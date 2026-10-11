import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denial_dart_shell/src/launcher/models/home_grid_item.dart';
import 'package:denial_dart_shell/src/launcher/widgets/home_app_page.dart';

void main() {
  test('one shared blur mask follows each visible tile geometry', () {
    final clock = HomeGridItem.clock(colSpan: 2, rowSpan: 1);
    final date = HomeGridItem.date();
    final first = homeTileBlurRect(
      localIndex: 0, item: clock,
      columns: 3, tileWidth: 80, tileHeight: 90, gap: 8,
    );
    final second = homeTileBlurRect(
      localIndex: 2, item: date,
      columns: 3, tileWidth: 80, tileHeight: 90, gap: 8,
    );
    expect(first, const Rect.fromLTWH(0, 0, 168, 90));
    expect(second, const Rect.fromLTWH(176, 0, 80, 90));
    final clipper = HomeTileBackdropClipper([first, second]);
    final mask = clipper.getClip(const Size(256, 200));
    expect(mask.contains(const Offset(30, 30)), true);
    expect(mask.contains(const Offset(178, 30)), true);
    expect(mask.contains(const Offset(170, 30)), false);
    expect(mask.contains(const Offset(10, 100)), false);
  });

  test('tile blur mask is clipped to page for partial scrolling', () {
    final clipper = HomeTileBackdropClipper([
      const Rect.fromLTWH(-40, -20, 150, 110),
      const Rect.fromLTWH(120, 80, 50, 40),
    ]);
    final mask = clipper.getClip(const Size(140, 100));
    expect(mask.contains(const Offset(20, 20)), true);
    expect(mask.contains(const Offset(130, 90)), true);
    expect(mask.contains(const Offset(115, 95)), false);
  });

  test('unchanged geometry does not trigger expensive reclip', () {
    const old = HomeTileBackdropClipper([
      Rect.fromLTWH(0, 0, 80, 80),
    ]);
    const same = HomeTileBackdropClipper([
      Rect.fromLTWH(0, 0, 80, 80),
    ]);
    const changed = HomeTileBackdropClipper([
      Rect.fromLTWH(0, 0, 160, 80),
    ]);
    expect(same.shouldReclip(old), false);
    expect(changed.shouldReclip(old), true);
  });
}
