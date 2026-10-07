import 'package:flutter/widgets.dart';

import '../input/input_layout.dart';
import '../input/shell_interaction_registry.dart';
import '../models/denial_window.dart';
import '../platform/denial_bridge.dart';
import 'shell_state.dart';

Rect mobileWindowPresentationFrame({
  required Size viewSize,
  required Rect frame,
  required double contentOffset,
  required bool contain,
}) {
  if (viewSize.isEmpty || frame.isEmpty) {
    return Rect.zero;
  }
  final topInset = contain ? ShellMetrics.appStatusBarHeight : 0.0;
  final targetHeight = (viewSize.height - topInset).clamp(0.0, viewSize.height);
  final target = Rect.fromLTWH(
    0,
    topInset - contentOffset,
    viewSize.width,
    targetHeight,
  );
  final widthScale = target.width / frame.width;
  final heightScale = target.height / frame.height;
  final scale = contain
      ? (widthScale < heightScale ? widthScale : heightScale)
      : (widthScale > heightScale ? widthScale : heightScale);
  if (!scale.isFinite || scale <= 0.0) {
    return Rect.zero;
  }
  final width = frame.width * scale;
  final height = frame.height * scale;
  return Rect.fromLTWH(
    target.left + (target.width - width) / 2.0,
    target.top + (target.height - height) / 2.0,
    width,
    height,
  );
}

/// Publishes the mobile shell's immutable native input-routing snapshot.
class ShellInputLayoutCoordinator {
  ShellInputLayoutCoordinator(this._bridge);

  final DenialBridge _bridge;
  int _inputLayoutEpoch = 0;
  InputLayoutSnapshot? _lastInputLayoutSnapshot;

  void invalidate() {
    _lastInputLayoutSnapshot = null;
  }

  void publish({
    required ShellState state,
    required Size viewSize,
    required ShellInteractionSnapshot interactions,
  }) {
    if (viewSize.width <= 0 || viewSize.height <= 0) {
      return;
    }

    final quickSettingsActive =
        state.quickSettingsVisible || state.quickSettingsDragProgress > 0.0;
    final edgePanelActive =
        state.edgePanelVisible || state.edgePanelDragProgress > 0.0;
    final edgePanelProgress = state.edgePanelDragProgress;
    final edgePanelRect = ShellMetrics.edgePanelRect(
      viewSize,
      edgePanelProgress,
    );
    final softwareKeyboardRegions = ShellMetrics.softwareKeyboardRegions(
      viewSize,
      progress: edgePanelProgress,
      scrollStripVisible: false,
    );
    if (state.lockLayerVisible) {
      final lockBackgroundWindow = state.primaryWindow;
      _publishInputLayout(
        viewSize: viewSize,
        shellRegions: <Rect>[Offset.zero & viewSize],
        windows: <InputWindowRegion>[
          if (lockBackgroundWindow != null)
            InputWindowRegion(
              window: lockBackgroundWindow,
              rect: Offset.zero & viewSize,
              sourceRect: Offset.zero & viewSize,
              z: 0,
              hitTest: false,
            ),
        ],
        softwareKeyboardRegions: softwareKeyboardRegions,
        keyboardCapture: true,
        exclusiveShellMode: true,
      );
      return;
    }

    // The Windows-style touch keyboard overlays the app. Native hit testing
    // must therefore stay in the same unshifted coordinate space as the
    // visual window, regardless of any stale legacy viewport-pan state.
    const contentOffset = 0.0;
    final inputBottom = edgePanelActive
        ? edgePanelRect.top.clamp(0.0, viewSize.height).toDouble()
        : viewSize.height;
    final inputWindow = state.inputWindow;
    final canvas = Offset.zero & viewSize;
    final shellRegions = <Rect>[
      if (inputWindow == null ||
          state.overviewVisible ||
          state.launchTransitionActive ||
          quickSettingsActive ||
          interactions.capturesFullScene)
        canvas
      else if (edgePanelActive) ...[
        ShellMetrics.statusRect(viewSize),
        if (edgePanelRect.height > 0.0) edgePanelRect,
      ] else ...[
        ShellMetrics.statusRect(viewSize),
        ShellMetrics.gestureRect(viewSize),
        ShellMetrics.edgePanelGestureRect(viewSize),
      ],
      for (final region in interactions.childRegions)
        if (!region.intersect(canvas).isEmpty) region.intersect(canvas),
    ];

    final inputRegions = <InputWindowRegion>[
      if (inputWindow != null)
        ..._inputRegionsForWindow(
          window: inputWindow,
          viewSize: viewSize,
          contentOffset: contentOffset,
          inputBottom: inputBottom,
        ),
      ..._inputMethodPopupRegions(
        windows: state.windows,
        viewSize: viewSize,
        contentOffset: contentOffset,
        hitTest: !interactions.capturesFullScene && !quickSettingsActive,
      ),
    ];

    _publishInputLayout(
      viewSize: viewSize,
      shellRegions: shellRegions,
      windows: inputRegions,
      softwareKeyboardRegions: softwareKeyboardRegions,
      keyboardCapture: quickSettingsActive || interactions.capturesKeyboard,
      exclusiveShellMode: interactions.compositorExclusive,
    );
  }

  List<InputWindowRegion> _inputMethodPopupRegions({
    required List<DenialWindow> windows,
    required Size viewSize,
    required double contentOffset,
    required bool hitTest,
  }) {
    final canvas = Offset.zero & viewSize;
    final regions = <InputWindowRegion>[];
    for (final popup in windows) {
      final geometry = popup.geometry;
      final source = popup.contentCoordinateRect;
      if (!popup.isInputMethodPopup ||
          geometry == null ||
          geometry.isEmpty ||
          source.isEmpty) {
        continue;
      }
      final visual = geometry.shift(Offset(0, -contentOffset));
      final clipped = visual.intersect(canvas);
      if (clipped.isEmpty) {
        continue;
      }
      final scaleX = source.width / visual.width;
      final scaleY = source.height / visual.height;
      regions.add(
        InputWindowRegion(
          window: popup,
          surfaceId: popup.objectId,
          rect: clipped,
          sourceRect: Rect.fromLTWH(
            source.left + (clipped.left - visual.left) * scaleX,
            source.top + (clipped.top - visual.top) * scaleY,
            clipped.width * scaleX,
            clipped.height * scaleY,
          ),
          z: 1000000000,
          hitTest: hitTest,
          geometryLocked: true,
        ),
      );
    }
    return regions;
  }

  List<InputWindowRegion> _inputRegionsForWindow({
    required DenialWindow window,
    required Size viewSize,
    required double contentOffset,
    required double inputBottom,
  }) {
    final frame = window.presentationCoordinateRect;
    final content = window.contentCoordinateRect;
    if (frame.isEmpty || content.isEmpty) {
      return const <InputWindowRegion>[];
    }
    final cropTop = !window.isLocalFlutter && window.serverSideDecorated
        ? ShellMetrics.mobileNativeTitleBarCrop
        : 0.0;
    final maxCrop = (frame.height - 1.0).clamp(0.0, double.infinity);
    final clampedCropTop = cropTop.clamp(0.0, maxCrop).toDouble();
    final sourceFrame = clampedCropTop > 0.0
        ? Rect.fromLTRB(
            frame.left,
            frame.top + clampedCropTop,
            frame.right,
            frame.bottom,
          )
        : frame;
    final sourceContent = content.intersect(sourceFrame);
    if (sourceContent.isEmpty) {
      return const <InputWindowRegion>[];
    }
    // Match the texture's top-centred BoxFit.contain. This keeps fixed-size
    // and legacy clients fully visible instead of cropping them to the mobile
    // viewport, while retaining exact source-coordinate routing for touch.
    final fullContentRect = mobileWindowPresentationFrame(
      viewSize: viewSize,
      frame: sourceFrame,
      contentOffset: contentOffset,
      contain: !window.isLocalFlutter,
    );
    if (fullContentRect.isEmpty) {
      return const <InputWindowRegion>[];
    }
    final scale = fullContentRect.width / sourceFrame.width;
    final frameLeft = fullContentRect.left;
    final frameTop = fullContentRect.top;
    final clientRect = Rect.fromLTWH(
      frameLeft + (sourceContent.left - sourceFrame.left) * scale,
      frameTop + (sourceContent.top - sourceFrame.top) * scale,
      sourceContent.width * scale,
      sourceContent.height * scale,
    );
    final clip = Rect.fromLTRB(0, 0, viewSize.width, inputBottom);
    final rect = clientRect.intersect(clip);
    if (rect.isEmpty) {
      return const <InputWindowRegion>[];
    }
    final sourceRect = Rect.fromLTWH(
      sourceContent.left + (rect.left - clientRect.left) / scale,
      sourceContent.top + (rect.top - clientRect.top) / scale,
      rect.width / scale,
      rect.height / scale,
    );
    final regions = <InputWindowRegion>[];
    for (final popup in window.popupRoots.toList(growable: false).reversed) {
      final popupRect = window.mapSurfaceRect(
        popup,
        fullContentRect,
        sourceRect: sourceFrame,
      );
      final clipped = popupRect.intersect(clip);
      if (clipped.isEmpty ||
          popupRect.width <= 0.0 ||
          popupRect.height <= 0.0) {
        continue;
      }
      final scaleX = popup.surfaceWidth / popupRect.width;
      final scaleY = popup.surfaceHeight / popupRect.height;
      regions.add(
        InputWindowRegion(
          window: window,
          surfaceId: popup.surfaceId,
          rect: clipped,
          sourceRect: Rect.fromLTWH(
            (clipped.left - popupRect.left) * scaleX,
            (clipped.top - popupRect.top) * scaleY,
            clipped.width * scaleX,
            clipped.height * scaleY,
          ),
          z: popup.compositionOrder + 1,
          geometryLocked: true,
        ),
      );
    }
    regions.add(
      InputWindowRegion(
        window: window,
        // Route through the toplevel root so native hit testing can select an
        // input-capable subsurface rather than the current primary texture.
        surfaceId: window.objectId,
        rect: rect,
        sourceRect: sourceRect,
        z: 0,
        geometryLocked: true,
      ),
    );
    return regions;
  }

  void _publishInputLayout({
    required Size viewSize,
    required List<Rect> shellRegions,
    required List<InputWindowRegion> windows,
    List<Rect> softwareKeyboardRegions = const <Rect>[],
    bool keyboardCapture = false,
    bool exclusiveShellMode = false,
  }) {
    if (viewSize.width <= 0 || viewSize.height <= 0) {
      return;
    }

    final snapshot = InputLayoutSnapshot(
      epoch: _inputLayoutEpoch + 1,
      shellRegions: shellRegions,
      windows: windows,
      softwareKeyboardRegions: softwareKeyboardRegions,
      visibleSurfaceIds: <int>{
        for (final region in windows) ...region.window.visibleSurfaceIds,
      }.toList(growable: false),
      keyboardCapture: keyboardCapture,
      exclusiveShellMode: exclusiveShellMode,
    );
    if (_lastInputLayoutSnapshot?.hasSameRoutingAs(snapshot) ?? false) {
      return;
    }

    if (!_bridge.publishInputLayout(snapshot)) {
      return;
    }
    _inputLayoutEpoch = snapshot.epoch;
    _lastInputLayoutSnapshot = snapshot;
  }
}
