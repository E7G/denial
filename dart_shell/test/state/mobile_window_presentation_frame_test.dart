import 'package:denial_dart_shell/src/state/shell_input_layout_coordinator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('landscape native client maximizes below the real status bar', () {
    final frame = mobileWindowPresentationFrame(
      viewSize: const Size(768, 1024),
      frame: const Rect.fromLTWH(0, 0, 1920, 1080),
      contentOffset: 0,
      contain: true,
    );

    expect(frame.left, closeTo(0, 0.001));
    expect(frame.top, closeTo(320, 0.001));
    expect(frame.width, closeTo(768, 0.001));
    expect(frame.height, closeTo(432, 0.001));
  });

  test('matching native aspect fills the complete area below status bar', () {
    final frame = mobileWindowPresentationFrame(
      viewSize: const Size(768, 1024),
      frame: const Rect.fromLTWH(0, 0, 768, 976),
      contentOffset: 0,
      contain: true,
    );

    expect(frame, const Rect.fromLTWH(0, 48, 768, 976));
  });

  test('legacy cover behavior remains full-screen for local shell apps', () {
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

  test('stationary keyboard overlay keeps native content anchored', () {
    final frame = mobileWindowPresentationFrame(
      viewSize: const Size(768, 1024),
      frame: const Rect.fromLTWH(0, 0, 1920, 1080),
      contentOffset: 0,
      contain: true,
    );

    expect(frame.left, closeTo(0, 0.001));
    expect(frame.top, closeTo(320, 0.001));
    expect(frame.width, closeTo(768, 0.001));
    expect(frame.height, closeTo(432, 0.001));
  });
}
