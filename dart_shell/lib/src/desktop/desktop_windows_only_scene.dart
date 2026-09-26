part of 'desktop_shell.dart';

extension _DesktopWindowsOnlyScene on _DesktopSceneState {
  /// Deliberately reuses the production window widgets. This experiment
  /// measures the cost of the surrounding shell, not a new window renderer.
  Widget _buildWindowsOnlyScene({
    required List<DesktopWindowPlacement> placements,
    required Map<int, DenialWindow> windowsById,
    required List<DenialWindow> popupSurfaces,
    required int topZ,
  }) {
    final displayLayout = widget.displayLayout;
    final canvas = Offset.zero & widget.viewSize;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final switcher = widget.windowSwitcher;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep the original no-wallpaper baseline available independently of
        // the wallpaper-backed scene used to inspect window shadows.
        if (desktopDiagnosticWallpaper) const ShellWallpaper(),
        for (final surface in widget.layerSurfaces)
          if (surface.contentKind ==
                  DenialWindowContentKind.layerShellBackground ||
              surface.contentKind == DenialWindowContentKind.layerShellBottom)
            _DesktopLayerShellSurface(
              key: ValueKey<String>('layer-shell-${surface.surfaceId}'),
              surface: surface,
              displayLayout: displayLayout,
            ),
        ..._buildDesktopWindowLayers(
          placements: placements,
          windowsById: windowsById,
          desktop: widget.desktop,
          desktopPlane: false,
          minimizeLayerHandoff: _minimizeLayerHandoff,
          minimizedPlacementTransition: _minimizedPlacementTransition,
          minimizedPlacementExitFrames: _minimizedPlacementExitFrames,
          minimizeOffscreenBounds: canvas,
          minimizedWindowPlacement: widget.minimizedWindowPlacement,
          desktopWidgetFrames: const <int, Rect>{},
          switcher: switcher,
          switcherStageBounds: switcher == null
              ? Rect.zero
              : _windowSwitcherStageBounds(
                  viewSize: widget.viewSize,
                  displayLayout: displayLayout,
                  desktop: widget.desktop,
                  switcher: switcher,
                ),
          topZ: topZ,
          reduceMotion: reduceMotion,
          displayLayout: displayLayout,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          windowRevealRegistry: _windowRevealRegistry,
          onActivateWindow: widget.onActivateWindow,
          onCloseWindow: widget.onCloseWindow,
          onBeginOverviewDrag: widget.onBeginOverviewDrag,
          onUpdateOverviewDrag: widget.onUpdateOverviewDrag,
          onEndOverviewDrag: widget.onEndOverviewDrag,
          onCancelOverviewDrag: widget.onCancelOverviewDrag,
        ),
        for (final popup in popupSurfaces)
          if (popup.geometry case final geometry?)
            Positioned.fromRect(
              key: ValueKey<String>('desktop-popup-surface-${popup.objectId}'),
              rect: geometry,
              child: IgnorePointer(
                child: WindowSurfaceTree(
                  window: popup,
                  includePopups: true,
                  presentationScale: desktopOutputPixelGridForMonitor(
                    displayLayout,
                    popup.monitorId,
                  )?.scale,
                  pixelGridOrigin:
                      desktopOutputPixelGridForMonitor(
                        displayLayout,
                        popup.monitorId,
                      )?.logicalRect.topLeft ??
                      Offset.zero,
                ),
              ),
            ),
        for (final surface in widget.layerSurfaces)
          if (surface.contentKind == DenialWindowContentKind.layerShellTop ||
              surface.contentKind == DenialWindowContentKind.layerShellOverlay)
            _DesktopLayerShellSurface(
              key: ValueKey<String>('layer-shell-${surface.surfaceId}'),
              surface: surface,
              displayLayout: displayLayout,
            ),
      ],
    );
  }
}
