# Denial Tablet Metro shell

This branch turns Denial's mobile shell into a touch-first tablet shell inspired
by Square Home and the Windows 8 / Surface RT Start screen while keeping
Denial's Rust/Smithay compositor, window lifecycle, overview, shade and input
model intact.

## Tablet experience

- Metro/Square Home style Start screen with deterministic accent tiles.
- Application tiles support 1x1, 2x1, 1x2 and 2x2 sizes.
- Long press enters edit mode with large touch targets for:
  - remove from Start;
  - cycle the tile color;
  - resize;
  - drag/reorder, including cross-page movement.
- Tile size, color, position and folder data survive restart.
- Layout persistence is versioned and backward-compatible with older saved
  layouts.
- New applications appear in **All apps** and are not automatically pinned to
  Start after the user already has a saved layout.
- A clean first-run Start layout contains live system tiles plus a small starter
  app set instead of every installed application.

## Live tiles

The shell now ships built-in live tiles backed by Denial's existing providers:

- clock and date;
- battery/charging state;
- Wi-Fi state, connected SSID and signal strength.

System live tiles can be pinned/unpinned just like applications and can be
resized or recolored.

## All apps and folders

**All apps** is a searchable, full-screen application drawer.

- Tap an application to launch it.
- Long press or tap the pin control to pin/unpin it from Start.
- System tiles are exposed in their own section.
- **Folder** mode allows selecting two or more applications and creating a
  named Square Home-style folder tile.
- Folder tiles show miniature child-app previews and can be resized, recolored,
  moved or removed.
- Opening a folder shows a touch-friendly app grid; its name can be edited
  directly.
- Folder names and child application IDs are persisted in layout format v4.
- Removed applications are pruned from folders during desktop-entry refresh.

## Tablet Metro settings

Settings now contains a dedicated **Tablet Metro** page. Its values are stored
in Denial's normal settings document (schema v29).

Available controls:

- enable/disable the Metro tablet presentation;
- compact / comfortable / spacious tile density;
- tile opacity;
- show/hide the wide-screen Start header;
- show/hide system tiles;
- show/hide the Quick Settings gesture hint;
- compact portrait layout;
- gesture navigation or Android-style Back/Home/Overview buttons;
- launcher animation strength;
- reset Start to the safe default layout.

The new interface is integrated with Denial's English and Simplified Chinese
localization resources.

## Navigation and system integration

Denial's existing mobile capabilities remain intact:

- status bar;
- notifications and Quick Settings shade;
- wallpaper;
- launch transitions;
- recent-app overview;
- horizontal app switching;
- gesture navigation.

When three-button navigation is selected, the buttons reuse Denial's existing
shell state machine. Back closes launcher folders/All apps first, then shell
overlays/Overview, and finally falls back to Home for ordinary Linux
applications instead of injecting arbitrary keyboard events.

## Layout behavior

Use the normal mobile shell profile:

```sh
export DENIAL_SHELL_PROFILE=mobile
```

Tablet presentation activates on wide viewports. Portrait mode can use a
denser layout automatically; narrower phone-sized viewports retain the compact
mobile presentation.

## Validation

The branch is checked with:

- Dart formatter and `git diff --check`;
- `flutter analyze` using Denial's pinned Flutter dependency set;
- `tools/denial-pc flutter-test` with the lock-matched custom
  `flutter_tester`, never stock `flutter test`.

The custom-engine test path covers launcher layout/resize/paging and settings
serialization regressions, including saved Start authority and folder restore
behavior.
