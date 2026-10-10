import 'package:denial_dart_shell/denial.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../launcher/home_surface.dart';
import '../../state/mobile_multi_window.dart';
import '../../theme/motion.dart';
import '../../widgets/shade/shade_progress.dart';

/// Visibility and interaction policy for the stock launcher feature.
class MobileLauncherLayer extends ConsumerWidget {
  const MobileLauncherLayer({
    super.key,
    required this.contentOpacity,
    required this.overviewPresentationActive,
  });

  final Animation<double> contentOpacity;
  final ValueListenable<bool> overviewPresentationActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final multi = ref.watch(mobileMultiWindowProvider);
    final floatAboveHome =
        multi.mode == MobileMultiWindowMode.floating &&
        multi.secondaryId == null;
    final flags = ref.watch(
      shellControllerProvider.select((state) {
        final active =
            state.primaryWindow == null ||
            state.homeTransitionActive ||
            floatAboveHome;
        return (
          active: active,
          launching: state.launchTransitionActive,
          interactive:
              active &&
              !state.launchTransitionActive &&
              !state.overviewVisible &&
              state.gestureDrag == Offset.zero &&
              !state.homeTransitionActive &&
              state.quickSettingsDragProgress == 0.0 &&
              !state.lockLayerVisible,
        );
      }),
    );
    final opacity = _HomeContentOpacity(
      first: contentOpacity,
      next: ReverseAnimation(ref.watch(shadeProgressProvider)),
    );
    // Keep the grid mounted while recents and the shade fade its content.
    // Phase changes alone update interaction/tickers; animation ticks stay
    // at the renderer and share the existing composited opacity layer.
    return ValueListenableBuilder<bool>(
      valueListenable: overviewPresentationActive,
      builder: (context, overviewActive, _) => TickerMode(
        enabled: !overviewActive,
        // WinRT retreat without fullscreen opacity + scaling passes.
        // The old 0.58 alpha and 0.975 scale caused two expensive full-scene
        // compositing layers behind the simultaneously expanding splash.
        // A short horizontal translation preserves the directional motion.
        child: AnimatedSlide(
          offset: flags.launching ? const Offset(-0.024, 0) : Offset.zero,
          duration: Motion.launchHomeRetreat,
          curve: flags.launching
              ? Motion.winPhoneExitCurve
              : Motion.winPhoneEnterCurve,
          child: HomeSurface(
            active: flags.active,
            interactive:
                flags.interactive && !overviewActive && !floatAboveHome,
            contentOpacity: opacity,
            useShellLaunchTransition: true,
          ),
        ),
      ),
    );
  }
}

class _HomeContentOpacity extends CompoundAnimation<double> {
  _HomeContentOpacity({required super.first, required super.next});

  @override
  double get value => first.value * next.value;
}
