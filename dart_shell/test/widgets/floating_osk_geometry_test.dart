import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/widgets/osk/floating_osk_geometry.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('floating keyboard respects horizontal safe areas after rotation', () {
    for (final view in [const Size(768, 1024), const Size(1024, 768)]) {
      const safe = EdgeInsets.fromLTRB(44, 24, 32, 18);
      for (final placement in [
        const TabletOskFloatingPlacement(),
        const TabletOskFloatingPlacement(x: 0, y: 0),
        const TabletOskFloatingPlacement(
          x: 9999,
          y: 9999,
          width: 9999,
          height: 9999,
        ),
      ]) {
        final rect = resolveFloatingOskRect(
          viewSize: view,
          safePadding: safe,
          placement: placement,
        );
        expect(rect.left, greaterThanOrEqualTo(56));
        expect(rect.right, lessThanOrEqualTo(view.width - 44));
        expect(rect.top, greaterThanOrEqualTo(32));
        expect(rect.bottom, lessThanOrEqualTo(view.height - 34));
      }
    }
  });

  test('horizontal safe areas can exhaust the keyboard viewport', () {
    final rect = resolveFloatingOskRect(
      viewSize: const Size(100, 768),
      safePadding: const EdgeInsets.only(left: 40, right: 40),
      placement: const TabletOskFloatingPlacement(),
    );
    expect(rect, Rect.zero);
  });

  test('Mi Pad 2 portrait floating keyboard defaults to lower-right', () {
    const view = Size(768, 1024);
    const placement = TabletOskFloatingPlacement();

    final rect = resolveFloatingOskRect(
      viewSize: view,
      safePadding: EdgeInsets.zero,
      placement: placement,
    );

    expect(rect.width, 470);
    expect(rect.height, 300);
    expect(rect.right, 756);
    expect(rect.bottom, 1008);
  });

  test('floating keyboard placement clamps inside safe viewport', () {
    const view = Size(768, 1024);
    const safe = EdgeInsets.only(top: 24, bottom: 18);
    const placement = TabletOskFloatingPlacement(
      x: 9999,
      y: 9999,
      width: 9999,
      height: 9999,
    );

    final rect = resolveFloatingOskRect(
      viewSize: view,
      safePadding: safe,
      placement: placement,
    );

    expect(rect.left, greaterThanOrEqualTo(floatingOskHorizontalMargin));
    expect(rect.top, greaterThanOrEqualTo(32));
    expect(rect.right, lessThanOrEqualTo(756));
    expect(rect.bottom, lessThanOrEqualTo(990));
  });
}
