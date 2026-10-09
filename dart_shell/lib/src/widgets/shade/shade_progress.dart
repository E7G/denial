import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shares the shade's painted progress, including its release spring, with
/// sibling shell layers. Listening to the animation does not rebuild providers.
final shadeProgressProvider = Provider<ProxyAnimation>((ref) {
  final progress = ProxyAnimation();
  ref.onDispose(() => progress.parent = null);
  return progress;
});

/// Waits for the actual shade controller to finish closing, not a guessed
/// delay. After its last tick the panel is removed from paint in the next
/// frame; wait for two *completed* Flutter frames before native capture can
/// run. A stuck/open panel times out without taking a misleading screenshot.
Future<bool> waitForShadeFullyClosed(
  Animation<double> progress, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  final settled = Completer<void>();
  void maybeSettled() {
    if (!settled.isCompleted &&
        progress.value <= 0.0 &&
        !progress.isAnimating) {
      settled.complete();
    }
  }

  void onStatus(AnimationStatus status) => maybeSettled();
  progress.addListener(maybeSettled);
  progress.addStatusListener(onStatus);
  try {
    maybeSettled();
    await settled.future.timeout(timeout);
  } on TimeoutException {
    return false;
  } finally {
    progress.removeListener(maybeSettled);
    progress.removeStatusListener(onStatus);
  }

  final binding = WidgetsBinding.instance;
  // The closing spring's terminal notification may arrive before the shade's
  // Offstage/RepaintBoundary update has made it into a rendered frame.
  binding.scheduleFrame();
  await binding.endOfFrame;
  binding.scheduleFrame();
  await binding.endOfFrame;
  return true;
}
