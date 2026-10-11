import 'package:denial_dart_shell/src/state/mobile_multi_window.dart';
import 'package:denial_dart_shell/src/state/shell_input_layout_coordinator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('single-app fullscreen continues to publish client touch routing', () {
    final targets = mobileInputTargets(
      multiActive: false,
      normalWindowId: 42,
      primaryWindowId: null,
      secondaryWindowId: null,
      multiRects: const <int, Rect>{},
    );
    expect(targets.length, 1);
    expect(targets.single.objectId, 42);
    expect(targets.single.viewport, isNull);
  });

  test('launcher has no fake client input region in normal mode', () {
    final targets = mobileInputTargets(
      multiActive: false,
      normalWindowId: null,
      primaryWindowId: null,
      secondaryWindowId: null,
      multiRects: const <int, Rect>{},
    );
    expect(targets, isEmpty);
  });

  test('split and floating touch map to both correctly ordered clients', () {
    const first = Rect.fromLTWH(0, 48, 384, 700);
    const second = Rect.fromLTWH(392, 48, 376, 700);
    final targets = mobileInputTargets(
      multiActive: true,
      normalWindowId: 2,
      primaryWindowId: 1,
      secondaryWindowId: 2,
      multiRects: const {1: first, 2: second},
    );
    expect(targets.map((entry) => entry.objectId).toList(), [1, 2]);
    expect(targets.first.viewport, first);
    expect(targets.last.viewport, second);
  });

  test('portrait split has disjoint top/bottom native client rectangles', () {
    const layout = MobileMultiWindowState(
      mode: MobileMultiWindowMode.split,
      primaryId: 10,
      secondaryId: 20,
    );
    final rects = layout.windowRects(const Size(768, 1024));
    expect(rects.keys.toSet(), {10, 20});
    expect(rects[10]!.top, 48);
    expect(rects[10]!.width, 768);
    expect(rects[20]!.bottom, 1000);
    expect(rects[10]!.bottom + 8, rects[20]!.top);
    expect(rects[10]!.overlaps(rects[20]!), false);
  });

  test(
    'landscape split positions clients left/right with adjustable divider',
    () {
      const layout = MobileMultiWindowState(
        mode: MobileMultiWindowMode.split,
        primaryId: 10,
        secondaryId: 20,
        splitFraction: 0.6,
      );
      final rects = layout.windowRects(const Size(1024, 768));
      expect(rects[10]!.left, 0);
      expect(rects[20]!.right, 1024);
      expect(rects[10]!.right + 8, rects[20]!.left);
      expect(rects[10]!.top, 48);
      expect(rects[10]!.height, rects[20]!.height);
    },
  );

  test('floating frame and native content remain inside safe viewport', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(mobileMultiWindowProvider.notifier);
    controller.startFloating(11);
    const size = Size(768, 1024);
    controller.moveFloating(const Offset(9999, 9999), size);
    controller.resizeFloating(const Offset(9999, 9999), size);
    final state = container.read(mobileMultiWindowProvider);
    final b = state.usableBounds(size);
    final frame = state.floatingFrame(size);
    final content = state.windowRects(size)[11]!;
    expect(frame.right <= b.right && frame.bottom <= b.bottom, true);
    expect(
      content.right <= frame.right && content.bottom <= frame.bottom,
      true,
    );
    expect(content.top, frame.top + 32);
    expect(content.width, frame.width);
  });

  test('floating one app above another retains two independent viewports', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(mobileMultiWindowProvider.notifier);
    ctrl.startFloating(100, backgroundId: 200);
    final state = container.read(mobileMultiWindowProvider);
    const size = Size(1024, 768);
    final rects = state.windowRects(size);
    expect(rects.keys.toSet(), {100, 200});
    expect(rects[200], state.usableBounds(size));
    expect(rects[100]!.width < rects[200]!.width, true);
    ctrl.reconcile({100});
    expect(
      container.read(mobileMultiWindowProvider).mode,
      MobileMultiWindowMode.floating,
    );
    expect(container.read(mobileMultiWindowProvider).secondaryId, isNull);
  });

  test('select second app, resize split, close peer and return to single', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(mobileMultiWindowProvider.notifier);
    ctrl.startSplit(1, null);
    expect(container.read(mobileMultiWindowProvider).selectingPartner, true);
    expect(ctrl.selectPartner(1), false);
    expect(ctrl.selectPartner(2), true);
    ctrl.setSplitFraction(1.4);
    expect(container.read(mobileMultiWindowProvider).splitFraction, 0.7);
    ctrl.reconcile({1});
    expect(
      container.read(mobileMultiWindowProvider).mode,
      MobileMultiWindowMode.single,
    );
  });

  test('native/client visual mapping stays inside requested floating rect', () {
    const viewport = Rect.fromLTWH(200, 130, 320, 290);
    const native = Rect.fromLTWH(200, 130, 640, 580);
    final visual = mobileWindowFitInRect(
      frame: native,
      viewport: viewport,
      contain: true,
    );
    expect(visual, viewport);
  });

  test('rotation preserves normalized floating geometry and clamps edges', () {
    const state = MobileMultiWindowState(
      mode: MobileMultiWindowMode.floating,
      primaryId: 100,
    );
    for (final size in [
      const Size(768, 1024),
      const Size(1024, 768),
      const Size(280, 640),
    ]) {
      final frame = state.floatingFrame(size);
      final bounds = state.usableBounds(size);
      expect(frame.left >= bounds.left && frame.right <= bounds.right, true);
      expect(frame.top >= bounds.top && frame.bottom <= bounds.bottom, true);
      expect(frame.width > 0 && frame.height > 0, true);
    }
  });
}
