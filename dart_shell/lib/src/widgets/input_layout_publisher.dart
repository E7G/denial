import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../input/shell_interaction_registry.dart';
import '../settings/settings_controller.dart';
import '../settings/shell_settings.dart';
import '../state/shell_controller.dart';
import 'osk/floating_osk_geometry.dart';

class InputLayoutPublisher extends ConsumerStatefulWidget {
  const InputLayoutPublisher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<InputLayoutPublisher> createState() =>
      _InputLayoutPublisherState();
}

class _InputLayoutPublisherState extends ConsumerState<InputLayoutPublisher> {
  bool _scheduled = false;
  Size _pendingViewSize = Size.zero;
  Rect? _pendingFloatingKeyboardRect;

  @override
  Widget build(BuildContext context) {
    ref.watch(
      shellControllerProvider.select(
        (state) => (
          overviewVisible: state.overviewVisible,
          inputWindow: state.inputWindow,
          launchRequestId: state.launchRequest?.requestId,
          launchingObjectId: state.launchingObjectId,
          quickSettingsVisible: state.quickSettingsVisible,
          quickSettingsProgress: state.quickSettingsDragProgress,
          edgePanelVisible: state.edgePanelVisible,
          edgePanelProgress: state.edgePanelDragProgress,
          edgePanelViewportScroll: state.edgePanelViewportScroll,
          lockLayerVisible: state.lockLayerVisible,
        ),
      ),
    );
    ref.watch(shellInteractionRegistryProvider);
    final media = MediaQuery.of(context);
    final tabletKeyboard = ref.watch(
      shellSettingsProvider.select(
        (settings) => (
          mode: settings.tablet.oskLayoutMode,
          portrait: settings.tablet.oskFloatingPortrait,
          landscape: settings.tablet.oskFloatingLandscape,
        ),
      ),
    );
    final portrait = media.size.height >= media.size.width;
    final floatingKeyboardRect =
        tabletKeyboard.mode == TabletOskLayoutMode.floating
        ? resolveFloatingOskRect(
            viewSize: media.size,
            safePadding: media.padding,
            placement: portrait
                ? tabletKeyboard.portrait
                : tabletKeyboard.landscape,
          )
        : null;
    _schedulePublish(media.size, floatingKeyboardRect);
    return widget.child;
  }

  void _schedulePublish(Size viewSize, Rect? floatingKeyboardRect) {
    _pendingViewSize = viewSize;
    _pendingFloatingKeyboardRect = floatingKeyboardRect;
    if (_scheduled) {
      return;
    }

    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) {
        return;
      }
      ref
          .read(shellControllerProvider.notifier)
          .publishInputLayout(
            _pendingViewSize,
            ref.read(shellInteractionRegistryProvider),
            floatingKeyboardRect: _pendingFloatingKeyboardRect,
          );
    });
  }
}
