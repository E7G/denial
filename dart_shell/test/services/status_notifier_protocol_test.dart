import 'dart:isolate';
import 'dart:typed_data';

import 'package:denial_dart_shell/src/models/system_tray_item.dart';
import 'package:denial_dart_shell/src/services/status_notifier_protocol.dart';
import 'package:test/test.dart';

void main() {
  test(
    'full snapshots round-trip every item field and own immutable lists',
    () {
      final items = [_item('a', icon: _icon(1)), _item('b')];
      final decoded = StatusNotifierProtocol.decodeItems(
        StatusNotifierProtocol.encodeItems(items),
      );
      expect(decoded, items);
      expect(() => decoded.clear(), throwsUnsupportedError);
      expect(
        identical(decoded.first.iconPixmap!.rgba, items.first.iconPixmap!.rgba),
        isFalse,
      );
      expect(
        decoded.first.iconPixmap.hashCode,
        items.first.iconPixmap.hashCode,
      );
    },
  );

  test('unchanged items and icons are retained across metadata updates', () {
    final encoder = StatusNotifierUpdateEncoder();
    final decoder = StatusNotifierUpdateDecoder();
    final icon = _icon(1);
    final original = [_item('a', icon: icon), _item('b', icon: _icon(2))];
    final full = encoder.encode(original);
    expect(_transfers(full), 2);
    final before = decoder.decode(full);
    final renamed = [_item('a', icon: icon, title: 'New title'), original.last];
    final delta = encoder.encode(renamed);
    expect(((delta as List)[2] as List), hasLength(1));
    expect(_transfers(delta), 0);
    final after = decoder.decode(delta);
    expect(after, renamed);
    expect(identical(after.last, before.last), isTrue);
    expect(identical(after.first.iconPixmap, before.first.iconPixmap), isTrue);
    expect(before.first.title, 'Title a');
    expect(() => after.removeLast(), throwsUnsupportedError);
  });

  test('equal pixels in a new object do not get transferred again', () {
    final encoder = StatusNotifierUpdateEncoder();
    final decoder = StatusNotifierUpdateDecoder();
    final before = decoder.decode(encoder.encode([_item('a', icon: _icon(3))]));
    final frame = encoder.encode([
      _item('a', icon: _icon(3), title: 'Changed'),
    ]);
    expect(_transfers(frame), 0);
    expect(
      identical(
        decoder.decode(frame).single.iconPixmap,
        before.single.iconPixmap,
      ),
      isTrue,
    );
  });

  test('icon changes transfer only the changed buffer and null removes it', () {
    final encoder = StatusNotifierUpdateEncoder();
    final decoder = StatusNotifierUpdateDecoder();
    final unchanged = _item('b', icon: _icon(2));
    decoder.decode(encoder.encode([_item('a', icon: _icon(1)), unchanged]));
    final next = [_item('a', icon: _icon(9)), unchanged];
    final frame = encoder.encode(next);
    expect(_transfers(frame), 1);
    expect(decoder.decode(frame), next);
    final removed = encoder.encode([_item('a'), unchanged]);
    expect(_transfers(removed), 0);
    expect(decoder.decode(removed).first.iconPixmap, isNull);
  });

  test(
    'reordering, removing and re-adding items retains the right identities',
    () {
      final encoder = StatusNotifierUpdateEncoder();
      final decoder = StatusNotifierUpdateDecoder();
      final a = _item('a', icon: _icon(1));
      final b = _item('b', icon: _icon(2));
      final first = decoder.decode(encoder.encode([a, b]));
      final reorder = encoder.encode([b, a]);
      expect((reorder as List)[2], isEmpty);
      final second = decoder.decode(reorder);
      expect(identical(second.first, first.last), isTrue);
      expect(identical(second.last, first.first), isTrue);
      decoder.decode(encoder.encode([b]));
      final readded = encoder.encode([a, b]);
      expect(_transfers(readded), 1);
      expect(decoder.decode(readded), [a, b]);
      expect(decoder.decode(encoder.encode([])), isEmpty);
    },
  );

  test(
    'a self-contained startup response does not seed the event delta cache',
    () {
      final encoder = StatusNotifierUpdateEncoder();
      final decoder = StatusNotifierUpdateDecoder();
      final items = [_item('a', icon: _icon(5))];
      final initial = StatusNotifierProtocol.encodeItems(items);
      final event = encoder.encode(items);
      expect(decoder.decode(event), items);
      expect(StatusNotifierProtocol.decodeItems(initial), items);
      expect(
        decoder
            .decode(
              encoder.encode([_item('a', title: 'Later', icon: _icon(5))]),
            )
            .single
            .title,
        'Later',
      );
    },
  );

  test(
    'malformed deltas require a reset and never mutate published snapshots',
    () {
      final encoder = StatusNotifierUpdateEncoder();
      final decoder = StatusNotifierUpdateDecoder();
      final items = [_item('a', icon: _icon(5))];
      final before = decoder.decode(encoder.encode(items));
      expect(
        () => decoder.decode([
          false,
          ['a'],
          [
            ['a'],
          ],
        ]),
        throwsFormatException,
      );
      expect(
        () => decoder.decode(encoder.encode(items)),
        throwsFormatException,
      );
      expect(before, items);
      final reset = encoder.encode(items, reset: true);
      expect(_transfers(reset), 1);
      expect(decoder.decode(reset), items);
      expect(decoder.decode(encoder.encode(items)), items);
    },
  );

  test(
    'unknown references, duplicate IDs and orphaned updates are rejected',
    () {
      for (final packet in <Object?>[
        null,
        [false, [], []],
        [
          true,
          ['missing'],
          [],
        ],
        [
          true,
          ['a', 'a'],
          [_row('a')],
        ],
        [
          true,
          ['a'],
          [_row('a'), _row('a')],
        ],
        [
          true,
          [],
          [_row('a')],
        ],
        [
          true,
          [7],
          [],
        ],
        [
          true,
          ['a'],
          [_row('a', pixmap: true)],
        ],
      ]) {
        expect(
          () => StatusNotifierUpdateDecoder().decode(packet),
          throwsFormatException,
        );
      }
      final encoder = StatusNotifierUpdateEncoder();
      expect(
        () => encoder.encode([_item('a'), _item('a')]),
        throwsFormatException,
      );
      expect(
        StatusNotifierUpdateDecoder().decode(encoder.encode([_item('a')])),
        [_item('a')],
      );
    },
  );

  test('invalid item fields, enum values and pixmap sizes are rejected', () {
    for (final (index, value) in [
      (0, 1),
      (1, -1),
      (3, 99),
      (7, 'true'),
      (9, null),
    ]) {
      final row = _row('a')..[index] = value;
      expect(
        () => StatusNotifierProtocol.decodeItems([row]),
        throwsFormatException,
      );
    }
    for (final (width, height, length) in [(0, 1, 4), (1, -1, 4), (2, 2, 4)]) {
      final row = _row(
        'a',
        pixmap: [
          width,
          height,
          TransferableTypedData.fromList([Uint8List(length)]),
        ],
      );
      expect(
        () => StatusNotifierProtocol.decodeItems([row]),
        throwsFormatException,
      );
    }
  });

  test('menu trees round-trip flags and immutable children', () {
    final leaf = _menu(2, children: const []);
    final menu = [
      _menu(1, children: [leaf]),
    ];
    final result = StatusNotifierProtocol.decodeMenu(
      StatusNotifierProtocol.encodeMenu(menu),
    )!;
    final root = result.single;
    expect(
      (
        root.id,
        root.label,
        root.enabled,
        root.visible,
        root.separator,
        root.toggleType,
        root.toggleState,
        root.destructive,
        root.hasSubmenu,
      ),
      (
        1,
        'Entry 1',
        true,
        true,
        false,
        SystemTrayMenuToggleType.checkmark,
        1,
        false,
        true,
      ),
    );
    expect(root.children.single.id, 2);
    expect(() => result.clear(), throwsUnsupportedError);
    expect(() => root.children.clear(), throwsUnsupportedError);
    expect(StatusNotifierProtocol.decodeMenu(null), isNull);
  });

  test('metadata-only snapshots transition to and from pixel deltas', () {
    final encoder = StatusNotifierUpdateEncoder();
    final decoder = StatusNotifierUpdateDecoder();
    for (final icon in [null, _icon(1), null, _icon(2)]) {
      final items = [_item('a', icon: icon)];
      final result = decoder.decode(encoder.encode(items));
      expect(result, items);
      expect(() => result.clear(), throwsUnsupportedError);
    }
  });

  test('delta frames cross a real isolate in order', () async {
    final replies = ReceivePort();
    try {
      await Isolate.spawn(_sendUpdates, replies.sendPort);
      final frames = await replies
          .take(4)
          .toList()
          .timeout(const Duration(seconds: 5));
      final decoder = StatusNotifierUpdateDecoder();
      final first = decoder.decode(frames[0]);
      final second = decoder.decode(frames[1]);
      final third = decoder.decode(frames[2]);
      expect(first.single.title, 'Title a');
      expect(second.single.title, 'Updated');
      expect(
        identical(first.single.iconPixmap, second.single.iconPixmap),
        isTrue,
      );
      expect(third.single.iconPixmap!.rgba.first, 9);
      final fourth = decoder.decode(frames[3]);
      expect(fourth.single.iconPixmap, isNull);
      expect(() => fourth.clear(), throwsUnsupportedError);
    } finally {
      replies.close();
    }
  });
}

void _sendUpdates(SendPort port) {
  final encoder = StatusNotifierUpdateEncoder();
  port.send(encoder.encode([_item('a', icon: _icon(1))]));
  port.send(encoder.encode([_item('a', icon: _icon(1), title: 'Updated')]));
  port.send(encoder.encode([_item('a', icon: _icon(9), title: 'Updated')]));
  port.send(encoder.encode([_item('a')]));
}

int _transfers(Object? value) => value is TransferableTypedData
    ? 1
    : value is List
    ? value.fold<int>(0, (n, v) => n + _transfers(v))
    : 0;

SystemTrayIconPixmap _icon(int value) => SystemTrayIconPixmap(
  width: 2,
  height: 2,
  rgba: Uint8List.fromList(List.filled(16, value)),
);
SystemTrayItem _item(String id, {String? title, SystemTrayIconPixmap? icon}) =>
    SystemTrayItem(
      id: id,
      source: SystemTrayItemSource.statusNotifier,
      title: title ?? 'Title $id',
      status: SystemTrayStatus.active,
      iconName: 'icon-$id',
      iconThemePath: '/icons',
      iconPixmap: icon,
      menuAvailable: true,
      primaryOpensMenu: false,
      menuPath: '/Menu',
    );
List<Object?> _row(String id, {Object? pixmap}) => [
  id,
  0,
  'Title $id',
  1,
  'icon',
  '',
  pixmap,
  true,
  false,
  '/Menu',
];
SystemTrayMenuEntry _menu(
  int id, {
  required List<SystemTrayMenuEntry> children,
}) => SystemTrayMenuEntry(
  id: id,
  label: 'Entry $id',
  enabled: true,
  visible: true,
  separator: false,
  toggleType: SystemTrayMenuToggleType.checkmark,
  toggleState: 1,
  destructive: false,
  children: children,
  hasSubmenu: children.isNotEmpty,
);
