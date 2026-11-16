import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'denial_window.dart';

enum MobileWorkspaceMode { automatic, split, scrolling }

/// Session-local stable object identities, never package/app IDs or raw PIDs.
@immutable
class MobileWorkspace {
  MobileWorkspace({
    required this.id,
    required Iterable<int> members,
    this.mode = MobileWorkspaceMode.automatic,
    Iterable<double>? weights,
    this.scrollOffset = 0,
    int? focusedId,
  }) : members = List<int>.unmodifiable(members),
       weights = List<double>.unmodifiable(weights ?? members.map((_) => 1.0)),
       focusedId = focusedId ?? members.first {
    assert(this.members.length >= 2);
    assert(this.members.toSet().length == this.members.length);
    assert(this.weights.length == this.members.length);
  }

  final int id;
  final List<int> members;
  final List<double> weights;
  final MobileWorkspaceMode mode;
  final double scrollOffset;
  final int focusedId;

  const MobileWorkspace._retained({
    required this.id,
    required this.members,
    required this.weights,
    required this.mode,
    required this.scrollOffset,
    required this.focusedId,
  });

  MobileWorkspace copyWith({
    MobileWorkspaceMode? mode,
    List<double>? weights,
    double? scrollOffset,
    int? focusedId,
  }) => MobileWorkspace._retained(
    id: id,
    members: members,
    mode: mode ?? this.mode,
    weights: weights == null
        ? this.weights
        : List<double>.unmodifiable(weights),
    scrollOffset: scrollOffset ?? this.scrollOffset,
    focusedId: focusedId ?? this.focusedId,
  );
}

/// Remove stale identities and dissolve singletons rather than keeping a
/// hidden reduced-size window after its partner closes.
List<MobileWorkspace> reconcileMobileWorkspaces(
  List<MobileWorkspace> groups,
  Iterable<DenialWindow> windows,
) {
  final live = {
    for (final w in windows)
      if (w.isUserApp) w.objectId,
  };
  final claimed = <int>{};
  final result = <MobileWorkspace>[];
  for (final group in groups) {
    final indices = [
      for (var i = 0; i < group.members.length; i++)
        if (live.contains(group.members[i]) &&
            !claimed.contains(group.members[i]))
          i,
    ];
    if (indices.length < 2) continue;
    final members = [for (final i in indices) group.members[i]];
    claimed.addAll(members);
    if (listEquals(members, group.members)) {
      result.add(group);
      continue;
    }
    result.add(
      MobileWorkspace(
        id: group.id,
        members: members,
        weights: [for (final i in indices) group.weights[i]],
        mode: group.mode,
        scrollOffset: group.scrollOffset,
        focusedId: members.contains(group.focusedId)
            ? group.focusedId
            : members.first,
      ),
    );
  }
  return result.length == groups.length &&
          List.generate(
            result.length,
            (i) => identical(result[i], groups[i]),
          ).every((same) => same)
      ? groups
      : List.unmodifiable(result);
}

class MobileWorkspacePane {
  const MobileWorkspacePane({required this.objectId, required this.frame});
  final int objectId;
  final Rect frame;

  // Workspace controls float over the scene only when requested. Native,
  // self-managed and local clients all receive the complete pane canvas.
  Rect clientFrame(DenialWindow _) => frame;
}

/// One geometry source for rendering, resize negotiation and native hit testing.
/// Scroll offsets only translate presentation: never reconfigure a client for
/// every scrolling pixel. Fixed-aspect clients remain contained in their pane.
class MobileWorkspaceLayout {
  const MobileWorkspaceLayout({
    required this.viewport,
    required this.horizontal,
    required this.scrolling,
    required this.panes,
    required this.maxScroll,
    required this.offset,
    required this.minimumExtents,
  });

  static const status = 48.0;
  static const toolbar = 0.0;
  static const header = 0.0;
  static const divider = 12.0;
  static const minimumExtent = 320.0;

  final Rect viewport;
  final bool horizontal;
  final bool scrolling;
  final List<MobileWorkspacePane> panes;
  final double maxScroll;
  final double offset;
  final List<double> minimumExtents;

  factory MobileWorkspaceLayout.resolve(
    Size size,
    MobileWorkspace workspace, {
    Iterable<DenialWindow> windows = const [],
  }) {
    final horizontal = size.width > size.height;
    final viewport = Rect.fromLTWH(
      0,
      status + toolbar,
      size.width,
      math.max(0.0, size.height - status - toolbar),
    );
    final main = horizontal ? viewport.width : viewport.height;
    final count = workspace.members.length;
    final available = math.max(0.0, main - divider * (count - 1));
    final byId = {for (final window in windows) window.objectId: window};
    final minimums = List<double>.filled(count, minimumExtent);
    for (var i = 0; i < count; i++) {
      final window = byId[workspace.members[i]];
      if (window == null) continue;
      final hint = horizontal ? window.minimumWidth : window.minimumHeight;
      minimums[i] = math.max(minimumExtent, hint.clamp(0, 16384)).toDouble();
    }
    final minimumTotal = minimums.fold(0.0, (sum, value) => sum + value);
    final scrolling =
        workspace.mode == MobileWorkspaceMode.scrolling ||
        (workspace.mode == MobileWorkspaceMode.automatic &&
            available < minimumTotal);
    final weights = [
      for (final w in workspace.weights)
        w.isFinite && w > 0 ? w.clamp(0.1, 10.0).toDouble() : 1.0,
    ];
    final total = weights.fold(0.0, (sum, w) => sum + w);
    final extents = scrolling
        ? [
            for (var i = 0; i < count; i++)
              math.max(minimums[i], main * 0.72 * weights[i]).toDouble(),
          ]
        : [for (final w in weights) available * w / total];
    // Water-fill within real minimums when a split is possible. A large
    // client's minimum must not squash its neighbor or cause resize loops.
    if (!scrolling && minimumTotal <= available) {
      var remaining = available;
      final pending = {for (var i = 0; i < count; i++) i};
      while (pending.isNotEmpty) {
        final sum = pending.fold(0.0, (value, i) => value + weights[i]);
        final constrained = pending
            .where((i) => remaining * weights[i] / sum < minimums[i])
            .toList();
        if (constrained.isEmpty) {
          for (final i in pending) {
            extents[i] = remaining * weights[i] / sum;
          }
          break;
        }
        for (final i in constrained) {
          extents[i] = minimums[i];
          remaining -= minimums[i];
          pending.remove(i);
        }
      }
    }
    final maxScroll = math.max(
      0.0,
      extents.fold(0.0, (sum, w) => sum + w) + divider * (count - 1) - main,
    );
    final offset = workspace.scrollOffset.isFinite
        ? workspace.scrollOffset.clamp(0.0, maxScroll).toDouble()
        : 0.0;
    var position = -offset;
    final panes = <MobileWorkspacePane>[];
    for (var i = 0; i < count; i++) {
      panes.add(
        MobileWorkspacePane(
          objectId: workspace.members[i],
          frame: horizontal
              ? Rect.fromLTWH(
                  viewport.left + position,
                  viewport.top,
                  extents[i],
                  viewport.height,
                )
              : Rect.fromLTWH(
                  viewport.left,
                  viewport.top + position,
                  viewport.width,
                  extents[i],
                ),
        ),
      );
      position += extents[i] + divider;
    }
    return MobileWorkspaceLayout(
      viewport: viewport,
      horizontal: horizontal,
      scrolling: scrolling,
      panes: List.unmodifiable(panes),
      maxScroll: maxScroll,
      offset: offset,
      minimumExtents: List.unmodifiable(minimums),
    );
  }

  Rect dividerAfter(int index) {
    final frame = panes[index].frame;
    return horizontal
        ? Rect.fromLTWH(frame.right, frame.top, divider, frame.height)
        : Rect.fromLTWH(frame.left, frame.bottom, frame.width, divider);
  }

  List<double> resizedWeights(MobileWorkspace group, int index, double delta) {
    if (index < 0 || index + 1 >= panes.length || !delta.isFinite) {
      return group.weights;
    }
    final current = [
      for (final p in panes) horizontal ? p.frame.width : p.frame.height,
    ];
    final pair = current[index] + current[index + 1];
    final minimumTotal = minimumExtents[index] + minimumExtents[index + 1];
    final minimumScale = math.min(1.0, pair / math.max(1.0, minimumTotal));
    final firstMinimum = minimumExtents[index] * minimumScale;
    final secondMinimum = minimumExtents[index + 1] * minimumScale;
    final first = (current[index] + delta).clamp(
      firstMinimum,
      pair - secondMinimum,
    );
    current[index] = first.toDouble();
    current[index + 1] = pair - first;
    if (scrolling) {
      final main = horizontal ? viewport.width : viewport.height;
      return [
        for (final extent in current) extent / math.max(1.0, main * 0.72),
      ];
    }
    final average =
        current.fold(0.0, (sum, extent) => sum + extent) / current.length;
    return [for (final extent in current) extent / math.max(1.0, average)];
  }
}
