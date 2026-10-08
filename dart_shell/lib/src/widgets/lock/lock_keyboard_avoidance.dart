import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../input/input_layout.dart';
import '../../settings/shell_settings.dart';
import '../osk/floating_osk_geometry.dart';

@immutable
class LockKeyboardAvoidance {
  const LockKeyboardAvoidance({
    this.topInset = 0,
    this.bottomInset = 0,
    this.alignment = Alignment.bottomCenter,
  });

  final double topInset;
  final double bottomInset;
  final Alignment alignment;

  double availableHeight({
    required Size viewSize,
    required EdgeInsets safePadding,
  }) {
    final safeTop = math.max(safePadding.top, 12.0);
    final safeBottom = math.max(safePadding.bottom, 22.0);
    return math.max(
      1.0,
      viewSize.height - safeTop - safeBottom - topInset - bottomInset,
    );
  }
}

LockKeyboardAvoidance resolveLockKeyboardAvoidance({
  required Size viewSize,
  required EdgeInsets safePadding,
  required double keyboardProgress,
  required ShellTabletSettings tabletSettings,
}) {
  if (viewSize.isEmpty ||
      viewSize.height <= viewSize.width ||
      keyboardProgress <= 0.001) {
    return const LockKeyboardAvoidance();
  }

  final progress = keyboardProgress.clamp(0.0, 1.0).toDouble();
  final safeTop = math.max(safePadding.top, 12.0);
  final safeBottom = math.max(safePadding.bottom, 22.0);
  const gap = 12.0;

  if (tabletSettings.oskLayoutMode != TabletOskLayoutMode.floating) {
    final keyboardHeight = ShellMetrics.edgePanelHeight(viewSize) * progress;
    final keyboardTop = viewSize.height - keyboardHeight;
    final contentBottom = viewSize.height - safeBottom;
    return LockKeyboardAvoidance(
      bottomInset: math.max(0.0, contentBottom - keyboardTop + gap),
    );
  }

  final saved = tabletSettings.oskFloatingPortrait;
  var keyboardRect = resolveFloatingOskRect(
    viewSize: viewSize,
    safePadding: safePadding,
    placement: saved,
  );
  keyboardRect = keyboardRect.shift(
    Offset(0, ShellMetrics.edgePanelHeight(viewSize) * (1 - progress)),
  );
  keyboardRect = keyboardRect.intersect(Offset.zero & viewSize);
  if (keyboardRect.isEmpty) {
    return const LockKeyboardAvoidance();
  }

  final authWidth = math.min(480.0, math.max(0.0, viewSize.width - 36.0));
  final authHorizontal = Rect.fromLTWH(
    (viewSize.width - authWidth) / 2,
    0,
    authWidth,
    viewSize.height,
  );
  if (authHorizontal.intersect(keyboardRect).isEmpty) {
    return const LockKeyboardAvoidance();
  }

  final contentTop = safeTop;
  final contentBottom = viewSize.height - safeBottom;
  final aboveBottom = keyboardRect.top - gap;
  final belowTop = keyboardRect.bottom + gap;
  final aboveHeight = math.max(0.0, aboveBottom - contentTop);
  final belowHeight = math.max(0.0, contentBottom - belowTop);

  if (aboveHeight >= belowHeight) {
    return LockKeyboardAvoidance(
      bottomInset: math.max(0.0, contentBottom - aboveBottom),
    );
  }

  return LockKeyboardAvoidance(
    topInset: math.max(0.0, belowTop - contentTop),
    alignment: Alignment.topCenter,
  );
}
