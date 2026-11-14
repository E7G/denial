import 'package:denial_dart_shell/denial.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/window_surface_tree.dart';
import 'mobile_primary_window_stage.dart';
import 'mobile_workspace_stage.dart';

/// Each animated layer observes only the state it presents.
class MobilePrimaryWindowLayer extends ConsumerStatefulWidget {
  const MobilePrimaryWindowLayer({
    super.key,
    required this.overviewPresentationActive,
  });

  final ValueListenable<bool> overviewPresentationActive;

  @override
  ConsumerState<MobilePrimaryWindowLayer> createState() =>
      _MobilePrimaryWindowLayerState();
}

class _MobilePrimaryWindowLayerState
    extends ConsumerState<MobilePrimaryWindowLayer> {
  final _dragX = ValueNotifier(0.0);

  @override
  void dispose() {
    _dragX.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      shellControllerProvider.select((state) => state.gestureDrag.dx),
      (_, next) => _dragX.value = next,
    );
    _dragX.value = ref.read(shellControllerProvider).gestureDrag.dx;
    final visual = ref.watch(
      shellControllerProvider.select(
        (state) => (
          window: state.primaryWindow,
          workspace: state.activeMobileWorkspace,
          secure: state.locked || state.lockLayerVisible,
          windows: state.windows,
          target: state.appSwitchTargetWindow,
          switching: state.gestureDrag.dx.abs() >= 0.5,
          heroOwnsForeground:
              state.foregroundWindow != null &&
              (state.overviewVisible ||
                  state.gestureDrag.dy < 0.0 ||
                  state.homeTransitionActive),
        ),
      ),
    );
    final window = visual.window;
    if (window == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<bool>(
      valueListenable: widget.overviewPresentationActive,
      builder: (context, overviewActive, _) {
        // Gesture state resets on release; the hero still owns presentation
        // until its return animation has reached the normal app bounds.
        final heroOwnsForeground = visual.heroOwnsForeground || overviewActive;
        if (window.isLocalFlutter && heroOwnsForeground) {
          return const SizedBox.shrink();
        }
        final workspace = visual.workspace;
        if (workspace != null) {
          final controller = ref.read(shellControllerProvider.notifier);
          return Positioned.fill(
            child: Opacity(
              opacity: heroOwnsForeground ? 0 : 1,
              child: MobileWorkspaceStage(
                key: ValueKey(workspace.id),
                workspace: workspace,
                windows: {for (final w in visual.windows) w.objectId: w},
                focusedObjectId: window.objectId,
                presented: !heroOwnsForeground && !visual.secure,
                onFocus: controller.focusWindow,
                onClose: controller.closeWindow,
                onUngroup: () =>
                    controller.ungroupMobileWorkspace(workspace.id),
                onMode: (mode) =>
                    controller.setMobileWorkspaceMode(workspace.id, mode),
                onScroll: (delta) =>
                    controller.scrollMobileWorkspace(workspace.id, delta),
                onScrollEnd: () =>
                    controller.settleMobileWorkspaceScroll(workspace.id),
                onResizeStart: () =>
                    controller.beginMobileWorkspaceResize(workspace.id),
                onResize: (index, delta) => controller.resizeMobileWorkspace(
                  workspace.id,
                  index,
                  delta,
                ),
                onResizeEnd: (cancel) =>
                    controller.finishMobileWorkspaceResize(cancel: cancel),
              ),
            ),
          );
        }
        return Positioned.fill(
          child: MobilePrimaryWindowStage(
            currentWindow: window,
            switchTargetWindow: visual.switching ? visual.target : null,
            switchDragX: _dragX,
            opacity: heroOwnsForeground ? 0.0 : 1.0,
          ),
        );
      },
    );
  }
}

class MobileInputMethodPopupLayer extends ConsumerWidget {
  const MobileInputMethodPopupLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(
      shellControllerProvider.select(
        (state) =>
            (sequence: state.windowSnapshotSequence, windows: state.windows),
      ),
    );
    final popups = snapshot.windows
        .where((window) => window.isInputMethodPopup && window.geometry != null)
        .toList(growable: false);
    if (popups.isEmpty) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          for (final popup in popups)
            if (popup.geometry case final geometry?)
              Positioned.fromRect(
                rect: geometry,
                child: RepaintBoundary(
                  child: WindowSurfaceTree(
                    window: popup,
                    includePopups: true,
                    clipToBounds: false,
                    filterQuality: FilterQuality.low,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class MobileLaunchLayer extends ConsumerWidget {
  const MobileLaunchLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final launch = ref.watch(
      shellControllerProvider.select(
        (state) =>
            (request: state.launchRequest, window: state.launchingWindow),
      ),
    );
    return LaunchTransitionLayer(
      request: launch.request,
      window: launch.window,
      onCompleted: ref
          .read(shellControllerProvider.notifier)
          .completeLaunchTransition,
    );
  }
}

class MobileOverviewLayer extends ConsumerStatefulWidget {
  const MobileOverviewLayer({
    super.key,
    required this.onPresentationChanged,
    this.onProgressChanged,
  });

  final ValueChanged<bool> onPresentationChanged;
  final ValueChanged<double>? onProgressChanged;

  @override
  ConsumerState<MobileOverviewLayer> createState() =>
      _MobileOverviewLayerState();
}

class _MobileOverviewLayerState extends ConsumerState<MobileOverviewLayer> {
  final _dragY = ValueNotifier(0.0);

  @override
  void dispose() {
    _dragY.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      shellControllerProvider.select((state) => state.gestureDrag.dy),
      (_, next) => _dragY.value = next,
    );

    final overview = ref.watch(
      shellControllerProvider.select(
        (state) => (
          window: state.activeMobileWorkspace == null
              ? state.foregroundWindow
              : state.windowByObjectId(
                  state.activeMobileWorkspace!.members.first,
                ),
          objectId:
              state.activeMobileWorkspace?.members.first ??
              state.foregroundObjectId,
          workspaces: state.mobileWorkspaces,
          windows: state.mobileRecentsWindows,
          allWindows: state.windows,
          visible: state.overviewVisible,
          homeActive: state.homeTransitionActive,
        ),
      ),
    );
    final controller = ref.read(shellControllerProvider.notifier);
    return OverviewLayer(
      windows: overview.windows,
      workspaceMembers: {
        for (final group in overview.workspaces)
          group.members.first: [
            for (final id in group.members)
              for (final window in overview.allWindows)
                if (window.objectId == id) window,
          ],
      },
      onMergeWindows: controller.mergeMobileWorkspace,
      foregroundWindow: overview.window,
      foregroundObjectId: overview.objectId,
      visible: overview.visible,
      swipeDy: _dragY,
      homeTransitionActive: overview.homeActive,
      onPresentationChanged: widget.onPresentationChanged,
      onProgressChanged: widget.onProgressChanged,
      onDismissOverview: controller.closeOverview,
      onDismissWindow: controller.closeMobileRecentsEntry,
      onFocusWindow: controller.focusMobileRecentsEntry,
      onHomeSettled: controller.completeHomeTransition,
    );
  }
}
