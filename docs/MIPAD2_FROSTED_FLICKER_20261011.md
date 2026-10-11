# Mi Pad 2: Impeller / frosted Metro tile flicker, 2026-10-11

## Observed regression

The x5-Z8500/Cherry Trail i915 tablet running the original mobile Denial shell
logged bursts of `Impeller validation: Could not find font in the atlas` when
the global appearance transparency mode was `glass`. This persisted after
removing the experimental split-window feature. It therefore was not a
split-window-specific compositor defect.

The earlier Metro implementation nested a separate `BackdropFilter.grouped`
around every tile (including its fonts and animated foreground). Even grouped,
these layers forced Impeller GLES to repeatedly process per-tile filtered
offscreen text surfaces. Switching from opaque appearance to glass produced
83 font-atlas validation messages during one test window.

A 150-sample native DRM scanout probe observed the output always `On`, the
backlight value fixed at 255, and normal reuse of three primary framebuffer
IDs. Twenty software screenshots were visually static. Those observations
cannot rule out sub-frame hardware or panel flicker.

## Fix

The mobile page now paints ONE, GPU-bounded, sigma<=6 clipped backdrop layer
BEHIND the entire non-overlapping tile collection. Each tile then paints its
own translucent tint, reflection and text above the background. Tile geometry
and the blur clipper share the same layout computation. Normal opacity `off`
uses no backdrop at all.

This patch changes only the Flutter AOT UI, not the Rust compositor, i915
driver, Flutter engine or other user settings. It deliberately does not
reactivate the experimental multiwindow feature.

## Verification

- Pinned-engine Flutter tests: 3 new tile clipper/geometry checks passed;
  9 existing layout tests and 2 existing lock-profile tests passed.
- Release bundle built with the pinned Flutter engine.
- Device deployment: replaced **only** `libapp.so`.
  - Before: `b0a85345b692b0dc289cb6537b80cf3e64ec3ad2393e8ac87f0ce787befac51c`
  - After: `0aab74b4a6f73c1f1fd9271dc74b87a0dcb7345c23624d8adba2b6b1c462897a`
  - Compositor unchanged: `a1ca757fa6a346e0075fd1f6e2275bc29d520faecf8c83a521523a3a15183b68`
- Glass was enabled on the new build; **0 font-atlas errors observed in the
  recent 300-second journal window** (previous appearance A/B produced 83).
- The desktop screenshot rendered normally; a native GNOME text editor
  appeared correctly, then was closed.
- `denialctl status`: 1/1 output active; no new crash.
- A *separate*, existing compositor startup warning about
  `MissingAuthorization` can still appear and requires its own treatment.
- The user's physical-screen flicker perception still needs confirmation:
  software screenshot and journal probes cannot fully validate a real panel.

## Rollback

A dedicated AOT backup is saved as:

`/usr/lib/denial/flutter/lib/libapp.so.backup-pre-singlepass-20261011`

To restore the preceding original UI and restart the graphical login:

```sh
ssh mipad2 bash /home/user/denial-rollback-singlepass-20261011.sh
```

This restores the library atomically, checks its SHA-256, then restarts GDM.
The script is idempotent and exits without restarting if already restored.
It does not revert other user settings. Save unsaved documents before running.
