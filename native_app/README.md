# Minimal native Flutter app runner

`denial-app` runs an existing release AOT bundle in its own Wayland process.
It reuses Denial's raw engine host, text editor and cursor decoder unchanged.
There are no changes to the compositor, SDK, Flutter engine or app Dart code.

The rendering path is Flutter → reusable RGBA8 framebuffer → GPU blit →
alpha-capable EGL/Wayland window. Denial still supplies the desktop glass.
The runner preserves the application's alpha; it does not synthesize blur.
Before graphics startup, it appends `-GL_EXT_shader_framebuffer_fetch` to
`MESA_EXTENSION_OVERRIDE`, preserving other overrides. This avoids the engine
buffer transition that corrupts layers below the final backdrop filter on .188.
The workaround affects this app process; Denial's shell keeps its capabilities.
Old-size frames are discarded during resize. Frame callbacks pace animation;
the event loop sleeps until Wayland events or engine task deadlines arrive.

Build from the repository root (native dependencies: Wayland, EGL, GLES3,
libxkbcommon):

```sh
cargo build --manifest-path native_app/Cargo.toml --release --locked
cargo test --manifest-path native_app/Cargo.toml --locked
cargo clippy --manifest-path native_app/Cargo.toml --all-targets --locked -- -D warnings
```

Run from an existing Wayland terminal:

```sh
native_app/target/release/denial-app \
  --bundle settings_app/build/linux/x64/release/bundle \
  --engine dart_shell/build/linux/x64/release/bundle/lib/libflutter_engine.so \
  --app-id dev.denial.Settings --title Settings
```

`--check` validates bundle components, AOT loading and the raw engine ABI
without starting Flutter or opening a window. Impeller is the default.
This repository builds Slimpeller, so Skia is unavailable in its engine.

Initial scope: one window/view and seat, integer display scaling, resize,
pointer/buttons/scrolling, keyboard layout/compose/repeat, basic text editing,
cursor shapes and window close. Accessibility, external IME, clipboard,
file dialogs, activation/single-instance handling, touch and GTK plugins are
omitted. Dart entrypoint arguments are not exposed by the reused host, so
the existing Settings bundle's `--welcome` mode is not available yet.
Plugin Manager needs its existing installation descriptor beside the runner.

The source inclusion of the two private input modules is deliberate read-only
reuse for this first version. A small transaction type adapter satisfies the
text editor's import. This creates a checkout dependency, not a new public SDK
contract; extracting those modules later would require a separate Denial change.

Difficulty: moderate for this MVP because engine startup and platform logic
already exist. Correct GPU ownership, resize commits and scheduling are the
hard parts. Broader platform-plugin compatibility is a larger follow-up.
The user validated correct rendering and glass on .188 with framebuffer fetch
disabled on 2026-09-30. The GTK Settings/Welcome and Plugin Manager runners apply
the same process-local workaround.
