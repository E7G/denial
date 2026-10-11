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

## 2026-10-11 regression investigation

**Deployment status: NOT ACTIVE.** The initial multiwindow build caused
single-app touch failures. A nested Dart collection-if/else attached the
fullscreen input route to the wrong branch, yielding **zero ordinary client
input regions**. The safe branch fixes this and adds a regression test.

Further safeguards: unchanged single-app mode no longer emits native window
configuration commands; the mobile-window reset compares against the actual
configured client geometry rather than its own target; and the permanent menu
icon no longer depends on the font atlas.

The release still needs live testing before re-enabling multiwindow on the
Mi Pad 2. Both the original and patched builds logged repeated
`Impeller validation: Could not find font in the atlas` on the tablet.
This also occurs on the previously working baseline. A brief Skia backend
experiment showed a black screen and was immediately reverted. Therefore,
the font-atlas issue must be investigated separately from input routing.

**The tablet currently runs the preceding frosted-glass build.**
Verify before modifying the device:

```sh
ssh mipad2 sha256sum /usr/bin/deniald /usr/lib/denial/flutter/lib/libapp.so
# a1ca757fa6a346e0075fd1f6e2275bc29d520faecf8c83a521523a3a15183b68
# b0a85345b692b0dc289cb6537b80cf3e64ec3ad2393e8ac87f0ce787befac51c
```

The idempotent rollback script (run **only if** the active build differs):

```sh
ssh mipad2 bash /home/user/denial-rollback-multiwindow-20261011.sh
```

Rollback retains a dedicated backup captured before installing multiwindow.
If a change is necessary, it restarts GDM and ends the graphical session;
save unsaved documents first. When already on the stable build, it exits
without restarting anything.
