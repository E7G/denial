import 'package:denial_dart_shell/src/widgets/shade/shade_progress.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('screenshot waits for the entire shade exit and two frames', (
    tester,
  ) async {
    final controller = AnimationController(vsync: tester, value: 1);
    addTearDown(controller.dispose);
    final progress = ProxyAnimation(controller);
    bool? result;
    final wait = waitForShadeFullyClosed(progress).then((value) {
      result = value;
    });

    controller.animateTo(0, duration: const Duration(milliseconds: 450));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(result, isNull);
    expect(progress.value, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 250));
    expect(progress.value, 0);
    expect(result, isNull);
    // Each awaited endOfFrame schedules its next frame in a microtask,
    // so advance enough actual frames for both repaint boundaries.
    for (var frame = 0; frame < 8 && result == null; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(result, isTrue);
    await wait;
    expect(result, isTrue);
  });

  testWidgets('a stuck shade never authorizes capture', (tester) async {
    final controller = AnimationController(vsync: tester, value: 1);
    addTearDown(controller.dispose);
    bool? result;
    final wait = waitForShadeFullyClosed(
      controller,
      timeout: const Duration(milliseconds: 400),
    ).then((value) => result = value);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(result, isFalse);
    await wait;
    expect(result, isFalse);
  });
}
