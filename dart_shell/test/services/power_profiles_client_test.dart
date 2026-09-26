import 'dart:collection';

import 'package:dbus/dbus.dart';
import 'package:denial_dart_shell/src/models/power_profile.dart';
import 'package:denial_dart_shell/src/services/power_profiles_client.dart';
import 'package:test/test.dart';

const _modern = 'org.freedesktop.UPower.PowerProfiles';
const _legacy = 'net.hadess.PowerProfiles';

void main() {
  test('successful discovery reads the property only once', () async {
    final bus = _Bus({
      _modern: [const DBusString('balanced')],
    });
    final client = PowerProfilesClient(bus);
    expect(await client.readActiveProfile(), PowerProfile.balanced);
    expect(bus.reads, [_modern]);
    expect(await client.resolve(), isNotNull);
    expect(bus.reads, [_modern]);
  });

  test('legacy discovery does not re-read the successful fallback', () async {
    final bus = _Bus({
      _modern: [StateError('absent')],
      _legacy: [const DBusString('power-saver')],
    });
    final client = PowerProfilesClient(bus);
    expect(await client.readActiveProfile(), PowerProfile.powerSave);
    expect(bus.reads, [_modern, _legacy]);
  });

  test(
    'cached endpoints get fresh values without probing alternatives',
    () async {
      final bus = _Bus({
        _modern: [
          const DBusString('balanced'),
          const DBusString('performance'),
        ],
      });
      final client = PowerProfilesClient(bus);
      expect(await client.readActiveProfile(), PowerProfile.balanced);
      expect(await client.readActiveProfile(), PowerProfile.performance);
      expect(bus.reads, [_modern, _modern]);
    },
  );

  test(
    'a failed cached endpoint is not retried during the same refresh',
    () async {
      final bus = _Bus({
        _modern: [const DBusString('balanced'), StateError('gone')],
        _legacy: [
          const DBusString('performance'),
          const DBusString('balanced'),
        ],
      });
      final client = PowerProfilesClient(bus);
      expect(await client.readActiveProfile(), PowerProfile.balanced);
      expect(await client.readActiveProfile(), PowerProfile.performance);
      expect(bus.reads, [_modern, _modern, _legacy]);
      expect(await client.readActiveProfile(), PowerProfile.balanced);
      expect(bus.reads.last, _legacy);
    },
  );

  test('unavailable endpoints remain eligible for a later refresh', () async {
    final bus = _Bus({
      _modern: [
        const DBusString('balanced'),
        StateError('gone'),
        const DBusString('performance'),
      ],
      _legacy: [StateError('absent')],
    });
    final client = PowerProfilesClient(bus);
    await client.readActiveProfile();
    expect(await client.readActiveProfile(), isNull);
    expect(await client.readActiveProfile(), PowerProfile.performance);
    expect(bus.reads, [_modern, _modern, _legacy, _modern]);
  });

  test('invalid values cannot select an endpoint', () async {
    final bus = _Bus({
      _modern: [const DBusBoolean(true), const DBusString('unknown')],
      _legacy: [const DBusString('unknown'), const DBusString(' balanced ')],
    });
    final client = PowerProfilesClient(bus);
    expect(await client.resolve(), isNull);
    expect(await client.readActiveProfile(), PowerProfile.balanced);
    expect(bus.reads, [_modern, _legacy, _modern, _legacy]);
  });

  test('writes use the selected endpoint and retain write failures', () async {
    final bus = _Bus({
      _modern: [StateError('absent')],
      _legacy: [const DBusString('balanced')],
    });
    final client = PowerProfilesClient(bus);
    final endpoint = (await client.resolve())!;
    await endpoint.setActiveProfile('power-saver');
    expect(bus.writes.single, (
      _legacy,
      '/net/hadess/PowerProfiles',
      'power-saver',
    ));
    expect(bus.reads, [_modern, _legacy]);
    final error = StateError('write failed');
    bus.writeError = error;
    await expectLater(
      endpoint.setActiveProfile('performance'),
      throwsA(same(error)),
    );
    expect(bus.reads, [_modern, _legacy]);
  });

  test('normalization and cycling retain canonical profile names', () {
    for (final name in [
      'power-save',
      'power-saver',
      'powersave',
      'power_save',
    ]) {
      expect(PowerProfile.normalize(' $name '), PowerProfile.powerSave);
    }
    expect(PowerProfile.normalize(null), isNull);
    expect(PowerProfile.normalize('invalid'), isNull);
    expect(PowerProfile.next(PowerProfile.powerSave), PowerProfile.balanced);
    expect(PowerProfile.next(PowerProfile.balanced), PowerProfile.performance);
    expect(PowerProfile.next(PowerProfile.performance), PowerProfile.powerSave);
  });
}

// In-memory replies; no system-bus access or actual power-profile changes.
class _Bus implements DBusClient {
  _Bus(Map<String, List<Object>> replies)
    : replies = {
        for (final entry in replies.entries) entry.key: Queue.of(entry.value),
      };
  final Map<String, Queue<Object>> replies;
  final reads = <String>[];
  final writes = <(String, String, String)>[];
  Object? writeError;

  @override
  Future<DBusMethodSuccessResponse> callMethod({
    String? destination,
    required DBusObjectPath path,
    String? interface,
    required String name,
    Iterable<DBusValue> values = const [],
    DBusSignature? replySignature,
    bool noReplyExpected = false,
    bool noAutoStart = false,
    bool allowInteractiveAuthorization = false,
  }) async {
    expect(interface, 'org.freedesktop.DBus.Properties');
    expect(values.first.asString(), destination);
    expect(values.elementAt(1).asString(), 'ActiveProfile');
    if (name == 'Get') {
      reads.add(destination!);
      final queue = replies[destination];
      if (queue == null || queue.isEmpty) {
        throw StateError('Unexpected read of $destination');
      }
      final value = queue.removeFirst();
      if (value is! DBusValue) throw value;
      return DBusMethodSuccessResponse([DBusVariant(value)]);
    }
    if (name == 'Set') {
      writes.add((
        destination!,
        path.value,
        values.last.asVariant().asString(),
      ));
      if (writeError case final error?) throw error;
      return DBusMethodSuccessResponse([]);
    }
    throw StateError('Unexpected method $name');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
