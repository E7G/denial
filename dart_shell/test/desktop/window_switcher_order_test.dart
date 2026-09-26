import 'dart:math';

import 'package:denial_dart_shell/src/desktop/window_switcher_order.dart';
import 'package:test/test.dart';

void main() {
  test('indexed lookup matches list behavior, including duplicates and unknown IDs', () {
    final random = Random(4817);
    for (var length = 0; length < 128; length++) {
      final ids = [for (var i = 0; i < length; i++) random.nextInt(64)];
      final order = WindowSwitcherOrder(ids);
      expect(order.objectIds, ids);
      for (var id = -1; id <= 64; id++) {
        expect(order.indexOf(id), ids.indexOf(id));
        expect(order.contains(id), ids.contains(id));
      }
    }
  });

  test('a candidate order owns its snapshot and rejects external mutation', () {
    final source = [5, 8, 3];
    final order = WindowSwitcherOrder(source);
    source
      ..clear()
      ..add(10);
    expect(order.objectIds, [5, 8, 3]);
    expect(order.indexOf(8), 1);
    expect(order.contains(10), isFalse);
    expect(() => order.objectIds.add(10), throwsUnsupportedError);
    expect(() => order.objectIds[0] = 10, throwsUnsupportedError);
  });
}
