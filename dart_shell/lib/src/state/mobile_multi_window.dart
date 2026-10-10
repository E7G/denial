import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../input/input_layout.dart';

enum MobileMultiWindowMode { single, split, floating }

@immutable
class MobileMultiWindowState {
  const MobileMultiWindowState({
    this.mode = MobileMultiWindowMode.single,
    this.primaryId,
    this.secondaryId,
    this.selectingPartner = false,
    this.splitFraction = 0.5,
    this.floatingFraction = const Rect.fromLTWH(0.19, 0.13, 0.74, 0.67),
  });

  final MobileMultiWindowMode mode;
  final int? primaryId;
  final int? secondaryId;
  final bool selectingPartner;
  final double splitFraction;

  /// Normalized to the available viewport; survives portrait/landscape.
  final Rect floatingFraction;

  Rect usableBounds(Size size) => Rect.fromLTRB(
    0,
    math.min(ShellMetrics.appStatusBarHeight, size.height),
    size.width,
    math.max(
      math.min(ShellMetrics.appStatusBarHeight, size.height),
      size.height - 24,
    ),
  );

  Rect floatingFrame(Size size) {
    final b = usableBounds(size);
    if (b.isEmpty) return Rect.zero;
    final minWidth = math.min(210.0, b.width);
    final minHeight = math.min(190.0, b.height);
    final w = (b.width * floatingFraction.width)
        .clamp(minWidth, b.width)
        .toDouble();
    final h = (b.height * floatingFraction.height)
        .clamp(minHeight, b.height)
        .toDouble();
    final x = (b.left + b.width * floatingFraction.left)
        .clamp(b.left, b.right - w)
        .toDouble();
    final y = (b.top + b.height * floatingFraction.top)
        .clamp(b.top, b.bottom - h)
        .toDouble();
    return Rect.fromLTWH(x, y, w, h);
  }

  /// Actual native client rectangles; floating chrome occupies 32 logical px.
  Map<int, Rect> windowRects(Size size) {
    final a = primaryId;
    if (a == null) return const {};
    final bounds = usableBounds(size);
    if (bounds.isEmpty) return const {};
    if (mode == MobileMultiWindowMode.floating) {
      final frame = floatingFrame(size);
      return {
        if (secondaryId case final b? when b != a) b: bounds,
        a: Rect.fromLTWH(
          frame.left,
          frame.top + 32,
          frame.width,
          math.max(64, frame.height - 32),
        ),
      };
    }
    if (mode != MobileMultiWindowMode.split || secondaryId == null) {
      return const {};
    }
    final b = secondaryId!;
    if (a == b) return const {};
    const gap = 8.0;
    final fraction = splitFraction.clamp(0.3, 0.7);
    if (bounds.width > bounds.height) {
      final usable = math.max(0.0, bounds.width - gap);
      final leftWidth = usable * fraction;
      return {
        a: Rect.fromLTWH(bounds.left, bounds.top, leftWidth, bounds.height),
        b: Rect.fromLTWH(
          bounds.left + leftWidth + gap,
          bounds.top,
          usable - leftWidth,
          bounds.height,
        ),
      };
    }
    final usable = math.max(0.0, bounds.height - gap);
    final topHeight = usable * fraction;
    return {
      a: Rect.fromLTWH(bounds.left, bounds.top, bounds.width, topHeight),
      b: Rect.fromLTWH(
        bounds.left,
        bounds.top + topHeight + gap,
        bounds.width,
        usable - topHeight,
      ),
    };
  }
}

final mobileMultiWindowProvider =
    NotifierProvider<MobileMultiWindowController, MobileMultiWindowState>(
      MobileMultiWindowController.new,
    );

class MobileMultiWindowController extends Notifier<MobileMultiWindowState> {
  @override
  MobileMultiWindowState build() => const MobileMultiWindowState();

  void startSplit(int foregroundId, int? partnerId) {
    if (partnerId == foregroundId) partnerId = null;
    state = MobileMultiWindowState(
      mode: MobileMultiWindowMode.split,
      primaryId: foregroundId,
      secondaryId: partnerId,
      selectingPartner: partnerId == null,
    );
  }

  bool selectPartner(int windowId) {
    if (!state.selectingPartner || windowId == state.primaryId) return false;
    state = MobileMultiWindowState(
      mode: MobileMultiWindowMode.split,
      primaryId: state.primaryId,
      secondaryId: windowId,
      splitFraction: state.splitFraction,
    );
    return true;
  }

  void startFloating(int objectId, {int? backgroundId}) {
    state = MobileMultiWindowState(
      mode: MobileMultiWindowMode.floating,
      primaryId: objectId,
      secondaryId: backgroundId != objectId ? backgroundId : null,
      floatingFraction: state.floatingFraction,
    );
  }

  void setSplitFraction(double fraction) {
    if (state.mode != MobileMultiWindowMode.split) return;
    state = MobileMultiWindowState(
      mode: state.mode,
      primaryId: state.primaryId,
      secondaryId: state.secondaryId,
      splitFraction: fraction.clamp(0.3, 0.7),
      floatingFraction: state.floatingFraction,
    );
  }

  void moveFloating(Offset delta, Size size) {
    if (state.mode != MobileMultiWindowMode.floating) return;
    final b = state.usableBounds(size);
    if (b.isEmpty) return;
    final frame = state.floatingFrame(size);
    final x = (frame.left + delta.dx).clamp(b.left, b.right - frame.width);
    final y = (frame.top + delta.dy).clamp(b.top, b.bottom - frame.height);
    _updateFloating(
      Rect.fromLTWH(
        (x - b.left) / b.width,
        (y - b.top) / b.height,
        frame.width / b.width,
        frame.height / b.height,
      ),
    );
  }

  void resizeFloating(Offset delta, Size size) {
    if (state.mode != MobileMultiWindowMode.floating) return;
    final b = state.usableBounds(size);
    if (b.isEmpty) return;
    final frame = state.floatingFrame(size);
    final width = (frame.width + delta.dx)
        .clamp(math.min(210, b.width), b.right - frame.left)
        .toDouble();
    final height = (frame.height + delta.dy)
        .clamp(math.min(190, b.height), b.bottom - frame.top)
        .toDouble();
    _updateFloating(
      Rect.fromLTWH(
        (frame.left - b.left) / b.width,
        (frame.top - b.top) / b.height,
        width / b.width,
        height / b.height,
      ),
    );
  }

  void _updateFloating(Rect normalized) {
    state = MobileMultiWindowState(
      mode: state.mode,
      primaryId: state.primaryId,
      secondaryId: state.secondaryId,
      splitFraction: state.splitFraction,
      floatingFraction: normalized,
    );
  }

  void restore() {
    if (state.mode == MobileMultiWindowMode.single) return;
    state = const MobileMultiWindowState();
  }

  void reconcile(Set<int> ids) {
    if (state.mode == MobileMultiWindowMode.single) return;
    if (!ids.contains(state.primaryId)) {
      restore();
    } else if (state.secondaryId != null && !ids.contains(state.secondaryId)) {
      if (state.mode == MobileMultiWindowMode.floating) {
        startFloating(state.primaryId!);
      } else {
        restore();
      }
    }
  }
}
