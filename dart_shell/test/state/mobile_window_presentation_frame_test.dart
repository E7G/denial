import 'package:denial_dart_shell/src/state/shell_input_layout_coordinator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native mobile client is contained in a centered app tile', () {
    final frame = mobileWindowPresentationFrame(
      viewSize: const Size(768, 1024),
      frame: const Rect.fromLTWH(0, 0, 1920, 1080),
      contentOffset: 0,
      contain: true,
    );

    expect(frame.left, closeTo(24, 0.001));
    expect(frame.top, closeTo(309.5, 0.001));
    expect(frame.width, closeTo(720, 0.001));
    expect(frame.height, closeTo(405, 0.001));
  });

  test('native app tile keeps balanced tablet margins', () {
    final tile = mobileNativeAppTileBounds(viewSize: const Size(768, 1024));

    expect(tile, const Rect.fromLTRB(24, 28, 744, 996));
  });

  test('legacy cover behavior remains available for local shell apps', () {
    final frame = mobileWindowPresentationFrame(
      viewSize: const Size(768, 1024),
      frame: const Rect.fromLTWH(0, 0, 1920, 1080),
      contentOffset: 0,
      contain: false,
    );

    expect(frame.height, closeTo(1024, 0.001));
    expect(frame.width, greaterThan(768));
    expect(frame.left, lessThan(0));
  });

  test('keyboard viewport offset moves the complete centered app tile', () {
    final frame = mobileWindowPresentationFrame(
      viewSize: const Size(768, 1024),
      frame: const Rect.fromLTWH(0, 0, 1920, 1080),
      contentOffset: 180,
      contain: true,
    );

    expect(frame.top, closeTo(129.5, 0.001));
    expect(frame.left, closeTo(24, 0.001));
    expect(frame.width, closeTo(720, 0.001));
    expect(frame.height, closeTo(405, 0.001));
  });
}
