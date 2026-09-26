import 'dart:math';

import 'package:denial_dart_shell/src/desktop/transient_family_order.dart';
import 'package:test/test.dart';

import '../support/legacy_transient_family_order.dart';

List<int> _order(int active, Map<int, int> placements, Map<int, int> parents) =>
    orderTransientFamily(
      activatedObjectId: active,
      placements: placements,
      parentIds: parents,
      zOrder: (z) => z,
    );

void main() {
  test(
    'unrelated windows and absent activated windows need no family sort',
    () {
      expect(_order(2, {1: 0, 2: 1}, {}), [2]);
      expect(_order(3, {1: 0, 2: 1}, {}), isEmpty);
      expect(_order(3, {1: 0, 2: 1, 3: 2}, {2: 1}), [3]);
    },
  );

  test('ancestors precede descendants despite their previous z values', () {
    expect(_order(1, {1: 100, 2: 50, 3: 0}, {2: 1, 3: 2}), [1, 2, 3]);
  });

  test('the activated sibling branch moves above the other branches', () {
    final placements = {1: 0, 2: 1, 3: 2, 4: 3, 5: 4};
    final parents = {2: 1, 3: 1, 4: 2, 5: 3};
    expect(_order(2, placements, parents), [1, 3, 5, 2, 4]);
    expect(_order(3, placements, parents), [1, 2, 4, 3, 5]);
  });

  test('equal-depth siblings retain z order with an object-id tie break', () {
    expect(_order(1, {1: 99, 4: 0, 3: 0, 2: -1}, {2: 1, 3: 1, 4: 1}), [
      1,
      2,
      3,
      4,
    ]);
  });

  test('missing placements can still connect descendants to a family', () {
    expect(_order(1, {1: 0, 3: 1}, {2: 1, 3: 2}), [1, 3]);
    expect(_order(3, {1: 0, 3: 1}, {2: 1, 3: 2}), [3]);
  });

  test('malformed cycles preserve the bounded legacy fallback', () {
    final placements = {1: 0, 2: 0, 3: 0, 4: 0};
    for (final parents in [
      {1: 1},
      {1: 2, 2: 1, 3: 2},
      {1: 2, 2: 3, 3: 1, 4: 3},
    ]) {
      for (final active in placements.keys) {
        expect(
          _order(active, placements, parents),
          legacyTransientFamilyOrder(active, placements, parents),
        );
      }
    }
  });

  test('cycles crossing a missing placement retain branch membership', () {
    expect(
      _order(3, {1: 0, 2: 1, 3: 2, 5: 4}, {1: 4, 2: 1, 3: 2, 4: 3, 5: 2}),
      [1, 2, 3, 5],
    );
  });

  test('random graphs including missing nodes and cycles match legacy order', () {
    final random = Random(3802);
    for (var sample = 0; sample < 10000; sample++) {
      final size = random.nextInt(48) + 1;
      final placements = {
        for (var id = 0; id < size; id++)
          if (random.nextInt(8) != 0) id: random.nextInt(16) - 8,
      };
      final parents = {
        for (var id = 0; id < size; id++)
          if (random.nextInt(3) != 0) id: random.nextInt(size + 2),
      };
      final active = random.nextInt(size + 1);
      expect(
        _order(active, placements, parents),
        legacyTransientFamilyOrder(active, placements, parents),
        reason:
            'sample $sample, active $active, parents $parents, placements $placements',
      );
    }
  });

  test('deep families require no recursive call stack', () {
    const size = 10000;
    final placements = {for (var id = 0; id < size; id++) id: id};
    final parents = {for (var id = 1; id < size; id++) id: id - 1};
    expect(_order(0, placements, parents), List.generate(size, (i) => i));
  });

  test(
    'z values are read once per member rather than for every comparison',
    () {
      final placements = {for (var id = 0; id < 64; id++) id: id};
      var reads = 0;
      final ordered = orderTransientFamily(
        activatedObjectId: 0,
        placements: placements,
        parentIds: {for (var id = 1; id < 64; id++) id: 0},
        zOrder: (id) {
          reads++;
          return -id;
        },
      );
      expect(reads, placements.length);
      expect(ordered, [0, for (var id = 63; id > 0; id--) id]);
    },
  );
}
