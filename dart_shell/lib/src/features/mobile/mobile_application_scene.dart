import 'dart:async';

import 'package:denial_dart_shell/denial.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../launcher/controllers/home_overlay_navigation.dart';
import '../../platform/denial_bridge.dart';
import '../../state/shell_controller.dart';
import '../../widgets/bottom_gesture_handle.dart';
import '../../widgets/three_button_navigation.dart';
import '../../widgets/edge_panel_layer.dart';
import '../../widgets/shade/system_shade_layer.dart';
import 'mobile_launcher_layer.dart';
import 'mobile_window_layers.dart';

/// Denial's built-in phone/tablet application scene.
///
/// All compositor lifecycle behavior is supplied by [DenialShell]; this class
/// contains only the visual feature policy of the stock mobile experience.
class MobileApplicationScene extends ConsumerStatefulWidget {
  const MobileApplicationScene({super.key});

  @override
  ConsumerState<MobileApplicationScene> createState() =>
      _MobileApplicationSceneState();
}

class _MobileApplicationSceneState
    extends ConsumerState<MobileApplicationScene> {
  final _overviewPresentationActive = ValueNotifier(false);
  final _overviewProgress = ValueNotifier(0.0);
  late final StreamSubscription<DenialShellActionEvent> _shellActions;
  late final _homeContentOpacity = Animation<double>.fromValueListenable(
    _overviewProgress,
    transformer: (progress) => 1.0 - progress,
  );

  @override
  void initState() {
    super.initState();
    _shellActions = ref
        .read(denialBridgeProvider)
        .shellActions
        .listen(_handleShellAction);
  }

  void _handleShellAction(DenialShellActionEvent event) {
    final controller = ref.read(shellControllerProvider.notifier);
    switch (event.action) {
      case DenialShellAction.applications:
        final state = ref.read(shellControllerProvider);
        if (state.overviewVisible) {
          controller.closeOverview();
        } else if (state.foregroundWindow != null ||
            state.launchRequest != null) {
          controller.goHome();
        }
      case DenialShellAction.overview:
        if (ref.read(shellControllerProvider).overviewVisible) {
          controller.closeOverview();
        } else {
          controller.openOverview();
        }
      case DenialShellAction.focusLeft:
        if (ref.read(homeOverlayNavigationProvider).modalOpen) {
          ref.read(homeOverlayNavigationProvider.notifier).requestBack();
        } else {
          controller.navigateBack();
        }
      default:
        break;
    }
  }

  @override
  void dispose() {
    unawaited(_shellActions.cancel());
    _overviewPresentationActive.dispose();
    _overviewProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.shellColors.background,
      child: MobileKeyboardViewport(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ShellWallpaper(),
            RepaintBoundary(
              child: MobileLauncherLayer(
                contentOpacity: _homeContentOpacity,
                overviewPresentationActive: _overviewPresentationActive,
              ),
            ),
            MobilePrimaryWindowLayer(
              overviewPresentationActive: _overviewPresentationActive,
            ),
            const MobileLaunchLayer(),
            MobileOverviewLayer(
              onPresentationChanged: (active) =>
                  _overviewPresentationActive.value = active,
              onProgressChanged: (progress) =>
                  _overviewProgress.value = progress,
            ),
            const MobileInputMethodPopupLayer(),
          ],
        ),
      ),
    );
  }
}

/// Gesture and shade chrome for the stock mobile shell.
class MobileShellChrome extends ConsumerWidget {
  const MobileShellChrome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final launchActive = ref.watch(
      shellControllerProvider.select((state) => state.launchRequest != null),
    );
    final navigationMode = ref.watch(
      shellSettingsProvider.select(
        (settings) => settings.tablet.navigationMode,
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (navigationMode == TabletNavigationMode.threeButton)
          const ThreeButtonNavigation()
        else
          const BottomGestureHandle(),
        SystemShadeLayer(ignoring: launchActive),
      ],
    );
  }
}
