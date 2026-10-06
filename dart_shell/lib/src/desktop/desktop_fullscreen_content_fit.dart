import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Keeps a fullscreen client fully visible while its native surface has not
/// adopted the output aspect ratio.
///
/// Well-behaved clients quickly resize to [target] and therefore still fill
/// the output. Fixed-size, minimum-size and legacy X11 clients are letterboxed
/// instead of being stretched or cropped. The same rectangle is used by the
/// renderer and the native input map, so touch and pointer coordinates remain
/// aligned with the visible client.
Rect desktopFullscreenContentRect({
  required Rect target,
  required Size sourceSize,
  required bool fullscreen,
}) {
  if (!fullscreen ||
      target.isEmpty ||
      sourceSize.isEmpty ||
      !sourceSize.width.isFinite ||
      !sourceSize.height.isFinite) {
    return target;
  }

  final scale = math.min(
    target.width / sourceSize.width,
    target.height / sourceSize.height,
  );
  if (!scale.isFinite || scale <= 0.0) {
    return target;
  }

  final fitted = Size(sourceSize.width * scale, sourceSize.height * scale);
  return Rect.fromCenter(
    center: target.center,
    width: fitted.width,
    height: fitted.height,
  );
}
