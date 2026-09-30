use std::{
    ffi::{CStr, c_void},
    sync::Mutex,
};

use denial_flutter_engine::{
    BackingStoreRequest, CompositorBackingStore, EngineEvent, OpenGlHandler, PresentFrame,
    PresentView, sys,
};
use smithay_client_toolkit::reexports::calloop::channel::Sender;
use wayland_client::{Connection, Proxy, protocol::wl_surface::WlSurface};
use wayland_egl::WlEglSurface;

use crate::{app::Event, egl::Egl};

#[allow(
    clippy::all,
    dead_code,
    unused_imports,
    non_upper_case_globals,
    non_snake_case,
    non_camel_case_types
)]
mod gl {
    include!(concat!(env!("OUT_DIR"), "/gles.rs"));
}

pub struct Renderer {
    // Destroy EGL first, then its wl_egl_window, then the underlying wl_surface.
    egl: Egl,
    state: Mutex<State>,
    events: Sender<Event>,
    _surface: WlSurface,
}

struct State {
    window: WlEglSurface,
    desired: (u32, u32),
    attached: (u32, u32),
    scale: u32,
    attached_scale: u32,
    targets: Vec<Target>,
}

struct Target {
    framebuffer: u32,
    texture: u32,
    stencil: u32,
    size: (u32, u32),
    borrowed: bool,
}

impl Renderer {
    pub fn new(
        connection: &Connection,
        surface: &WlSurface,
        size: (u32, u32),
        events: Sender<Event>,
    ) -> Result<Self, String> {
        let window = WlEglSurface::new(surface.id(), size.0 as i32, size.1 as i32)
            .map_err(|e| e.to_string())?;
        let egl = Egl::new(connection, &window)?;
        Ok(Self {
            egl,
            state: Mutex::new(State {
                window,
                desired: size,
                attached: size,
                scale: 1,
                attached_scale: 1,
                targets: Vec::new(),
            }),
            events,
            _surface: surface.clone(),
        })
    }

    pub fn resize(&self, size: (u32, u32), scale: u32) {
        let mut state = self.state.lock().unwrap();
        state.desired = size;
        state.scale = scale;
    }

    pub fn request_frame<State>(&self, qh: &wayland_client::QueueHandle<State>)
    where
        State: wayland_client::Dispatch<wayland_client::protocol::wl_callback::WlCallback, WlSurface>
            + 'static,
    {
        // Serialize empty commits with EGL's buffer commit. In particular,
        // buffer scale must never be committed with the previous-sized buffer.
        let _state = self.state.lock().unwrap();
        self._surface.frame(qh, self._surface.clone());
        self._surface.commit();
    }

    fn fail(&self, message: String) -> bool {
        let _ = self.events.send(Event::Error(message));
        false
    }

    fn publish(&self, framebuffer: u32) -> bool {
        let mut state = self.state.lock().unwrap();
        let Some(target) = state.targets.iter().find(|t| t.framebuffer == framebuffer) else {
            return self.fail("Flutter presented an unknown backing store".into());
        };
        // A queued frame can outlive a configure. Keep the last complete frame
        // until Flutter renders the new physical size, instead of stretching it.
        if target.size != state.desired {
            return true;
        }
        let (width, height) = target.size;
        let (mut read, mut draw) = (0, 0);
        // SAFETY: the render context is current and all FBOs belong to it. Save
        // every state changed by the blit so Impeller's state cache stays valid.
        unsafe {
            gl::GetIntegerv(gl::READ_FRAMEBUFFER_BINDING, &mut read);
            gl::GetIntegerv(gl::DRAW_FRAMEBUFFER_BINDING, &mut draw);
            let scissor = gl::IsEnabled(gl::SCISSOR_TEST) != 0;
            gl::Disable(gl::SCISSOR_TEST);
            gl::BindFramebuffer(gl::READ_FRAMEBUFFER, framebuffer);
            gl::BindFramebuffer(gl::DRAW_FRAMEBUFFER, 0);
            gl::BlitFramebuffer(
                0,
                0,
                width as i32,
                height as i32,
                0,
                0,
                width as i32,
                height as i32,
                gl::COLOR_BUFFER_BIT,
                gl::NEAREST,
            );
            gl::BindFramebuffer(gl::READ_FRAMEBUFFER, read as u32);
            gl::BindFramebuffer(gl::DRAW_FRAMEBUFFER, draw as u32);
            if scissor {
                gl::Enable(gl::SCISSOR_TEST);
            }
        }
        if state.attached_scale != state.scale {
            self._surface.set_buffer_scale(state.scale as i32);
            state.attached_scale = state.scale;
        }
        if !self.egl.swap() {
            return self.fail(crate::egl::last_error("swap Wayland buffer"));
        }
        let _ = self.events.send(Event::Presented);
        true
    }
}

impl OpenGlHandler for Renderer {
    fn make_current(&self) -> bool {
        self.egl.make_render_current()
    }
    fn clear_current(&self) -> bool {
        self.egl.clear_current()
    }
    fn make_resource_current(&self) -> bool {
        self.egl.make_resource_current()
    }
    fn framebuffer(&self, _: u32, _: u32) -> u32 {
        0
    } // All rendering uses FlutterCompositor's nonzero FBOs.
    fn present(&self, frame: PresentFrame<'_>) -> bool {
        // With FlutterCompositor, the root surface's zero-FBO callback only
        // completes the raster pass; present_view already published the pixels.
        frame.framebuffer == 0 || self.publish(frame.framebuffer)
    }
    fn resolve_proc(&self, name: &CStr) -> *mut c_void {
        Egl::resolve(name)
    }
    fn event(&self, event: EngineEvent) {
        let _ = self.events.send(Event::Engine(event));
    }

    fn create_backing_store(&self, request: BackingStoreRequest) -> Option<CompositorBackingStore> {
        if !self.make_current() {
            self.fail(crate::egl::last_error("acquire render context"));
            return None;
        }
        let mut state = self.state.lock().unwrap();
        if request.view_id != 0
            || (request.width, request.height)
                != (state.desired.0 as usize, state.desired.1 as usize)
        {
            return None;
        }
        if state.attached != state.desired {
            state
                .window
                .resize(state.desired.0 as i32, state.desired.1 as i32, 0, 0);
            state.attached = state.desired;
        }
        let size = state.desired;
        // Collect only allocations Flutter has released. Never recycle a live
        // lease across resize, even if the engine queues several raster tasks.
        state.targets.retain_mut(|target| {
            if !target.borrowed && target.size != size {
                target.destroy();
                false
            } else {
                true
            }
        });
        let index = match state
            .targets
            .iter()
            .position(|t| !t.borrowed && t.size == size)
        {
            Some(index) => index,
            None => {
                if state.targets.len() >= 3 {
                    return None;
                }
                match Target::new(size) {
                    Ok(target) => state.targets.push(target),
                    Err(error) => {
                        self.fail(error);
                        return None;
                    }
                }
                state.targets.len() - 1
            }
        };
        let target = &mut state.targets[index];
        target.borrowed = true;
        // The external-view embedder expects the supplied FBO to be current.
        // SAFETY: this target belongs to the current GLES3 render context.
        unsafe {
            gl::BindFramebuffer(gl::FRAMEBUFFER, target.framebuffer);
            gl::Viewport(0, 0, size.0 as i32, size.1 as i32);
        }
        Some(CompositorBackingStore {
            framebuffer: target.framebuffer,
            format: gl::RGBA8,
            user_data: target.framebuffer as usize,
        })
    }

    fn collect_backing_store(&self, store: CompositorBackingStore) -> bool {
        let mut state = self.state.lock().unwrap();
        let Some(target) = state.targets.iter_mut().find(|t| {
            t.framebuffer == store.framebuffer && store.user_data == t.framebuffer as usize
        }) else {
            return false;
        };
        target.borrowed = false;
        true
    }

    fn present_view(&self, view: PresentView<'_>) -> bool {
        let valid = self.state.lock().unwrap().targets.iter().any(|target| {
            target.framebuffer == view.backing_store.framebuffer
                && target.borrowed
                && view.backing_store.user_data == target.framebuffer as usize
                && view.width == target.size.0 as f64
                && view.height == target.size.1 as f64
        });
        if !valid || view.view_id != 0 || view.offset_x != 0.0 || view.offset_y != 0.0 {
            return self.fail("Only a single full-window Flutter view is supported".into());
        }
        self.publish(view.backing_store.framebuffer)
    }

    fn populate_existing_damage(&self, _: isize, damage: &mut Vec<sys::FlutterRect>) {
        let size = self.state.lock().unwrap().desired;
        damage.clear();
        damage.push(sys::FlutterRect {
            left: 0.0,
            top: 0.0,
            right: size.0 as f64,
            bottom: size.1 as f64,
        });
    }

    fn shutdown_on_render_thread(&self) -> bool {
        if !self.make_current() {
            return false;
        }
        for mut target in self.state.lock().unwrap().targets.drain(..) {
            target.destroy();
        }
        self.clear_current()
    }
}

impl Target {
    fn new(size: (u32, u32)) -> Result<Self, String> {
        let mut target = Self {
            framebuffer: 0,
            texture: 0,
            stencil: 0,
            size,
            borrowed: false,
        };
        let (mut texture, mut stencil, mut read, mut draw) = (0, 0, 0, 0);
        // SAFETY: callbacks execute with the GLES3 render context current.
        // Save bindings before allocation to preserve Flutter's cached GL state.
        let complete = unsafe {
            gl::GetIntegerv(gl::TEXTURE_BINDING_2D, &mut texture);
            gl::GetIntegerv(gl::RENDERBUFFER_BINDING, &mut stencil);
            gl::GetIntegerv(gl::READ_FRAMEBUFFER_BINDING, &mut read);
            gl::GetIntegerv(gl::DRAW_FRAMEBUFFER_BINDING, &mut draw);
            gl::GenTextures(1, &mut target.texture);
            gl::BindTexture(gl::TEXTURE_2D, target.texture);
            gl::TexParameteri(gl::TEXTURE_2D, gl::TEXTURE_MIN_FILTER, gl::NEAREST as i32);
            gl::TexParameteri(gl::TEXTURE_2D, gl::TEXTURE_MAG_FILTER, gl::NEAREST as i32);
            gl::TexParameteri(gl::TEXTURE_2D, gl::TEXTURE_WRAP_S, gl::CLAMP_TO_EDGE as i32);
            gl::TexParameteri(gl::TEXTURE_2D, gl::TEXTURE_WRAP_T, gl::CLAMP_TO_EDGE as i32);
            gl::TexImage2D(
                gl::TEXTURE_2D,
                0,
                gl::RGBA8 as i32,
                size.0 as i32,
                size.1 as i32,
                0,
                gl::RGBA,
                gl::UNSIGNED_BYTE,
                std::ptr::null(),
            );
            gl::GenRenderbuffers(1, &mut target.stencil);
            gl::BindRenderbuffer(gl::RENDERBUFFER, target.stencil);
            gl::RenderbufferStorage(
                gl::RENDERBUFFER,
                gl::DEPTH24_STENCIL8,
                size.0 as i32,
                size.1 as i32,
            );
            gl::GenFramebuffers(1, &mut target.framebuffer);
            gl::BindFramebuffer(gl::FRAMEBUFFER, target.framebuffer);
            gl::FramebufferTexture2D(
                gl::FRAMEBUFFER,
                gl::COLOR_ATTACHMENT0,
                gl::TEXTURE_2D,
                target.texture,
                0,
            );
            gl::FramebufferRenderbuffer(
                gl::FRAMEBUFFER,
                gl::DEPTH_STENCIL_ATTACHMENT,
                gl::RENDERBUFFER,
                target.stencil,
            );
            let complete = gl::CheckFramebufferStatus(gl::FRAMEBUFFER) == gl::FRAMEBUFFER_COMPLETE;
            gl::BindTexture(gl::TEXTURE_2D, texture as u32);
            gl::BindRenderbuffer(gl::RENDERBUFFER, stencil as u32);
            gl::BindFramebuffer(gl::READ_FRAMEBUFFER, read as u32);
            gl::BindFramebuffer(gl::DRAW_FRAMEBUFFER, draw as u32);
            complete
        };
        if !complete {
            target.destroy();
            return Err("RGBA8 Flutter framebuffer is incomplete".into());
        }
        Ok(target)
    }

    fn destroy(&mut self) {
        // SAFETY: called only with the owning render context current, after
        // Flutter releases its lease or while the engine drains shutdown.
        unsafe {
            gl::DeleteFramebuffers(1, &self.framebuffer);
            gl::DeleteTextures(1, &self.texture);
            gl::DeleteRenderbuffers(1, &self.stencil);
        }
        self.framebuffer = 0;
        self.texture = 0;
        self.stencil = 0;
    }
}
