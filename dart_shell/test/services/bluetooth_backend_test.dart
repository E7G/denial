import 'dart:async';
import 'dart:math';

import 'package:dbus/dbus.dart';
import 'package:denial_dart_shell/src/services/bluetooth_backend.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../support/bluetooth_fixtures.dart';
import '../support/legacy_bluetooth_snapshot.dart';

void main() {
  test('irrelevant event bursts perform no BlueZ snapshot reads', () {
    fakeAsync((async) {
      final client = _Client();
      final manager = _Manager();
      final service = BluetoothService(client: client, manager: manager);
      unawaited(service.start());
      async.flushMicrotasks();
      expect(manager.reads, 1);
      final irrelevant = bluetoothProperties(
        bluetoothDeviceInterface,
        changed: {
          'ManufacturerData': DBusDict(
            DBusSignature('q'),
            DBusSignature('v'),
            {},
          ),
        },
      );
      for (var i = 0; i < 1000; i++) {
        manager.events.add(irrelevant);
      }
      async.elapse(const Duration(milliseconds: 100));
      expect(manager.reads, 1);
      // Relevant bursts still coalesce into a single full snapshot read.
      for (var i = 0; i < 1000; i++) {
        manager.events.add(
          bluetoothProperties(
            bluetoothDeviceInterface,
            changed: {'RSSI': DBusInt16(-i)},
          ),
        );
      }
      async.elapse(const Duration(milliseconds: 100));
      expect(manager.reads, 2);
      unawaited(service.dispose());
      unawaited(manager.events.close());
      async.flushMicrotasks();
    });
  });

  test('all consumed properties and invalidations request a refresh', () {
    const properties = {
      bluetoothAdapterInterface: [
        'Alias',
        'Name',
        'Powered',
        'Discovering',
        'Pairable',
      ],
      bluetoothDeviceInterface: [
        'Adapter',
        'Address',
        'Alias',
        'Name',
        'Icon',
        'Connected',
        'Paired',
        'Bonded',
        'Trusted',
        'Blocked',
        'ServicesResolved',
        'RSSI',
      ],
    };
    for (final MapEntry(key: interface, value: names) in properties.entries) {
      for (final name in names) {
        expect(
          bluetoothSignalAffectsSnapshot(
            bluetoothProperties(
              interface,
              changed: {name: const DBusString('value')},
            ),
          ),
          isTrue,
          reason: '$interface.$name',
        );
        expect(
          bluetoothSignalAffectsSnapshot(
            bluetoothProperties(interface, invalidated: [name]),
          ),
          isTrue,
          reason: '$interface.$name invalidated',
        );
      }
    }
  });

  test('advertising-only changes and unrelated interfaces need no refresh', () {
    for (final interface in [
      bluetoothAdapterInterface,
      bluetoothDeviceInterface,
      'org.bluez.Battery1',
    ]) {
      final signal = bluetoothProperties(
        interface,
        changed: {
          'ManufacturerData': DBusDict(
            DBusSignature('q'),
            DBusSignature('v'),
            {},
          ),
          'ServiceData': DBusDict.stringVariant({}),
          'TxPower': const DBusInt16(10),
          'UUIDs': DBusArray.string(['unused']),
        },
        invalidated: ['Appearance', 'AdvertisingFlags'],
      );
      for (var i = 0; i < 1000; i++) {
        expect(bluetoothSignalAffectsSnapshot(signal), isFalse);
      }
    }
    expect(
      bluetoothSignalAffectsSnapshot(
        bluetoothProperties(
          'org.bluez.Battery1',
          changed: {'Name': const DBusString('not a device')},
        ),
      ),
      isFalse,
    );
    expect(
      bluetoothSignalAffectsSnapshot(
        bluetoothProperties(bluetoothDeviceInterface),
      ),
      isFalse,
    );
    expect(
      bluetoothSignalAffectsSnapshot(
        bluetoothProperties(
          bluetoothDeviceInterface,
          changed: {
            'TxPower': const DBusInt16(10),
            'RSSI': const DBusInt16(-50),
          },
        ),
      ),
      isTrue,
    );
  });

  test('adding or removing adapters and devices still refreshes topology', () {
    for (final added in [false, true]) {
      for (final interface in [
        bluetoothAdapterInterface,
        bluetoothDeviceInterface,
      ]) {
        expect(
          bluetoothSignalAffectsSnapshot(
            bluetoothInterfaces([
              'org.bluez.Battery1',
              interface,
            ], added: added),
          ),
          isTrue,
        );
      }
      expect(
        bluetoothSignalAffectsSnapshot(
          bluetoothInterfaces(['org.bluez.Battery1'], added: added),
        ),
        isFalse,
      );
      expect(
        bluetoothSignalAffectsSnapshot(bluetoothInterfaces([], added: added)),
        isFalse,
      );
    }
  });

  test('bounded selection preserves exact ties and replacement slots', () {
    final managed = bluetoothObjects(300, tied: true);
    // Later higher-priority devices must replace the first worst slot,
    // preserving the previous implementation's final sort input on ties.
    managed[DBusObjectPath(
      '/adapter/device280',
    )]![bluetoothDeviceInterface]!['Connected'] = const DBusBoolean(
      true,
    );
    managed[DBusObjectPath(
      '/adapter/device299',
    )]![bluetoothDeviceInterface]!['Paired'] = const DBusBoolean(
      true,
    );
    for (final cap in [-1, 0, 1, 2, 8, 128, 300, 400]) {
      expect(
        buildBluetoothSnapshot(managed, maxDevices: cap),
        legacyBluetoothSnapshot(managed, maxDevices: cap),
        reason: 'cap $cap',
      );
    }
  });

  test('snapshot owns its immutable device list', () {
    final managed = bluetoothObjects(8);
    final snapshot = buildBluetoothSnapshot(managed);
    managed.clear();
    expect(snapshot.devices, hasLength(8));
    expect(() => snapshot.devices.clear(), throwsUnsupportedError);
  });

  test(
    'powered adapter preference and selected-adapter filtering remain intact',
    () {
      final managed = bluetoothObjects(12);
      for (var i = 0; i < 8; i++) {
        managed[DBusObjectPath('/other$i')] = {
          bluetoothAdapterInterface: {
            'Powered': DBusBoolean(i.isOdd),
            'Name': DBusString('Adapter $i'),
          },
          bluetoothDeviceInterface: {
            'Adapter': DBusObjectPath('/other$i'),
            'Alias': const DBusString('Other device'),
          },
        };
      }
      for (final cap in [-1, 0, 1, 2, 4, 20]) {
        expect(
          buildBluetoothSnapshot(managed, maxAdapters: cap),
          legacyBluetoothSnapshot(managed, maxAdapters: cap),
        );
      }
    },
  );

  test('random device trees match the previous snapshot and ordering', () {
    final random = Random(91822);
    for (var iteration = 0; iteration < 1000; iteration++) {
      final managed = bluetoothObjects(random.nextInt(350), seed: iteration);
      for (final interfaces in managed.values) {
        final device = interfaces[bluetoothDeviceInterface];
        if (device == null) continue;
        if (random.nextInt(3) == 0) device.remove('RSSI');
        if (random.nextInt(5) == 0) {
          device['Alias'] = const DBusString('  日本語 alias  ');
        }
        if (random.nextInt(7) == 0) device['Name'] = const DBusUint32(2);
        if (random.nextInt(11) == 0) device['Bonded'] = const DBusBoolean(true);
        if (random.nextInt(13) == 0) {
          device['Adapter'] = DBusObjectPath('/elsewhere');
        }
      }
      final cap = random.nextInt(160);
      expect(
        buildBluetoothSnapshot(managed, maxDevices: cap),
        legacyBluetoothSnapshot(managed, maxDevices: cap),
        reason: 'iteration $iteration, cap $cap',
      );
    }
  });
}

// No bus connections, radio actions, or desktop events are involved.
class _Manager implements DBusRemoteObjectManager {
  final events = StreamController<DBusSignal>.broadcast(sync: true);
  int reads = 0;

  @override
  Stream<DBusSignal> get signals => events.stream;

  @override
  Future<BluetoothObjects> getManagedObjects() async {
    reads++;
    return bluetoothObjects(8);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements DBusClient {
  final owners = StreamController<DBusNameOwnerChangedEvent>.broadcast(
    sync: true,
  );

  @override
  Stream<DBusNameOwnerChangedEvent> get nameOwnerChanged => owners.stream;

  @override
  Future<String?> getNameOwner(String name) async => ':1.42';

  @override
  Future<void> registerObject(DBusObject object) async {}

  @override
  Future<void> unregisterObject(DBusObject object) async {}

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
    if (name != 'RegisterAgent' && name != 'RequestDefaultAgent') {
      throw StateError('Unexpected call $name');
    }
    return DBusMethodSuccessResponse();
  }

  @override
  Future<void> close() => owners.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
