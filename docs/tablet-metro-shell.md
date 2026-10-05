# Denial Tablet Metro shell

This branch turns Denial's existing mobile shell into a touch-first tablet shell
inspired by Square Home and the Windows 8 / Surface RT Start screen while
keeping Denial's compositor, window lifecycle, overview, shade and input model.

## What changes

- Square Metro tiles replace the icon-grid look on the mobile home surface.
- Application tiles can be resized from 1x1 up to 2x2 and keep their size
  across desktop-entry refreshes and saved-layout reloads.
- Long press enters edit/resize mode; moving the held tile still reuses
  Denial's existing cross-page drag/reorder behavior.
- Tablet-width outputs get a Windows 8-style Start header.
- **All apps** opens a full-screen searchable app drawer. Swipe down or use
  the back arrow to return to Start.
- Existing Denial mobile features remain intact: status bar, notifications,
  quick settings, wallpaper, launch transitions, recent-app overview,
  home/recents gesture pill and horizontal app switching.

## Enable the mobile/tablet shell

Use Denial's normal mobile profile:

```sh
export DENIAL_SHELL_PROFILE=mobile
```

The Metro Start header is enabled automatically on viewports at least 700
logical pixels wide. Narrow mobile viewports keep the compact layout.

## Current scope

This is the first functional tablet shell pass. The clock tile already uses
live system data through Denial's existing provider. Application tiles are
currently visual launch tiles; richer Square Home-style live tile providers,
per-tile color controls, tile groups/folders, widget picking and a dedicated
tablet settings page are intended follow-up work.
