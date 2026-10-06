import 'package:denial_dart_shell/src/state/shell_input_layout_coordinator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'landscape native client fills width and leaves only proportional space',
    () {
      final frame = mobileWindowPresentationFrame(
        viewSize: const Size(768, 1024),
        frame: const Rect.fromLTWH(0, 0, 1920, 1080),
        contentOffset: 0,
        contain: true,
      );

      expect(frame.left, closeTo(0, 0.001));
      expect(frame.top, closeTo(296, 0.001));
      expect(frame.width, closeTo(768, 0.001));
      expect(frame.height, closeTo(432, 0.001));
    },
  );

  test('matching aspect ratio fills the complete app viewport', () {
    final frame = mobileWindowPresentationFrame(
      viewSize: const Size(768, 1024),
      frame: const Rect.fromLTWH(0, 0, 768, 1024),
      contentOffset: 0,
      contain: true,
    );

    expect(frame, const Rect.fromLTWH(0, 0, 768, 1024));
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

  test('keyboard viewport offset shifts the same proportional frame', () {
    final frame = mobileWindowPresentationFrame(
      viewSize: const Size(768, 1024),
      frame: const Rect.fromLTWH(0, 0, 1920, 1080),
      contentOffset: 180,
      contain: true,
    );

    expect(frame.left, closeTo(0, 0.001));
    expect(frame.top, closeTo(116, 0.001));
    expect(frame.width, closeTo(768, 0.001));
    expect(frame.height, closeTo(432, 0.001));
  });
}
