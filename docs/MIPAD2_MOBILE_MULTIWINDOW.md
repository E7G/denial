# Mi Pad 2 — mobile split-screen and floating windows

The Denial **mobile** shell keeps Android-like single-app fullscreen as its default.
A compact four-square `Window` icon appears near the top-right of an open app.
Tap it to expand three actions:

| Action | Behavior |
| --- | --- |
| 分屏 (Split) | Place the current app alongside the most recent other unminimized app. With no second app open, return to Home and launch one to fill the second slot. |
| 小窗 (Floating) | Move the current app into a freeform window over the previous open app (or Home if none). |
| 全屏 (Fullscreen) | Return to the original mobile single-window geometry. |

* Portrait: split top/bottom. Landscape: split left/right.
* Drag the narrow divider to adjust split sizes (30–70%).
* Drag the dark 32-logical-pixel floating title strip to move the window.
* Drag the floating window's lower-right grip to resize it.
* The floating title strip also provides a fullscreen shortcut.
* Screens rotate without losing the relative floating position. Window geometry is
  clamped to the new output bounds.
* Both visible apps have independent Wayland input regions and real native
  configured client sizes. The active keyboard focus still belongs to one
  client at a time.

## Implementation and constraints

The split/floating state is kept in `mobileMultiWindowProvider`. Only the
mobile shell uses it; desktop window layouts remain unchanged. The
`MobileWindowOverride` marker is set by an **explicit native window configure**
from the embedded shell and never by the client itself. Normal non-exact
configures clear the marker and restore original mobile fullscreen behavior.
Input is routed from the exact on-screen client rectangles rather than simply
painting fullscreen textures smaller.

Current deliberately scoped limitations:

* Two active application viewports are supported (side-by-side, or one floating
  above another); multiple independent overlapping floating windows and PiP
  video controls are not implemented.
* A single floating app can appear above Home; Home interaction remains
  disabled under it to avoid sending touches to the wrong client.
* The multiwindow arrangement is session-local, not persisted across logout.
* Apps enforcing their own minimum sizes may internally letterbox or decline
  resizing. Their input is mapped to the displayed client content.
* A full touchscreen/OSK/rotation regression on real hardware remains
  necessary; the release build and pure-geometry tests alone are not sufficient
  to certify every app.

## Developer verification

```sh
tools/denial-pc flutter-test \
  test/state/mobile_multi_window_layout_test.dart \
  test/state/mobile_window_presentation_frame_test.dart \
  test/widgets/lock_profile_layout_test.dart
tools/denial-pc bundle
tools/denial-pc compositor
```

On the **Mi Pad 2** deployed 2026-10-11, restore the preceding frosted-glass
build (without changing user data/settings) using:

```sh
ssh mipad2 bash /home/user/denial-rollback-multiwindow-20261011.sh
```

The rollback uses a dedicated backup captured immediately before installation.
It restarts GDM and therefore ends the current graphical session. Back up
unsaved application documents before executing the rollback.
