import 'package:flutter/widgets.dart';

import '../../input/shell_interaction_registry.dart';
import '../../localization/denial_localizations.dart';
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
  // Scrolling changes only Stack offsets. Reuse identical pane subtrees so
  // neither app layout nor texture widgets rebuild at every pointer sample.
  final _panes =
      <
        int,
        ({DenialWindow window, bool focused, bool presented, Widget child})
      >{};

  Widget _pane(DenialWindow window) {
    final focused = window.objectId == widget.focusedObjectId;
    final cached = _panes[window.objectId];
    if (cached != null &&
        cached.window == window &&
        cached.focused == focused &&
        cached.presented == widget.presented)
      return cached.child;
    final child = _WorkspacePane(
      key: ValueKey(window.objectId),
      window: window,
      focused: focused,
      presented: widget.presented,
      onFocus: () => widget.onFocus(window),
      onClose: () => widget.onClose(window),
    );
    _panes[window.objectId] = (
      window: window,
      focused: focused,
      presented: widget.presented,
      child: child,
    );
    return child;
  }

  @override
  Widget build(BuildContext context) {
    _panes.removeWhere((id, _) => !widget.workspace.members.contains(id));
    final strings = MobileWorkspaceStrings(context);
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
                          child: ShellInputRegion(
                            active: widget.presented,
                            debugLabel: 'mobile_workspace_divider_$i',
                            child: Semantics(
                              label: strings.resize,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (_) => widget.onResizeStart(),
                                onPanUpdate: (event) => widget.onResize(
                                  i,
                                  layout.horizontal
                                      ? event.delta.dx
                                      : event.delta.dy,
                                ),
                                onPanEnd: (_) => widget.onResizeEnd(false),
                                onPanCancel: () => widget.onResizeEnd(true),
                                child: Center(
                                  child: Container(
                                    width: layout.horizontal ? 4 : 36,
                                    height: layout.horizontal ? 36 : 4,
                                    decoration: BoxDecoration(
                                      color: context.shellColors.textTertiary,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
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
              Positioned(
                left: 0,
                right: 0,
                top: MobileWorkspaceLayout.status,
                height: MobileWorkspaceLayout.toolbar,
                child: ShellInputRegion(
                  active: widget.presented,
                  debugLabel: 'mobile_workspace_toolbar',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: layout.scrolling
                        ? (event) => widget.onScroll(
                            -(layout.horizontal
                                ? event.delta.dx
                                : event.delta.dy),
                          )
                        : null,
                    onPanEnd: layout.scrolling
                        ? (_) => widget.onScrollEnd()
                        : null,
                    child: ColoredBox(
                      color: context.shellColors.surfaceContainer,
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Expanded(
                            child: Semantics(
                              label: layout.scrolling
                                  ? strings.scroll
                                  : strings.title,
                              child: Text(
                                '${strings.title} · ${widget.workspace.members.length}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.shellColors.textPrimary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          _WorkspaceButton(
                            label: strings.mode(widget.workspace.mode),
                            onTap: () => widget.onMode(
                              MobileWorkspaceMode
                                  .values[(widget.workspace.mode.index + 1) %
                                  MobileWorkspaceMode.values.length],
                            ),
                          ),
                          _WorkspaceButton(
                            label: strings.ungroup,
                            onTap: widget.onUngroup,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkspacePane extends StatelessWidget {
  const _WorkspacePane({
    super.key,
    required this.window,
    required this.focused,
    required this.presented,
    required this.onFocus,
    required this.onClose,
  });
  final DenialWindow window;
  final bool focused;
  final bool presented;
  final VoidCallback onFocus;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final managesInsets = window.selfManagedInsets || window.isLocalFlutter;
    return ColoredBox(
      color: context.shellColors.background,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            top: managesInsets ? 0 : MobileWorkspaceLayout.header,
            child: window.isLocalFlutter && !presented
                ? const SizedBox.expand()
                : RepaintBoundary(
                    child: WindowContentRect(
                      key: ValueKey('workspace-content-${window.objectId}'),
                      window: window,
                      active: focused && presented,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      cropToContentBounds: true,
                    ),
                  ),
          ),
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: MobileWorkspaceLayout.header,
            child: ShellInputRegion(
              active: presented,
              debugLabel: 'mobile_workspace_header_${window.objectId}',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onFocus,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.shellColors.surfaceContainerLow,
                    border: Border(
                      bottom: BorderSide(
                        width: focused ? 2 : 1,
                        color: focused
                            ? context.shellTheme.accentSeed
                            : context.shellColors.hairline,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          localizedWindowTitle(context, window),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.shellColors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      _WorkspaceButton(
                        label: '×',
                        semanticLabel: MobileWorkspaceStrings(context).close,
                        onTap: onClose,
                      ),
                    ],
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

class _WorkspaceButton extends StatelessWidget {
  const _WorkspaceButton({
    required this.label,
    required this.onTap,
    this.semanticLabel,
  });
  final String label;
  final String? semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel ?? label,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
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
