import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../launcher/controllers/home_overlay_navigation.dart';
import '../widgets/shell_surface_host.dart';
import 'shell_controller.dart';

final tabletNavigationProvider = Provider<TabletNavigationController>(
  TabletNavigationController.new,
);

/// Shared navigation policy for the physical and on-screen tablet buttons.
class TabletNavigationController {
  TabletNavigationController(this._ref);

  final Ref _ref;

  bool get _locked {
    final state = _ref.read(shellControllerProvider);
    return state.locked || state.lockLayerVisible;
  }

  void back() {
    if (_locked) return;
    final controller = _ref.read(shellControllerProvider.notifier);
    final state = _ref.read(shellControllerProvider);
    if (state.edgePanelVisible || state.edgePanelDrag != Offset.zero) {
      controller.closeEdgePanel();
      return;
    }
    final surfaces = _ref.read(shellSurfaceControllerProvider)
        .where((surface) => !surface.closing).toList();
    if (surfaces.isNotEmpty) {
      final top = surfaces.last;
      if (top.dismissPolicy == ShellDismissPolicy.outsideTapAndEscape) {
        _ref.read(shellSurfaceControllerProvider.notifier).close(top.id);
      }
      return;
    }
    if (_ref.read(homeOverlayNavigationProvider).modalOpen) {
      _ref.read(homeOverlayNavigationProvider.notifier).requestBack();
      return;
    }
    controller.navigateBack();
  }

  bool _dismissTransientSurfaces() {
    final surfaces = _ref.read(shellSurfaceControllerProvider)
        .where((surface) => !surface.closing);
    // Do not bypass a protected prompt (for example display confirmation).
    if (surfaces.any((surface) => surface.dismissPolicy == ShellDismissPolicy.none)) {
      return false;
    }
    _ref.read(shellSurfaceControllerProvider.notifier).dismissAllImmediately();
    if (_ref.read(homeOverlayNavigationProvider).modalOpen) {
      _ref.read(homeOverlayNavigationProvider.notifier).requestBack();
    }
    return true;
  }

  void home() {
    if (_locked || !_dismissTransientSurfaces()) return;
    final controller = _ref.read(shellControllerProvider.notifier);
    controller.closeEdgePanel();
    controller.closeQuickSettings();
    final state = _ref.read(shellControllerProvider);
    if (state.overviewVisible) {
      controller.closeOverview();
    } else if (state.foregroundWindow != null || state.launchRequest != null) {
      controller.goHome();
    }
  }

  void overview() {
    if (_locked || !_dismissTransientSurfaces()) return;
    final controller = _ref.read(shellControllerProvider.notifier);
    if (_ref.read(shellControllerProvider).overviewVisible) {
      controller.closeOverview();
    } else {
      controller.openOverview();
    }
  }
}
