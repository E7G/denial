import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../input/shell_interaction_registry.dart';
import '../../models/denial_window.dart';
import '../../state/mobile_multi_window.dart';
import '../../state/shell_controller.dart';
import '../../widgets/window_content_rect.dart';

/// Multi-window presentation shares the same native client geometry and
/// Flutter layout rectangles. Never scale an interactive client independently.
class MobileMultiWindowStage extends ConsumerStatefulWidget {
  const MobileMultiWindowStage({super.key});

  @override
  ConsumerState<MobileMultiWindowStage> createState() =>
      _MobileMultiWindowStageState();
}

class _MobileMultiWindowStageState
    extends ConsumerState<MobileMultiWindowStage> {
  final Map<int, Rect> _lastGeometry = {};
  final Map<int, DenialWindow> _lastWindows = {};
  bool _syncQueued = false;
  Size _pendingSize = Size.zero;
  MobileMultiWindowState _pendingLayout = const MobileMultiWindowState();
  Map<int, DenialWindow> _pendingWindows = {};

  void _syncGeometry(
    Size size,
    MobileMultiWindowState layout,
    Map<int, DenialWindow> windows,
  ) {
    _pendingSize = size;
    _pendingLayout = layout;
    _pendingWindows = windows;
    if (_syncQueued) return;
    _syncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncQueued = false;
      if (!mounted) return;
      final bridge = ref.read(denialBridgeProvider);
      final next = _pendingLayout.windowRects(_pendingSize);
      for (final id in _lastGeometry.keys.toList()) {
        if (!next.containsKey(id)) {
          final window = _lastWindows[id];
          if (window != null && _pendingWindows[id] != null) {
            // Non-exact configure is the native mobile full-screen reset.
            bridge.configureWindow(window, window.contentCoordinateRect);
          }
          _lastGeometry.remove(id);
          _lastWindows.remove(id);
        }
      }
      for (final entry in next.entries) {
        final window = _pendingWindows[entry.key];
        if (window == null || entry.value.isEmpty) {
          continue;
        }
        if (_lastGeometry[entry.key] == entry.value &&
            _lastWindows[entry.key]?.windowId == window.windowId) {
          continue;
        }
        bridge.configureWindow(window, entry.value, exact: true);
        _lastGeometry[entry.key] = entry.value;
        _lastWindows[entry.key] = window;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(mobileMultiWindowProvider);
    // Normal single-app mode must not configure any native windows. In the
    // original implementation this widget sent a resize for every app when it
    // first appeared, even though multi-window had never been enabled.
    if (layout.mode == MobileMultiWindowMode.single && _lastGeometry.isEmpty) {
      return const SizedBox.shrink();
    }
    final shell = ref.watch(shellControllerProvider);
    final windows = {
      for (final window in shell.openAppWindows) window.objectId: window,
    };
    final size = MediaQuery.sizeOf(context);
    _syncGeometry(size, layout, windows);
    final rects = layout.windowRects(size);
    if (rects.isEmpty ||
        shell.overviewVisible ||
        shell.lockLayerVisible ||
        shell.launchTransitionActive) {
      return const SizedBox.shrink();
    }
    final foreground = layout.primaryId;
    final orderedIds = [
      if (layout.secondaryId case final id? when rects.containsKey(id)) id,
      if (foreground case final id? when rects.containsKey(id)) id,
    ];
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          for (final id in orderedIds)
            if (windows[id] case final window?)
              Positioned.fromRect(
                key: ValueKey('multiwindow-$id'),
                rect: rects[id]!,
                child: RepaintBoundary(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF151820),
                      borderRadius: BorderRadius.circular(
                        layout.mode == MobileMultiWindowMode.floating &&
                                id == foreground
                            ? 8
                            : 0,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        layout.mode == MobileMultiWindowMode.floating &&
                                id == foreground
                            ? 8
                            : 0,
                      ),
                      child: WindowContentRect(
                        window: window,
                        active: shell.foregroundObjectId == id,
                        fit: window.isLocalFlutter
                            ? BoxFit.cover
                            : BoxFit.contain,
                        alignment: Alignment.center,
                        cropToContentBounds: true,
                        allowPopupOverflow: false,
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class MobileMultiWindowControls extends ConsumerStatefulWidget {
  const MobileMultiWindowControls({super.key});

  @override
  ConsumerState<MobileMultiWindowControls> createState() =>
      _MobileMultiWindowControlsState();
}

class _MobileMultiWindowControlsState
    extends ConsumerState<MobileMultiWindowControls> {
  bool _expanded = false;

  void _split() {
    final shell = ref.read(shellControllerProvider);
    final current = shell.foregroundWindow;
    if (current == null) return;
    final partner = shell.openAppWindows
        .where(
          (window) => window.objectId != current.objectId && !window.minimized,
        )
        .toList(growable: false);
    ref
        .read(mobileMultiWindowProvider.notifier)
        .startSplit(
          current.objectId,
          partner.isEmpty ? null : partner.last.objectId,
        );
    if (partner.isEmpty) {
      // Choosing a second app from Home also works when recents is empty.
      ref.read(shellControllerProvider.notifier).goHome();
    }
    setState(() => _expanded = false);
  }

  void _floating() {
    final shell = ref.read(shellControllerProvider);
    final id = shell.foregroundObjectId;
    if (id == null) return;
    final behind = shell.openAppWindows
        .where((window) => window.objectId != id && !window.minimized)
        .toList(growable: false);
    ref
        .read(mobileMultiWindowProvider.notifier)
        .startFloating(
          id,
          backgroundId: behind.isEmpty ? null : behind.last.objectId,
        );
    setState(() => _expanded = false);
  }

  void _restore() {
    ref.read(mobileMultiWindowProvider.notifier).restore();
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final shell = ref.watch(shellControllerProvider);
    final layout = ref.watch(mobileMultiWindowProvider);
    if ((shell.foregroundWindow == null &&
            layout.mode != MobileMultiWindowMode.floating) ||
        shell.overviewVisible ||
        shell.lockLayerVisible ||
        shell.launchTransitionActive) {
      return const SizedBox.shrink();
    }

    final size = MediaQuery.sizeOf(context);
    final isSplit =
        layout.mode == MobileMultiWindowMode.split &&
        !layout.selectingPartner &&
        layout.secondaryId != null;
    final isFloating = layout.mode == MobileMultiWindowMode.floating;
    final frame = layout.floatingFrame(size);
    final bounds = layout.usableBounds(size);

    Widget action(IconData icon, String label, VoidCallback onTap) => Tooltip(
      message: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 19),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Positioned.fill(
      child: Stack(
        children: [
          if (isSplit)
            Positioned(
              left: bounds.width > bounds.height
                  ? bounds.width * layout.splitFraction - 12
                  : 0,
              top: bounds.width > bounds.height
                  ? bounds.top
                  : bounds.top +
                        (bounds.height - 8) * layout.splitFraction -
                        12,
              width: bounds.width > bounds.height ? 24 : bounds.width,
              height: bounds.width > bounds.height ? bounds.height : 24,
              child: ShellInputRegion(
                debugLabel: 'Split-screen resize handle',
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanUpdate: (details) {
                    final horizontal = bounds.width > bounds.height;
                    ref
                        .read(mobileMultiWindowProvider.notifier)
                        .setSplitFraction(
                          layout.splitFraction +
                              (horizontal
                                  ? details.delta.dx / bounds.width
                                  : details.delta.dy / bounds.height),
                        );
                  },
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.64),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SizedBox(
                        width: bounds.width > bounds.height ? 4 : 54,
                        height: bounds.width > bounds.height ? 54 : 4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (isFloating && !frame.isEmpty) ...[
            Positioned.fromRect(
              rect: Rect.fromLTWH(frame.left, frame.top, frame.width, 32),
              child: ShellInputRegion(
                debugLabel: 'Floating window drag',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    ref
                        .read(mobileMultiWindowProvider.notifier)
                        .moveFloating(details.delta, size);
                  },
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0xE52A2C38)),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.drag_indicator,
                          color: Colors.white70,
                          size: 17,
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: _restore,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(
                              Icons.fullscreen,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: frame.right - 32,
              top: frame.bottom - 32,
              width: 32,
              height: 32,
              child: ShellInputRegion(
                debugLabel: 'Floating window resize',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) => ref
                      .read(mobileMultiWindowProvider.notifier)
                      .resizeFloating(details.delta, size),
                  child: const Icon(
                    Icons.open_in_full,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
              ),
            ),
          ],
          Positioned(
            top: isFloating ? bounds.top + 3 : bounds.top + 7,
            right: 10,
            child: ShellInputRegion(
              debugLabel: 'Mobile multi-window actions',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xDB282938),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_expanded) ...[
                      action(Icons.splitscreen, '分屏', _split),
                      action(Icons.open_in_new, '小窗', _floating),
                      action(Icons.fullscreen, '全屏', _restore),
                    ],
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        child: Icon(
                          Icons.window_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
