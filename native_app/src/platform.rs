use denial_flutter_engine::{EngineError, RunningEngine};

// Reuse these implementations verbatim. They are private Denial modules, so
// this prototype deliberately builds from the same checkout as its host crate.
#[allow(dead_code)]
#[path = "../../compositor/src/bin/deniald/flutter_runtime/mouse_cursor.rs"]
mod mouse_cursor;
#[allow(dead_code)]
#[path = "../../compositor/src/bin/deniald/flutter_runtime/text_input.rs"]
mod text_input;

#[derive(Default)]
pub struct Platform {
    text_input: text_input::TextInputPlugin,
    mouse_cursor: mouse_cursor::MouseCursorPlugin,
}

pub struct Reply {
    pub data: Vec<u8>,
    pub cursor: Option<&'static str>,
    pub close: bool,
}

impl Platform {
    pub fn handle(&mut self, channel: &str, data: &[u8]) -> Reply {
        let mut reply = Reply {
            data: Vec::new(),
            cursor: None,
            close: false,
        };
        match channel {
            "flutter/textinput" => reply
                .data
                .extend_from_slice(self.text_input.handle_platform_message(data)),
            "flutter/mousecursor" => {
                reply.data = self.mouse_cursor.handle_platform_message(data);
                reply.cursor = self.mouse_cursor.take_request();
            }
            "flutter/platform" => {
                if let Ok(call) = serde_json::from_slice::<serde_json::Value>(data) {
                    match call.get("method").and_then(|m| m.as_str()) {
                        Some("SystemNavigator.pop") => {
                            reply.close = true;
                            reply.data = b"[null]".to_vec();
                        }
                        Some(
                            "SystemChrome.setApplicationSwitcherDescription"
                            | "SystemChrome.setEnabledSystemUIMode"
                            | "SystemChrome.setSystemUIOverlayStyle",
                        ) => reply.data = b"[null]".to_vec(),
                        _ => {}
                    }
                }
            }
            _ => {} // Empty response means MethodNotImplemented, not success.
        }
        reply
    }

    pub fn text_key(
        &mut self,
        engine: &RunningEngine,
        code: u32,
        text: Option<&str>,
    ) -> Result<(), EngineError> {
        let mut characters = text.unwrap_or("").chars();
        let first = characters.next().map(u32::from).unwrap_or(0);
        for message in self.text_input.on_key_pressed(code, first) {
            engine.send_platform_message(text_input::CHANNEL, message)?;
        }
        for character in characters {
            for message in self.text_input.on_key_pressed(0, u32::from(character)) {
                engine.send_platform_message(text_input::CHANNEL, message)?;
            }
        }
        Ok(())
    }
}
