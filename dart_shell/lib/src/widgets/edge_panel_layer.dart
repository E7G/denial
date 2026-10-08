import 'dart:async';

import 'package:flutter/material.dart' show Icons;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../input/input_layout.dart';
import '../platform/denial_bridge.dart';
import '../services/clipboard_history_service.dart';
import '../services/fcitx_kimpanel_service.dart';
import '../services/haptics_service.dart';
import '../settings/settings_controller.dart';
import '../settings/shell_settings.dart';
import '../state/shell_controller.dart';
import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import 'osk/floating_osk_geometry.dart';
import 'osk/shell_osk_panel.dart';
import 'retained_translation.dart';
import 'shell_backdrop_blur.dart';

/// Keeps the mobile software keyboard above applications and shell surfaces,
/// including the compositor-owned lock screen.
class MobileSystemKeyboardLayer extends ConsumerWidget {
  const MobileSystemKeyboardLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Own the Kimpanel panel name for the whole mobile session, not only while
    // the keyboard is visible. Fcitx can then switch away from its floating
    // ClassicUI before the first composition starts.
    final candidateService = ref.watch(fcitxKimpanelServiceProvider);
    unawaited(candidateService.start().catchError((Object _) {}));
    final enabled = ref.watch(
      shellControllerProvider.select((state) => !state.launchTransitionActive),
    );
    return Offstage(
      offstage: !enabled,
      child: TickerMode(
        enabled: enabled,
        child: IgnorePointer(ignoring: !enabled, child: const EdgePanelLayer()),
      ),
    );
  }
}

/// Moves mobile content within the space left by the software keyboard.
///
/// The keyboard and its right-edge scroll strip must remain stationary, so
/// every full-screen surface that should follow the user's viewport pan wraps
/// itself in this boundary instead of duplicating the translation.
class MobileKeyboardViewport extends StatelessWidget {
  const MobileKeyboardViewport({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Windows touch keyboard behavior: the docked keyboard is an overlay.
    // Never translate the application scene. This deliberately removes the
    // old viewport-pan state so dismissing the keyboard cannot leave the app
    // shifted with its top edge off-screen.
    return RepaintBoundary(child: child);
  }
}

class EdgePanelLayer extends ConsumerStatefulWidget {
  const EdgePanelLayer({super.key});

  @override
  ConsumerState<EdgePanelLayer> createState() => _EdgePanelLayerState();
}

class _EdgePanelLayerState extends ConsumerState<EdgePanelLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _translation = ValueNotifier(Offset.zero);
  double _panelHeight = 0;
  bool _shown = false;
  bool _scrollReady = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(shellControllerProvider);
    _controller = AnimationController.unbounded(
      vsync: this,
      value: state.edgePanelVisible ? 1.0 : state.edgePanelDragProgress,
    )..addListener(_updatePresentation);
    _shown = unit(_controller.value) > 0.001;
    _scrollReady = unit(_controller.value) >= 0.98;
    ref.read(hapticsServiceProvider).prewarm();
  }

  @override
  void dispose() {
    _controller.dispose();
    _translation.dispose();
    super.dispose();
  }

  void _updateTranslation() {
    _translation.value = Offset(
      0,
      _panelHeight * (1 - unit(_controller.value)),
    );
  }

  void _updatePresentation() {
    _updateTranslation();
    final progress = unit(_controller.value);
    final shown = progress > 0.001;
    final scrollReady = progress >= 0.98;
    if (_shown == shown && _scrollReady == scrollReady) return;
    setState(() {
      _shown = shown;
      _scrollReady = scrollReady;
    });
  }

  void _onPanelChanged((bool, double, bool) signal) {
    final (visible, drag, dragActive) = signal;
    if (dragActive) {
      _controller.stop();
      _controller.value = drag;
    } else {
      springTo(
        _controller,
        visible ? 1.0 : 0.0,
        spring: Motion.gentle,
        telemetryLabel: 'edge_panel_settle',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _panelHeight = ShellMetrics.edgePanelHeight(MediaQuery.sizeOf(context));
    _updateTranslation();
    ref.listen<(bool, double, bool)>(
      shellControllerProvider.select(
        (state) => (
          state.edgePanelVisible,
          state.edgePanelDragProgress,
          state.edgePanelDragActive,
        ),
      ),
      (_, next) => _onPanelChanged(next),
    );

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: !_shown,
            child: TickerMode(
              enabled: _shown,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RetainedTranslation(
                    translation: _translation,
                    child: const _EdgePanelSheet(),
                  ),
                ],
              ),
            ),
          ),
          const _EdgePanelGestureTarget(),
        ],
      ),
    );
  }
}

class _EdgePanelGestureTarget extends ConsumerWidget {
  const _EdgePanelGestureTarget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final edgePanelVisible = ref.watch(
      shellControllerProvider.select((state) => state.edgePanelVisible),
    );
    final controller = ref.read(shellControllerProvider.notifier);
    return Positioned(
      right: 0,
      bottom: ShellMetrics.gestureBottomInset,
      width: ShellMetrics.edgePanelGestureWidth,
      height: ShellMetrics.edgePanelGestureHeight,
      child: IgnorePointer(
        ignoring: edgePanelVisible,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => controller.startEdgePanelDrag(),
          onVerticalDragUpdate: (details) {
            controller.updateEdgePanelDrag(Offset(0.0, details.delta.dy));
          },
          onVerticalDragEnd: (details) {
            controller.endEdgePanelDrag(details.primaryVelocity ?? 0.0);
          },
          onVerticalDragCancel: () => controller.endEdgePanelDrag(0.0),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _EdgePanelScrollStrip extends ConsumerWidget {
  const _EdgePanelScrollStrip({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final edgePanelVisible = ref.watch(
      shellControllerProvider.select((state) => state.edgePanelVisible),
    );
    if (!edgePanelVisible || !enabled) {
      return const SizedBox.expand();
    }

    final controller = ref.read(shellControllerProvider.notifier);
    final size = MediaQuery.sizeOf(context);
    final panelHeight = ShellMetrics.edgePanelHeight(size);

    return Positioned(
      top: 0,
      right: 0,
      bottom: panelHeight,
      width: ShellMetrics.edgePanelScrollStripWidth,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          controller.updateEdgePanelViewportScroll(
            -details.delta.dy * ShellMetrics.edgePanelScrollMultiplier,
            panelHeight,
          );
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _EdgePanelSheet extends ConsumerWidget {
  const _EdgePanelSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final floating = ref.watch(
      shellSettingsProvider.select(
        (settings) =>
            settings.tablet.oskLayoutMode == TabletOskLayoutMode.floating,
      ),
    );
    return floating
        ? const _FloatingEdgePanelSheet()
        : const _DockedEdgePanelSheet();
  }
}

class _DockedEdgePanelSheet extends ConsumerWidget {
  const _DockedEdgePanelSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(shellControllerProvider.notifier);
    final size = MediaQuery.sizeOf(context);
    final panelHeight = ShellMetrics.edgePanelHeight(size);

    return Align(
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => controller.startEdgePanelDrag(),
        onVerticalDragUpdate: (details) {
          controller.updateEdgePanelDrag(Offset(0.0, details.delta.dy));
        },
        onVerticalDragEnd: (details) {
          controller.endEdgePanelDrag(details.primaryVelocity ?? 0.0);
        },
        onVerticalDragCancel: () => controller.endEdgePanelDrag(0.0),
        child: SizedBox(
          width: double.infinity,
          height: panelHeight,
          child: const _EdgePanelContent(),
        ),
      ),
    );
  }
}

class _FloatingEdgePanelSheet extends ConsumerStatefulWidget {
  const _FloatingEdgePanelSheet();

  @override
  ConsumerState<_FloatingEdgePanelSheet> createState() =>
      _FloatingEdgePanelSheetState();
}

class _FloatingEdgePanelSheetState
    extends ConsumerState<_FloatingEdgePanelSheet> {
  Rect? _draftRect;
  TabletOskFloatingPlacement? _sourcePlacement;
  bool? _portrait;
  bool _interacting = false;

  TabletOskFloatingPlacement _savedPlacement(
    ShellTabletSettings settings,
    bool portrait,
  ) {
    return portrait
        ? settings.oskFloatingPortrait
        : settings.oskFloatingLandscape;
  }

  Rect _resolvedRect(
    BuildContext context,
    ShellTabletSettings settings,
    bool portrait,
  ) {
    final viewSize = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);
    final saved = _savedPlacement(settings, portrait);

    if (!_interacting &&
        (_draftRect == null ||
            _portrait != portrait ||
            _sourcePlacement != saved)) {
      _portrait = portrait;
      _sourcePlacement = saved;
      _draftRect = resolveFloatingOskRect(
        viewSize: viewSize,
        safePadding: safePadding,
        placement: saved,
      );
    }

    final current =
        _draftRect ??
        resolveFloatingOskRect(
          viewSize: viewSize,
          safePadding: safePadding,
          placement: saved,
        );
    final bounded = resolveFloatingOskRect(
      viewSize: viewSize,
      safePadding: safePadding,
      placement: placementFromFloatingOskRect(current),
    );
    if (bounded != current && !_interacting) {
      _draftRect = bounded;
    }
    return bounded;
  }

  void _move(DragUpdateDetails details) {
    final rect = _draftRect;
    if (rect == null) {
      return;
    }
    setState(() {
      _interacting = true;
      final moved = rect.shift(details.delta);
      _draftRect = resolveFloatingOskRect(
        viewSize: MediaQuery.sizeOf(context),
        safePadding: MediaQuery.paddingOf(context),
        placement: placementFromFloatingOskRect(moved),
      );
    });
  }

  void _resize(DragUpdateDetails details) {
    final rect = _draftRect;
    if (rect == null) {
      return;
    }
    setState(() {
      _interacting = true;
      final resized = Rect.fromLTWH(
        rect.left,
        rect.top,
        rect.width + details.delta.dx,
        rect.height + details.delta.dy,
      );
      _draftRect = resolveFloatingOskRect(
        viewSize: MediaQuery.sizeOf(context),
        safePadding: MediaQuery.paddingOf(context),
        placement: placementFromFloatingOskRect(resized),
      );
    });
  }

  void _finishInteraction([DragEndDetails? _]) {
    _interacting = false;
    _persist();
  }

  void _persist() {
    final rect = _draftRect;
    final portrait = _portrait;
    if (rect == null || portrait == null || rect.isEmpty) {
      return;
    }
    final placement = placementFromFloatingOskRect(rect);
    _sourcePlacement = placement;
    ref
        .read(shellSettingsProvider.notifier)
        .setTabletOskFloatingPlacement(
          portrait: portrait,
          placement: placement,
        );
  }

  void _toggleLock(bool locked) {
    ref
        .read(shellSettingsProvider.notifier)
        .setTabletOskFloatingLocked(!locked);
  }

  void _dockBottom() {
    final rect = _draftRect;
    if (rect == null) {
      return;
    }
    final viewSize = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final centered = TabletOskFloatingPlacement(
      x: (viewSize.width - rect.width) / 2,
      y: viewSize.height - safe.bottom - floatingOskBottomMargin - rect.height,
      width: rect.width,
      height: rect.height,
    );
    setState(() {
      _interacting = false;
      _draftRect = resolveFloatingOskRect(
        viewSize: viewSize,
        safePadding: safe,
        placement: centered,
      );
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final tabletSettings = ref.watch(
      shellSettingsProvider.select((settings) => settings.tablet),
    );
    final portrait =
        MediaQuery.sizeOf(context).height >= MediaQuery.sizeOf(context).width;
    final rect = _resolvedRect(context, tabletSettings, portrait);
    final locked = tabletSettings.oskFloatingLocked;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fromRect(
          rect: rect,
          child: RepaintBoundary(
            key: const ValueKey('floating-osk-surface'),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _EdgePanelContent(
                  floating: true,
                  floatingLocked: locked,
                  onFloatingMoveUpdate: locked ? null : _move,
                  onFloatingMoveEnd: locked ? null : _finishInteraction,
                  onToggleFloatingLock: () => _toggleLock(locked),
                  onDockFloating: _dockBottom,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  width: 42,
                  height: 42,
                  child: IgnorePointer(
                    ignoring: locked,
                    child: GestureDetector(
                      key: const ValueKey('osk-floating-resize-handle'),
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: _resize,
                      onPanEnd: _finishInteraction,
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.open_in_full_rounded,
                            size: 16,
                            color: context.shellColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EdgePanelContent extends ConsumerWidget {
  const _EdgePanelContent({
    this.floating = false,
    this.floatingLocked = false,
    this.onFloatingMoveUpdate,
    this.onFloatingMoveEnd,
    this.onToggleFloatingLock,
    this.onDockFloating,
  });

  final bool floating;
  final bool floatingLocked;
  final GestureDragUpdateCallback? onFloatingMoveUpdate;
  final GestureDragEndCallback? onFloatingMoveEnd;
  final VoidCallback? onToggleFloatingLock;
  final VoidCallback? onDockFloating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(shellControllerProvider.notifier);
    final bridge = ref.read(denialBridgeProvider);
    final candidateService = ref.read(fcitxKimpanelServiceProvider);
    final clipboard = ref.read(clipboardHistoryServiceProvider);
    final haptics = ref.read(hapticsServiceProvider);
    final theme = ShellTheme.of(context);
    final radius = floating
        ? BorderRadius.circular(14)
        : const BorderRadius.vertical(top: Radius.circular(12));
    return ShellBackdropBlur(
      separateChild: true,
      blur: theme.effectivePanelOpacity < 1.0,
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.panelColor(context.shellColors.panelBackground),
          borderRadius: radius,
          border: floating
              ? Border.all(color: context.shellColors.hairline, width: 1)
              : Border(
                  top: BorderSide(
                    color: context.shellColors.hairline,
                    width: 1,
                  ),
                ),
        ),
        child: RepaintBoundary(
          // Keep OSK presses inside the focused EditableText tap group. A
          // keyboard key must not look like an outside tap and retire the
          // editor before its command is delivered.
          child: TextFieldTapRegion(
            child: ShellOskPanel(
              onKeyTap: haptics.pulse,
              onDismiss: controller.dismissEdgePanelFromUser,
              loadClipboard: clipboard.snapshot,
              pasteClipboard: (entry) async {
                await clipboard.activate(entry.id);
                bridge.sendKeyboardKey('v', ctrl: true);
              },
              candidateListenable: candidateService.candidateListenable,
              onCandidateSelected: (index) {
                unawaited(candidateService.selectCandidate(index));
              },
              onCandidatePreviousPage: () {
                unawaited(candidateService.previousPage());
              },
              onCandidateNextPage: () {
                unawaited(candidateService.nextPage());
              },
              floating: floating,
              floatingLocked: floatingLocked,
              onFloatingMoveUpdate: onFloatingMoveUpdate,
              onFloatingMoveEnd: onFloatingMoveEnd,
              onToggleFloatingLock: onToggleFloatingLock,
              onDockFloating: onDockFloating,
              onKey: (intent) => _sendOskIntent(bridge, intent),
            ),
          ),
        ),
      ),
    );
  }

  void _sendOskIntent(DenialBridge bridge, ShellOskKeyIntent intent) {
    switch (intent.action) {
      case ShellOskKeyAction.text:
        bridge.sendKeyboardText(intent.text ?? '');
      case ShellOskKeyAction.key:
        bridge.sendKeyboardKey(intent.key ?? '', ctrl: intent.ctrl);
      case ShellOskKeyAction.space:
        if (intent.ctrl) {
          bridge.sendKeyboardKey(intent.key ?? 'space', ctrl: true);
        } else {
          bridge.sendKeyboardText(' ');
        }
      case ShellOskKeyAction.backspace:
        final key = intent.key ?? 'BackSpace';
        switch (intent.phase) {
          case ShellOskKeyPhase.tap:
            bridge.sendKeyboardKey(key, ctrl: intent.ctrl);
          case ShellOskKeyPhase.pressed:
            bridge.pressKeyboardKey(key);
          case ShellOskKeyPhase.released:
            bridge.releaseKeyboardKey(key);
        }
      case ShellOskKeyAction.enter:
        bridge.sendKeyboardKey(intent.key ?? 'Return', ctrl: intent.ctrl);
    }
  }
}
