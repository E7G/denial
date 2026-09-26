import 'dart:math';

import 'package:denial_dart_shell/src/models/system_tray_item.dart';
import 'package:denial_dart_shell/src/services/system_tray_order.dart';
import 'package:test/test.dart';

void main() {
  test('native-only snapshots retain list and item identity', () {
    final native = orderSystemTrayItems([_item('a', 'A'), _item('b', 'B')]);
    final result = combineSystemTrayItems(native, const []);
    expect(identical(result, native), isTrue);
    expect(() => result.clear(), throwsUnsupportedError);
  });

  test('legacy-only snapshots own their immutable ordered list', () {
    final source = [_item('b', 'B'), _item('a', 'A')];
    final result = combineSystemTrayItems(const [], source);
    expect(source.first.id, 'b');
    expect(result.map((item) => item.id), ['a', 'b']);
    source.clear();
    expect(result, hasLength(2));
    expect(() => result.clear(), throwsUnsupportedError);
  });

  test(
    'combined ordering preserves attention, active and passive priorities',
    () {
      final native = orderSystemTrayItems([
        _item('n1', 'Zulu', status: SystemTrayStatus.needsAttention),
        _item('n2', 'browser'),
        _item('n3', 'A', status: SystemTrayStatus.passive),
      ]);
      final legacy = [
        _item('l1', 'Steam'),
        _item('l2', 'audio', status: SystemTrayStatus.needsAttention),
        _item('l3', 'Äpp'),
      ];
      final result = combineSystemTrayItems(native, legacy);
      expect(result.map((item) => item.id), [
        'l2',
        'n1',
        'n2',
        'l1',
        'l3',
        'n3',
      ]);
      expect(
        result.every((item) => native.contains(item) || legacy.contains(item)),
        isTrue,
      );
      expect(() => result[0] = native.first, throwsUnsupportedError);
    },
  );

  test('equal titles keep native items ahead of legacy items', () {
    final native = orderSystemTrayItems([
      _item('n1', 'App'),
      _item('n2', 'App'),
    ]);
    final result = combineSystemTrayItems(native, [_item('l1', 'APP')]);
    expect(result.map((item) => item.id), ['n1', 'n2', 'l1']);
  });

  test('random merges match the previous combined sort for distinct keys', () {
    final random = Random(173);
    for (var sample = 0; sample < 1000; sample++) {
      final items = List.generate(
        random.nextInt(100),
        (id) => _item(
          '$id',
          '${id.isEven ? 'App' : 'tool'} $id',
          status: SystemTrayStatus.values[random.nextInt(3)],
        ),
      )..shuffle(random);
      final boundary = random.nextInt(items.length + 1);
      final native = orderSystemTrayItems(items.take(boundary));
      final legacy = items.skip(boundary).toList();
      final previous = [...native, ...legacy]..sort(compareSystemTrayItems);
      final merged = combineSystemTrayItems(native, legacy);
      expect(merged, previous, reason: 'sample $sample');
    }
  });
}

SystemTrayItem _item(
  String id,
  String title, {
  SystemTrayStatus status = SystemTrayStatus.active,
}) => SystemTrayItem(
  id: id,
  source: SystemTrayItemSource.statusNotifier,
  title: title,
  status: status,
  iconName: '',
  iconThemePath: '',
  iconPixmap: null,
  menuAvailable: false,
  primaryOpensMenu: false,
);
