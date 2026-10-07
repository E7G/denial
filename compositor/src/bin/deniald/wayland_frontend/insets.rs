//! Per-surface opt-out and native mobile client geometry.

use super::managed_window::ManagedWindow;
use super::*;
use smithay::reexports::wayland_server::{Client, DataInit, Dispatch, GlobalDispatch, New};

pub mod protocol {
    pub mod server {
        #![allow(
            dead_code,
            non_camel_case_types,
            non_upper_case_globals,
            non_snake_case,
            unused_imports,
            unused_unsafe,
            unused_variables,
            clippy::all,
            missing_docs
        )]
        use wayland_server;
        use wayland_server::protocol::*;
        pub mod __interfaces {
            use wayland_server::backend as wayland_backend;
            use wayland_server::protocol::__interfaces::*;
            wayland_scanner::generate_interfaces!("protocol/denial-insets-v1.xml");
        }
        use self::__interfaces::*;
        wayland_scanner::generate_server_code!("protocol/denial-insets-v1.xml");
    }
}

use protocol::server::denial_insets_manager_v1::{self, DenialInsetsManagerV1};

/// Matches the mobile status bar's logical height. Output scaling is applied
/// by the ordinary client configure/viewport and native texture projection.
pub(super) const MOBILE_STATUS_INSET: i32 = 48;

struct SelfManagedInsets;

pub(super) fn self_managed(surface: &WlSurface) -> bool {
    with_states(surface, |states| {
        states.data_map.get::<SelfManagedInsets>().is_some()
    })
}

pub(super) fn init(display: &DisplayHandle) {
    display.create_global::<RuntimeState, DenialInsetsManagerV1, _>(1, ());
}

impl GlobalDispatch<DenialInsetsManagerV1, ()> for RuntimeState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<DenialInsetsManagerV1>,
        _data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<DenialInsetsManagerV1, ()> for RuntimeState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &DenialInsetsManagerV1,
        request: denial_insets_manager_v1::Request,
        _data: &(),
        _handle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            denial_insets_manager_v1::Request::SetSelfManaged { surface } => {
                if self_managed(&surface) {
                    return;
                }
                if with_renderer_surface_state(&surface, |state| state.buffer().is_some())
                    .unwrap_or(false)
                {
                    resource.post_error(
                        denial_insets_manager_v1::Error::MappedSurface,
                        "declare self-managed insets before attaching the initial buffer",
                    );
                    return;
                }
                with_states(&surface, |states| {
                    states
                        .data_map
                        .insert_if_missing_threadsafe(|| SelfManagedInsets);
                });
                if let Some(frontend) = state.wayland.as_mut()
                    && let Some(window) = frontend.window_for_root_surface(&surface)
                {
                    frontend.configure_mobile_window(&window);
                }
                state.scene_sync.mark_dirty();
            }
            denial_insets_manager_v1::Request::Destroy => {}
        }
    }
}

impl WaylandFrontend {
    pub(super) fn mobile_window_geometry(
        &self,
        window: &Window,
    ) -> Option<Rectangle<i32, Logical>> {
        if !self.mobile_shell
            || ManagedWindow::new(window).is_some_and(|window| window.facts().override_redirect)
        {
            return None;
        }
        let root = self.window_root_surface(window)?;
        let system_ui = window.toplevel().is_some_and(|toplevel| {
            with_states(toplevel.wl_surface(), |states| {
                let Some(data) = states.data_map.get::<XdgToplevelSurfaceData>() else {
                    return false;
                };
                let data = data.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                data.app_id
                    .as_deref()
                    .into_iter()
                    .chain(data.title.as_deref())
                    .any(|name| name == "denia-home" || name.starts_with("denia-systemui"))
            })
        });
        if system_ui {
            return None;
        }
        let mut geometry = self
            .output_for_geometry(self.window_geometry_target(window))
            .map(|output| output.logical_geometry)
            .or_else(|| self.fallback_output_geometry())?;
        let top = if self_managed(&root) {
            0
        } else {
            MOBILE_STATUS_INSET.min((geometry.size.h - 1).max(0))
        };
        geometry.loc.y += top;
        geometry.size.h -= top;
        Some(geometry)
    }

    pub(super) fn configure_mobile_window(&mut self, window: &Window) {
        let Some(target) = self.mobile_window_geometry(window) else {
            return;
        };
        if self.exact_window_geometry(window) == Some(target) {
            return;
        }
        if let Some(toplevel) = window.toplevel() {
            toplevel.with_pending_state(|pending| {
                pending.size = Some(target.size);
                pending.states.unset(xdg_toplevel::State::Fullscreen);
                pending.states.unset(xdg_toplevel::State::Maximized);
            });
            toplevel.send_pending_configure();
        }
        self.set_window_geometry_target_with_authority(
            window,
            target,
            WindowGeometryAuthority::Exact,
        );
    }

    pub(super) fn clip_mobile_surface_tree_to_content(
        &self,
        window: &Window,
        content: Rectangle<i32, Logical>,
        layers: &mut [SurfaceLayerDescription],
        textures: &mut [ExternalTextureFrame],
    ) {
        if !self.mobile_shell || self.mobile_window_geometry(window).is_none() {
            return;
        }
        let Some(root_id) = self
            .window_root_surface(window)
            .and_then(|root| self.surface_id(&root))
        else {
            return;
        };
        for layer in layers
            .iter_mut()
            .filter(|layer| layer.popup_root_surface_id == 0)
        {
            clip_layer_to_content(layer, content, layer.surface_id == root_id);
            if layer.texture_id == 0
                && let Some(texture) = textures
                    .iter_mut()
                    .find(|texture| texture.texture_id == layer.surface_id as i64)
            {
                texture.expects_sample = false;
            }
        }
    }
}

fn clip_layer_to_content(
    layer: &mut SurfaceLayerDescription,
    content: Rectangle<i32, Logical>,
    root: bool,
) {
    if layer.surface_width <= 0.0 || layer.surface_height <= 0.0 {
        return;
    }
    let left = layer.surface_x.max(f64::from(content.loc.x));
    let top = layer.surface_y.max(f64::from(content.loc.y));
    let right =
        (layer.surface_x + layer.surface_width).min(f64::from(content.loc.x + content.size.w));
    let bottom =
        (layer.surface_y + layer.surface_height).min(f64::from(content.loc.y + content.size.h));
    if right <= left || bottom <= top {
        if root {
            layer.surface_width = 0.0;
            layer.surface_height = 0.0;
            layer.texture_source_width = 0.0;
            layer.texture_source_height = 0.0;
        } else {
            layer.texture_id = 0;
        }
        return;
    }
    let sx = layer.texture_source_width / layer.surface_width;
    let sy = layer.texture_source_height / layer.surface_height;
    layer.texture_source_x += (left - layer.surface_x) * sx;
    layer.texture_source_y += (top - layer.surface_y) * sy;
    layer.surface_x = left;
    layer.surface_y = top;
    layer.surface_width = (right - left).max(0.0);
    layer.surface_height = (bottom - top).max(0.0);
    layer.texture_source_width = layer.surface_width * sx;
    layer.texture_source_height = layer.surface_height * sy;
}
