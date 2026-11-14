import 'package:denial_dart_shell/src/models/mobile_workspace.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/mobile_motion_harness.dart';

void main() {
  MobileWorkspace group(
    int count, {
    MobileWorkspaceMode mode = MobileWorkspaceMode.automatic,
  }) => MobileWorkspace(
    id: 1,
    members: List.generate(count, (i) => i + 1),
    mode: mode,
  );

  test('two apps fit side by side on the tablet landscape output', () {
    final layout = MobileWorkspaceLayout.resolve(
      const Size(1024, 768),
      group(2),
    );
    expect(layout.horizontal, isTrue);
    expect(layout.scrolling, isFalse);
    expect(layout.panes.first.frame, const Rect.fromLTWH(0, 88, 506, 680));
    expect(layout.panes.last.frame, const Rect.fromLTWH(518, 88, 506, 680));
  });

  test(
    'portrait uses a top-bottom split rather than stretching app textures',
    () {
      final layout = MobileWorkspaceLayout.resolve(
        const Size(768, 1024),
        group(2),
      );
      expect(layout.horizontal, isFalse);
      expect(layout.scrolling, isFalse);
      expect(layout.panes.first.frame.height, 462);
      expect(layout.panes.last.frame.bottom, 1024);
    },
  );

  test('automatic layout switches to scrolling when panes cannot fit', () {
    final layout = MobileWorkspaceLayout.resolve(
      const Size(768, 1024),
      group(3),
    );
    expect(layout.scrolling, isTrue);
    expect(layout.maxScroll, greaterThan(0));
    expect(layout.panes.every((p) => p.frame.height >= 320), isTrue);
  });

  test('scrolling translates panes without changing client sizes', () {
    final workspace = group(3);
    final a = MobileWorkspaceLayout.resolve(const Size(1024, 768), workspace);
    final b = MobileWorkspaceLayout.resolve(
      const Size(1024, 768),
      workspace.copyWith(scrollOffset: 80),
    );
    // Three panes happen to fit; explicitly select scrolling for this check.
    final c = MobileWorkspaceLayout.resolve(
      const Size(1024, 768),
      workspace.copyWith(mode: MobileWorkspaceMode.scrolling),
    );
    final d = MobileWorkspaceLayout.resolve(
      const Size(1024, 768),
      workspace.copyWith(mode: MobileWorkspaceMode.scrolling, scrollOffset: 80),
    );
    expect(a.panes.first.frame.size, b.panes.first.frame.size);
    expect(c.panes.first.frame.size, d.panes.first.frame.size);
    expect(d.panes.first.frame.left, c.panes.first.frame.left - 80);
  });

  test('divider resize conserves pair extent and prevents zero-size panes', () {
    final workspace = group(2);
    final before = MobileWorkspaceLayout.resolve(
      const Size(1024, 768),
      workspace,
    );
    final after = MobileWorkspaceLayout.resolve(
      const Size(1024, 768),
      workspace.copyWith(weights: before.resizedWeights(workspace, 0, 10000)),
    );
    expect(after.panes.last.frame.width, closeTo(320, 0.001));
    expect(after.panes.last.frame.right, closeTo(1024, 0.001));
  });

  test('rotation clamps old scroll offsets into the new range', () {
    final workspace = group(3).copyWith(scrollOffset: double.infinity);
    final layout = MobileWorkspaceLayout.resolve(
      const Size(768, 1024),
      workspace,
    );
    expect(layout.offset, 0);
    expect(layout.panes.every((p) => p.frame.isFinite), isTrue);
  });

  test(
    'real client minimums trigger automatic scrolling instead of squeeze',
    () {
      final layout = MobileWorkspaceLayout.resolve(
        const Size(1024, 768),
        group(2),
        windows: [
          motionWindow(1, minimumWidth: 700),
          motionWindow(2, minimumWidth: 400),
        ],
      );
      expect(layout.scrolling, isTrue);
      expect(layout.panes[0].frame.width, greaterThanOrEqualTo(700));
      expect(layout.panes[1].frame.width, greaterThanOrEqualTo(400));
    },
  );

  test('asymmetric split and divider preserve both real client minimums', () {
    final workspace = group(2);
    final windows = [motionWindow(1, minimumWidth: 650), motionWindow(2)];
    final before = MobileWorkspaceLayout.resolve(
      const Size(1024, 768),
      workspace,
      windows: windows,
    );
    expect(before.scrolling, isFalse);
    expect(before.panes[0].frame.width, closeTo(650, .001));
    final after = MobileWorkspaceLayout.resolve(
      const Size(1024, 768),
      workspace.copyWith(weights: before.resizedWeights(workspace, 0, -10000)),
      windows: windows,
    );
    expect(after.panes[0].frame.width, closeTo(650, .001));
    expect(after.panes[1].frame.width, closeTo(362, .001));
  });

  test(
    'portrait minimums account for native header but not client-owned inset',
    () {
      final native = motionWindow(1, minimumHeight: 450);
      final android = motionWindow(
        2,
        minimumHeight: 450,
        selfManagedInsets: true,
      );
      final layout = MobileWorkspaceLayout.resolve(
        const Size(768, 1024),
        group(2),
        windows: [native, android],
      );
      expect(layout.minimumExtents, [498, 450]);
      expect(layout.scrolling, isTrue);
      expect(
        layout.panes[0].clientFrame(native).top,
        layout.panes[0].frame.top + 48,
      );
      expect(layout.panes[1].clientFrame(android), layout.panes[1].frame);
    },
  );
}
