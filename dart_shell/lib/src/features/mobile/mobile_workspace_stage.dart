import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../input/shell_interaction_registry.dart';
import '../../models/denial_window.dart';
import '../../models/mobile_workspace.dart';
import '../../theme/shell_theme.dart';
import '../../widgets/window_content_rect.dart';
import 'mobile_workspace_strings.dart';

class MobileWorkspaceStage extends StatefulWidget {
  const MobileWorkspaceStage({
    super.key,
    required this.workspace,
    required this.windows,
    required this.focusedObjectId,
    required this.presented,
    required this.onFocus,
    required this.onClose,
    required this.onUngroup,
    required this.onMode,
    required this.onScroll,
    required this.onScrollEnd,
    required this.onResizeStart,
    required this.onResize,
    required this.onResizeEnd,
  });

  final MobileWorkspace workspace;
  final Map<int, DenialWindow> windows;
  final int? focusedObjectId;
  final bool presented;
  final ValueChanged<DenialWindow> onFocus;
  final ValueChanged<DenialWindow> onClose;
  final VoidCallback onUngroup;
  final ValueChanged<MobileWorkspaceMode> onMode;
  final ValueChanged<double> onScroll;
  final VoidCallback onScrollEnd;
  final VoidCallback onResizeStart;
  final void Function(int divider, double delta) onResize;
  final void Function(bool cancel) onResizeEnd;

  @override
  State<MobileWorkspaceStage> createState() => _MobileWorkspaceStageState();
}

class _MobileWorkspaceStageState extends State<MobileWorkspaceStage> {
  // Translate retained clients while scrolling; never rebuild their canvas
  // or renegotiate a native size just to show/hide the transient controls.
  final _panes =
      <
        int,
        ({DenialWindow window, bool focused, bool presented, Widget child})
      >{};
  static const _gestureEdge = 8.0;
  Timer? _hideTimer;
  bool _controlsVisible = false;
  bool _holding = false;
  bool _holdHorizontal = false;
  double _lastHoldPosition = 0;
  double _holdTravel = 0;

  @override
  void didUpdateWidget(covariant MobileWorkspaceStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.presented || oldWidget.workspace.id != widget.workspace.id) {
      _hideTimer?.cancel();
      _controlsVisible = false;
      _holding = false;
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _hideControls() {
    _hideTimer?.cancel();
    if (mounted && _controlsVisible) setState(() => _controlsVisible = false);
  }

  void _showControls() {
    if (!widget.presented) return;
    _hideTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _hideTimer = Timer(const Duration(seconds: 6), _hideControls);
  }

  void _beginHold(MobileWorkspaceLayout layout) {
    if (!widget.presented) return;
    _holding = true;
    _holdHorizontal = layout.horizontal;
    _lastHoldPosition = 0;
    _holdTravel = 0;
    // Decide after release whether this is an action request or a scroll.
    // Scrolling must not briefly steal keyboard focus or flash a menu.
  }

  void _moveHold(
    MobileWorkspaceLayout layout,
    LongPressMoveUpdateDetails event,
  ) {
    if (!_holding || !widget.presented) return;
    if (layout.horizontal != _holdHorizontal) {
      _holding = false;
      _hideControls();
      return;
    }
    final position = _holdHorizontal
        ? event.offsetFromOrigin.dx
        : event.offsetFromOrigin.dy;
    final delta = position - _lastHoldPosition;
    _lastHoldPosition = position;
    _holdTravel += delta.abs();
    if (layout.scrolling && _holdTravel > 8) {
      _hideControls();
      widget.onScroll(-delta);
    }
  }

  void _endHold(MobileWorkspaceLayout layout) {
    if (!_holding) return;
    _holding = false;
    if (!widget.presented) {
      _hideControls();
      return;
    }
    if (layout.scrolling && _holdTravel > 8) {
      _hideControls();
      widget.onScrollEnd();
    } else {
      _showControls();
    }
  }

  void _action(VoidCallback callback) {
    if (!widget.presented) return;
    _hideControls();
    callback();
  }

  Widget _pane(DenialWindow window) {
    final focused = window.objectId == widget.focusedObjectId;
    final cached = _panes[window.objectId];
    if (cached != null &&
        cached.window == window &&
        cached.focused == focused &&
        cached.presented == widget.presented)
      return cached.child;
    final child = window.isLocalFlutter && !widget.presented
        ? const SizedBox.expand()
        : RepaintBoundary(
            child: WindowContentRect(
              key: ValueKey('workspace-content-${window.objectId}'),
              window: window,
              active: focused && widget.presented,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              includeLocalStatusInset: false,
              cropToContentBounds: true,
            ),
          );
    _panes[window.objectId] = (
      window: window,
      focused: focused,
      presented: widget.presented,
      child: child,
    );
    return child;
  }

  Widget _gesture(MobileWorkspaceLayout layout, {int? divider}) {
    final strings = MobileWorkspaceStrings(context);
    final resize = divider != null;
    return ShellInputRegion(
      active: widget.presented,
      debugLabel: resize
          ? 'mobile_workspace_divider_$divider'
          : 'mobile_workspace_gesture_edge',
      child: Semantics(
        label: resize ? strings.resize : strings.controls,
        onLongPress: _showControls,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: (_) => _beginHold(layout),
          onLongPressMoveUpdate: (event) => _moveHold(layout, event),
          onLongPressEnd: (_) => _endHold(layout),
          onLongPressCancel: () => _holding = false,
          onPanStart: resize
              ? (_) {
                  if (widget.presented) widget.onResizeStart();
                }
              : null,
          onPanUpdate: resize
              ? (event) {
                  if (widget.presented)
                    widget.onResize(
                      divider!,
                      layout.horizontal ? event.delta.dx : event.delta.dy,
                    );
                }
              : null,
          onPanEnd: resize ? (_) => widget.onResizeEnd(false) : null,
          onPanCancel: resize ? () => widget.onResizeEnd(true) : null,
          child: resize
              ? Center(
                  child: Container(
                    width: layout.horizontal ? 4 : 36,
                    height: layout.horizontal ? 36 : 4,
                    decoration: BoxDecoration(
                      color: context.shellColors.textTertiary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                )
              : const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _controls(MobileWorkspaceLayout layout) {
    final strings = MobileWorkspaceStrings(context);
    final focused = widget.windows[widget.focusedObjectId];
    return Positioned.fill(
      key: const ValueKey('workspace-actions'),
      child: ShellInputRegion(
        active: widget.presented,
        debugLabel: 'mobile_workspace_actions',
        pointerPolicy: ShellPointerPolicy.fullScene,
        keyboardPolicy: ShellKeyboardPolicy.capture,
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              _hideControls();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _hideControls,
                  child: const SizedBox.expand(),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.shellColors.surfaceContainer,
                        border: Border.all(color: context.shellColors.hairline),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              strings.title,
                              style: TextStyle(
                                color: context.shellColors.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                            if (layout.scrolling)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  strings.scroll,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: context.shellColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            Wrap(
                              alignment: WrapAlignment.center,
                              children: [
                                _WorkspaceButton(
                                  label: strings.mode(widget.workspace.mode),
                                  onTap: () => _action(
                                    () => widget.onMode(
                                      MobileWorkspaceMode.values[(widget
                                                  .workspace
                                                  .mode
                                                  .index +
                                              1) %
                                          MobileWorkspaceMode.values.length],
                                    ),
                                  ),
                                ),
                                _WorkspaceButton(
                                  label: strings.ungroup,
                                  onTap: () => _action(widget.onUngroup),
                                ),
                                if (focused != null)
                                  _WorkspaceButton(
                                    label: strings.close,
                                    onTap: () =>
                                        _action(() => widget.onClose(focused)),
                                  ),
                                _WorkspaceButton(
                                  label: strings.done,
                                  onTap: _hideControls,
                                ),
                              ],
                            ),
                          ],
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
    );
  }

  @override
  Widget build(BuildContext context) {
    _panes.removeWhere((id, _) => !widget.workspace.members.contains(id));
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = MobileWorkspaceLayout.resolve(
          constraints.biggest,
          widget.workspace,
          windows: widget.workspace.members
              .map((id) => widget.windows[id])
              .whereType<DenialWindow>(),
        );
        return ColoredBox(
          color: context.shellColors.background,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fromRect(
                rect: layout.viewport,
                child: ClipRect(
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      for (final pane in layout.panes)
                        if (widget.windows[pane.objectId] case final window?)
                          Positioned.fromRect(
                            key: ValueKey(pane.objectId),
                            rect: pane.frame.shift(-layout.viewport.topLeft),
                            child: _pane(window),
                          ),
                      for (var i = 0; i + 1 < layout.panes.length; i++)
                        Positioned.fromRect(
                          rect: layout
                              .dividerAfter(i)
                              .shift(-layout.viewport.topLeft),
                          child: _gesture(layout, divider: i),
                        ),
                    ],
                  ),
                ),
              ),
              // A transparent hit edge consumes no layout space. It remains
              // reachable even when an unusually wide client hides every divider.
              Positioned(
                left: 0,
                right: 0,
                top: layout.viewport.top,
                height: _gestureEdge,
                child: KeyedSubtree(
                  key: const ValueKey('workspace-gesture-edge'),
                  child: _gesture(layout),
                ),
              ),
              if (_controlsVisible && widget.presented) _controls(layout),
            ],
          ),
        );
      },
    );
  }
}

class _WorkspaceButton extends StatelessWidget {
  const _WorkspaceButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                color: context.shellColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
