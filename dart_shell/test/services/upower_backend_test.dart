import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:denial_dart_shell/src/services/upower_backend.dart';
import 'package:test/test.dart';

void main() {
  test(
    'battery enumeration and reads proceed while daemon properties wait',
    () async {
      final client = _Client({'/battery/one': _properties()});
      client.rootPending = Completer<DBusMethodSuccessResponse>();
      final service = UPowerService(systemBus: client);
      var completed = false;
      final result = service.readSnapshot().then((snapshot) {
        completed = true;
        return snapshot;
      });
      await _flush();
      expect(
        client.calls,
        contains(('/org/freedesktop/UPower', 'EnumerateDevices')),
      );
      expect(client.calls, contains(('/battery/one', 'GetAll')));
      expect(completed, isFalse);
      client.rootPending!.complete(_rootReply());
      final snapshot = await result;
      expect(snapshot.daemonVersion, '1.0');
      expect(snapshot.onBattery, isTrue);
      expect(snapshot.batteries.single.objectPath, '/battery/one');
      expect(snapshot.batteries.single.percentage, 75);
      await service.dispose();
    },
  );

  test(
    'disappearing and non-battery devices do not hide healthy batteries',
    () async {
      final client = _Client({
        '/battery/one': _properties(),
        '/battery/gone': null,
        '/line_power': {'Type': const DBusUint32(1)},
        '/battery/absent': {
          ..._properties(),
          'IsPresent': const DBusBoolean(false),
        },
        '/ups': {..._properties(), 'Type': const DBusUint32(3)},
      });
      final service = UPowerService(systemBus: client);
      final snapshot = await service.readSnapshot();
      expect(snapshot.batteries.map((battery) => battery.objectPath), [
        '/battery/one',
        '/ups',
      ]);
      expect(() => snapshot.batteries.clear(), throwsUnsupportedError);
      await service.dispose();
    },
  );

  test(
    'both independent read failures are handled by the returned future',
    () async {
      final client = _Client({})
        ..rootError = StateError('root failed')
        ..enumerationError = StateError('enumeration failed');
      final service = UPowerService(systemBus: client);
      await expectLater(
        service.readSnapshot(),
        throwsA(isA<ParallelWaitError>()),
      );
      client.rootError = null;
      client.enumerationError = null;
      expect((await service.readSnapshot()).batteries, isEmpty);
      await service.dispose();
    },
  );

  test('charge threshold operations retain their D-Bus arguments', () async {
    final client = _Client({});
    final service = UPowerService(systemBus: client);
    await service.setChargeThresholdEnabled('/battery/one', true);
    expect(client.calls.single, ('/battery/one', 'EnableChargeThreshold'));
    expect(client.lastValues, [const DBusBoolean(true)]);
    await service.dispose();
  });

  test(
    'snapshot inputs are copied and unchanged threshold updates reuse state',
    () {
      final battery = parseUPowerSystemBattery('/battery/one', _properties())!;
      final source = [battery];
      final snapshot = UPowerSnapshot(
        daemonVersion: '1',
        onBattery: true,
        batteries: source,
      );
      source.clear();
      expect(snapshot.batteries.single, same(battery));
      expect(battery.withChargeThresholdEnabled(false), same(battery));
      expect(
        snapshot.withChargeThresholdEnabled('/missing', true),
        same(snapshot),
      );
      expect(
        snapshot.withChargeThresholdEnabled('/battery/one', false),
        same(snapshot),
      );
    },
  );

  test('threshold updates copy once and preserve other battery instances', () {
    final first = parseUPowerSystemBattery('/battery/one', _properties())!;
    final other = parseUPowerSystemBattery('/battery/two', _properties())!;
    final snapshot = UPowerSnapshot(
      daemonVersion: '1',
      onBattery: true,
      batteries: [first, other, first],
    );
    final updated = snapshot.withChargeThresholdEnabled('/battery/one', true);
    expect(updated.batteries.first.chargeThresholdEnabled, isTrue);
    expect(updated.batteries.last.chargeThresholdEnabled, isTrue);
    expect(updated.batteries[1], same(other));
    expect(snapshot.batteries.first.chargeThresholdEnabled, isFalse);
    expect(updated.daemonVersion, snapshot.daemonVersion);
    expect(updated.onBattery, snapshot.onBattery);
    expect(() => updated.batteries.clear(), throwsUnsupportedError);
    expect(
      updated.withChargeThresholdEnabled('/battery/one', true),
      same(updated),
    );
  });

  test('display names preserve trimming, deduplication, and fallback', () {
    for (final (vendor, model, expected) in [
      (' Vendor ', ' Model ', 'Vendor Model'),
      ('Vendor', ' Vendor ', 'Vendor'),
      (' Vendor ', '', 'Vendor'),
      ('', ' Model ', 'Model'),
      ('  ', ' ', 'BAT0'),
    ]) {
      final battery = parseUPowerSystemBattery('/battery', {
        ..._properties(),
        'Vendor': DBusString(vendor),
        'Model': DBusString(model),
        'NativePath': const DBusString(' BAT0 '),
      })!;
      expect(battery.displayName, expected);
    }
  });

  test('parsing rejects unavailable or invalid measurements', () {
    final battery = parseUPowerSystemBattery('/battery', {
      ..._properties(),
      'Percentage': const DBusDouble(double.nan),
      'Energy': const DBusDouble(-1),
      'Voltage': const DBusDouble(double.infinity),
      'Temperature': const DBusString('wrong type'),
      'ChargeCycles': const DBusInt32(-1),
      'ChargeStartThreshold': const DBusUint32(101),
      'TimeToEmpty': const DBusInt64(0),
      'TimeToFull': const DBusInt64(12),
      'State': const DBusUint32(1),
    })!;
    expect(battery.percentage, isNull);
    expect(battery.energy, isNull);
    expect(battery.voltage, isNull);
    expect(battery.temperature, isNull);
    expect(battery.chargeCycles, isNull);
    expect(battery.chargeStartThreshold, isNull);
    expect(battery.timeToEmpty, isNull);
    expect(battery.timeToFull, const Duration(seconds: 12));
    expect(battery.state, UPowerBatteryState.charging);
  });
}

Map<String, DBusValue> _properties() => {
  'Type': const DBusUint32(2),
  'Percentage': const DBusDouble(75),
  'ChargeThresholdSupported': const DBusBoolean(true),
  'ChargeThresholdEnabled': const DBusBoolean(false),
};

DBusMethodSuccessResponse _rootReply() => DBusMethodSuccessResponse([
  DBusDict.stringVariant({
    'DaemonVersion': const DBusString('1.0'),
    'OnBattery': const DBusBoolean(true),
  }),
]);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _Client implements DBusClient {
  _Client(this.devices);
  final Map<String, Map<String, DBusValue>?> devices;
  final calls = <(String, String)>[];
  Iterable<DBusValue> lastValues = [];
  Completer<DBusMethodSuccessResponse>? rootPending;
  Object? rootError;
  Object? enumerationError;

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
    calls.add((path.value, name));
    lastValues = values;
    if (name == 'EnumerateDevices') {
      if (enumerationError case final error?) throw error;
      return DBusMethodSuccessResponse([
        DBusArray.objectPath(devices.keys.map(DBusObjectPath.new)),
      ]);
    }
    if (name == 'EnableChargeThreshold') return DBusMethodSuccessResponse([]);
    if (name != 'GetAll') throw StateError('Unexpected method $name');
    if (path.value == '/org/freedesktop/UPower') {
      if (rootError case final error?) throw error;
      return rootPending == null ? _rootReply() : rootPending!.future;
    }
    final properties = devices[path.value];
    if (properties == null) throw StateError('Device disappeared');
    return DBusMethodSuccessResponse([DBusDict.stringVariant(properties)]);
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
