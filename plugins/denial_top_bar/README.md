# Denial top bar

First-party source plugin providing `ShellPanel`. Owns the existing bar layout,
CPU/GPU/battery cards, clock, workspace indicator, media controls, and their
animations. Existing top/bottom/left/right placement continues to work.

The package imports only the public Denial SDKs and Flutter dependencies. It has
no dependency on `dart_shell`, native bridges, or other private shell libraries.
Native state, commands, localization, cursors, image loading, and the existing
tray host are supplied through `ShellServices`. Settings and work-area placement
remain host-owned; this extraction does not introduce a multi-panel layout system.

`lib/denial_top_bar.dart` declares a `@Plugin()` library and
`@Provides(ShellPanel)` implementation. The annotations are metadata for the
future compiler-driven composition step, not executable registration.

The package remains a path dependency in `dart_shell/pubspec.yaml`. The manual
selection lives in `dart_shell/lib/src/features/default_shell/panel_composition.dart`;
it currently selects `denial_taskbar`. Select `const TopBarPlugin()` there to use
this presentation and the host-configured edge/thickness again. The small host in
`desktop_system_bar.dart` delegates rendering to the selected panel. The plugin manager,
automatic discovery, installation, and enable/disable controls are deferred.

Validate with `tools/denial-pc plugin-check`. A release `tools/denial-pc bundle`
compiles the actual integration; existing shell widget tests remain in
`dart_shell/test` and require the repository's explicit development-engine test
workflow. Visual validation belongs to the user.
