import 'dart:collection';
import 'dart:math';

import 'package:dbus/dbus.dart';
import 'package:denial_dart_shell/src/core/bounded_text.dart';
import 'package:denial_dart_shell/src/models/logind.dart';
import 'package:denial_dart_shell/src/services/logind_protocol.dart';
import 'package:test/test.dart';

import '../support/legacy_logind_protocol.dart';

void main() {
  test('capability responses retain their existing meaning', () {
    for (final value in ['yes', 'no', 'challenge', 'na', '', 'unknown']) {
      expect(parseLogindCapability(value), legacyLogindCapability(value));
    }
  });

  test('inhibitor class limits count nonempty tokens before deduplication', () {
    final classes = ':  :${List.filled(16, 'sleep').join(':')}:shutdown';
    final parsed = parseLogindInhibitors(_array([_row(classes)]));
    expect(parsed.single.what, {'sleep'});
    expect(parsed.single.blocks(LogindAction.suspend), isTrue);
    expect(parsed.single.blocks(LogindAction.powerOff), isFalse);
    expect(() => parsed.single.what.add('shutdown'), throwsUnsupportedError);
    expect(() => parsed.clear(), throwsUnsupportedError);
  });

  test('the parser stops visiting rows once the accepted limit is reached', () {
    final rows = _ObservedList([
      const DBusString('malformed'),
      _row('sleep'),
      _row('shutdown'),
      for (var i = 0; i < 1000; i++) _row('idle'),
    ]);
    expect(
      parseLogindInhibitors(_ObservedArray(rows), maximum: 2),
      hasLength(2),
    );
    expect(rows.reads, 3);
  });

  test('malformed and ignored rows do not consume the accepted limit', () {
    final value = _array([
      const DBusString('not a row'),
      DBusStruct([const DBusString('too short')]),
      _row('sleep', mode: 'unsupported'),
      _row(': :'),
      DBusStruct([
        const DBusString('sleep'),
        const DBusString('who'),
        const DBusString('why'),
        const DBusString('block'),
        const DBusString('bad uid'),
        const DBusUint32(3),
      ]),
      _row('sleep'),
      _row('shutdown', mode: 'delay'),
    ]);
    expect(
      parseLogindInhibitors(value, maximum: 2),
      legacyLogindInhibitors(value, maximum: 2),
    );
    expect(parseLogindInhibitors(value, maximum: 0), isEmpty);
    expect(parseLogindInhibitors(value, maximum: -1), isEmpty);
    expect(parseLogindInhibitors(const DBusString('not an array')), isEmpty);
  });

  test('random inhibitor lists preserve normalized values and ordering', () {
    final random = Random(22131);
    for (var iteration = 0; iteration < 1000; iteration++) {
      final count = random.nextInt(80);
      final rows = <DBusValue>[
        for (var row = 0; row < count; row++)
          _row(
            List.generate(
              random.nextInt(25),
              (_) =>
                  ['sleep', 'shutdown', '', ' \n ', 'idle'][random.nextInt(5)],
            ).join(':'),
            mode: ['block', 'delay', 'invalid'][random.nextInt(3)],
            who: _randomText(random),
            why: _randomText(random),
          ),
      ];
      final value = _array(rows);
      final maximum = random.nextInt(70);
      expect(
        parseLogindInhibitors(value, maximum: maximum),
        legacyLogindInhibitors(value, maximum: maximum),
        reason: 'iteration $iteration',
      );
    }
  });

  test('shared text normalization preserves Unicode and boundary behavior', () {
    final random = Random(727);
    for (var i = 0; i < 10000; i++) {
      final value = _randomText(random);
      final maximum = random.nextInt(80);
      expect(
        normalizeBoundedText(value, maximum),
        legacyBoundedText(value, maximum),
        reason: 'iteration $i',
      );
    }
    expect(normalizeBoundedText('  A\n😀B  ', 3), 'A 😀');
    expect(() => normalizeBoundedText('text', -1), throwsRangeError);
  });

  test(
    'detached snapshot models preserve collection equality and ownership',
    () {
      final first = parseLogindInhibitors(_array([_row('sleep:shutdown')]));
      final second = parseLogindInhibitors(_array([_row('shutdown:sleep')]));
      expect(first.single, second.single);
      expect(first.single.hashCode, second.single.hashCode);
      final capabilities = {LogindAction.suspend: LogindCapability.available};
      final inhibitors = first.toList();
      final snapshot = LogindSnapshot(
        serviceAvailable: true,
        capabilities: capabilities,
        inhibitors: inhibitors,
      );
      final equal = LogindSnapshot(
        serviceAvailable: true,
        capabilities: capabilities,
        inhibitors: second,
      );
      capabilities.clear();
      inhibitors.clear();
      expect(snapshot, equal);
      expect(snapshot.hashCode, equal.hashCode);
      expect(
        snapshot.capabilityFor(LogindAction.suspend),
        LogindCapability.available,
      );
      expect(snapshot.blockersFor(LogindAction.suspend), first);
      expect(snapshot.delaysFor(LogindAction.suspend), isEmpty);
      expect(() => snapshot.capabilities.clear(), throwsUnsupportedError);
      expect(() => snapshot.inhibitors.clear(), throwsUnsupportedError);
    },
  );
}

DBusArray _array(List<DBusValue> rows) =>
    DBusArray.unchecked(DBusSignature('(ssssuu)'), rows);

DBusStruct _row(
  String what, {
  String mode = 'block',
  String who = 'Application',
  String why = 'Work in progress',
}) => DBusStruct([
  DBusString(what),
  DBusString(who),
  DBusString(why),
  DBusString(mode),
  const DBusUint32(1000),
  const DBusUint32(1234),
]);

String _randomText(Random random) => String.fromCharCodes([
  for (var i = 0, length = random.nextInt(300); i < length; i++)
    switch (random.nextInt(5)) {
      0 => random.nextInt(32),
      1 => 0x1f600 + random.nextInt(30),
      2 => 0xd800 + random.nextInt(0x800),
      _ => 32 + random.nextInt(100),
    },
]);

class _ObservedArray implements DBusArray {
  _ObservedArray(this.children);
  @override
  final List<DBusValue> children;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ObservedList extends ListBase<DBusValue> {
  _ObservedList(this.values);
  final List<DBusValue> values;
  int reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  DBusValue operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, DBusValue value) =>
      throw UnsupportedError('read only');
}
