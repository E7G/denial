# Denial Flutter SDK

Flutter-facing contracts for source plugins. Depends on `denial_sdk`, Flutter,
and Riverpod; never on `dart_shell` or a default plugin.

| Library | Purpose |
| --- | --- |
| `panels.dart` | Typed `ShellPanel`, optional fixed `PanelPlacement`, and `PanelEdge` |
| `services.dart` | Injected native service reads/actions and localized strings |
| `theme.dart` | Shared theme, motion, colors, typography, and wallpaper accent |
| `effects.dart` | Shared backdrop blur presentation |
| `input.dart` | Shell input-region registration used by native hit testing |

The first consumer is [denial_top_bar](../../plugins/denial_top_bar/README.md).
`ShellPanel.build` receives an output ID, edge, and `ShellServices`. The runtime
owns provider lifetimes, native actions, output placement, and work-area
reservations. Plugins use the supplied listenables with ordinary Riverpod
subscriptions, including `select`; they do not receive private controllers.

`ShellServicesScope` passes those explicitly supplied dependencies down a widget
subtree. It is not plugin discovery or a runtime contribution registry. The tray
presentation is currently a reusable host component exposed through
`buildSystemTray`; its native protocol and menu ownership remain in the runtime.

Existing shell imports re-export the moved theme and input libraries so the
runtime and plugins share the same types, inherited theme, provider instances,
and input registry. Do not copy these implementations into plugins.

These are initial repository-local APIs, not an API-stability promise. General
multi-panel placement/reservation, generated composition, and plugin management
remain future work. See [the architecture](../../docs/PLUGIN_SYSTEM.md).

Validate the Flutter SDK and first-party plugin packages without a development engine:

```sh
tools/denial-pc plugin-check
```

The taskbar adds public application-window projections, activation, launcher
access, and application-icon presentation. Tray presentation optionally wraps icons
for overflow panels. `PanelPlacement` supplies a fixed edge/thickness when needed;
null preserves configured placement. The host must use that placement for both
native work-area reservation and Flutter geometry, not just paint a panel elsewhere.

`PanelPlacement.reserveWindowSpacing` opts into reserving the configured window
spacing next to a panel. `reservedThickness` includes that spacing for native and
Flutter work areas; the host paints the panel at its original thickness, aligned
to the output edge. This preserves existing placement for panels that do not opt in.
