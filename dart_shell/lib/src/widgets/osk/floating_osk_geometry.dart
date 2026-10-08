import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../settings/shell_settings.dart';

const double floatingOskHorizontalMargin = 12;
const double floatingOskBottomMargin = 16;
const double floatingOskTopMargin = 8;
const double floatingOskMinimumWidth = 320;
const double floatingOskMinimumHeight = 220;

Rect resolveFloatingOskRect({
  required Size viewSize,
  required EdgeInsets safePadding,
  required TabletOskFloatingPlacement placement,
}) {
  if (viewSize.isEmpty) {
    return Rect.zero;
  }

  final availableWidth = math.max(
    0.0,
    viewSize.width - floatingOskHorizontalMargin * 2,
  );
  final availableHeight = math.max(
    0.0,
    viewSize.height -
        safePadding.top -
        safePadding.bottom -
        floatingOskTopMargin -
        floatingOskBottomMargin,
  );
  if (availableWidth <= 0 || availableHeight <= 0) {
    return Rect.zero;
  }

  final minWidth = math.min(floatingOskMinimumWidth, availableWidth);
  final minHeight = math.min(floatingOskMinimumHeight, availableHeight);
  final width = placement.width.clamp(minWidth, availableWidth).toDouble();
  final height = placement.height.clamp(minHeight, availableHeight).toDouble();

  final minX = floatingOskHorizontalMargin;
  final maxX = math.max(
    minX,
    viewSize.width - width - floatingOskHorizontalMargin,
  );
  final minY = safePadding.top + floatingOskTopMargin;
  final maxY = math.max(
    minY,
    viewSize.height - safePadding.bottom - floatingOskBottomMargin - height,
  );

  final defaultX = maxX;
  final defaultY = maxY;
  final x = (placement.x < 0 ? defaultX : placement.x)
      .clamp(minX, maxX)
      .toDouble();
  final y = (placement.y < 0 ? defaultY : placement.y)
      .clamp(minY, maxY)
      .toDouble();

  return Rect.fromLTWH(x, y, width, height);
}

TabletOskFloatingPlacement placementFromFloatingOskRect(Rect rect) {
  return TabletOskFloatingPlacement(
    x: rect.left,
    y: rect.top,
    width: rect.width,
    height: rect.height,
  );
}
