import 'package:denial_dart_shell/src/desktop/desktop_fullscreen_content_fit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('non-fullscreen content keeps the requested rectangle', () {
    const target = Rect.fromLTWH(12, 20, 640, 480);
    expect(
      desktopFullscreenContentRect(
        target: target,
        sourceSize: const Size(1920, 1080),
        fullscreen: false,
      ),
      target,
    );
  });

  test('landscape client is fully visible on a portrait fullscreen output', () {
    const target = Rect.fromLTWH(0, 0, 768, 1024);
    final result = desktopFullscreenContentRect(
      target: target,
      sourceSize: const Size(1920, 1080),
      fullscreen: true,
    );

    expect(result.left, closeTo(0, 0.001));
    expect(result.width, closeTo(768, 0.001));
    expect(result.height, closeTo(432, 0.001));
    expect(result.top, closeTo(296, 0.001));
  });

  test('portrait client is fully visible on a landscape fullscreen output', () {
    const target = Rect.fromLTWH(0, 0, 1024, 768);
    final result = desktopFullscreenContentRect(
      target: target,
      sourceSize: const Size(720, 1280),
      fullscreen: true,
    );

    expect(result.height, closeTo(768, 0.001));
    expect(result.width, closeTo(432, 0.001));
    expect(result.left, closeTo(296, 0.001));
    expect(result.top, closeTo(0, 0.001));
  });

  test('matching aspect ratio still fills fullscreen', () {
    const target = Rect.fromLTWH(0, 0, 1280, 720);
    expect(
      desktopFullscreenContentRect(
        target: target,
        sourceSize: const Size(1920, 1080),
        fullscreen: true,
      ),
      target,
    );
  });
}
