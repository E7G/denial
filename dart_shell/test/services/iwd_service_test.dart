import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:denial_dart_shell/src/services/iwd_service.dart';
import 'package:denial_dart_shell/src/services/iwd_signal_protocol.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

const _station = 'net.connman.iwd.Station';
const _device = 'net.connman.iwd.Device';
const _adapter = 'net.connman.iwd.Adapter';
const _network = 'net.connman.iwd.Network';
typedef _Objects = Map<DBusObjectPath, Map<String, Map<String, DBusValue>>>;

void main() {
  test(
    'station reads run in batches of four and retain priority order',
    () async {
      final manager = _Manager(5, sharedName: true);
      final client = _Client();
      final gates = {for (var i = 0; i < 5; i++) _path(i): Completer<void>()};
      client.beforeNetworkRead = (path) => gates[path]!.future;
      final service = IwdService(client: client, manager: manager);
      try {
        final refresh = service.refresh();
        await _flush();
        expect(client.networkReads, [_path(0), _path(1), _path(2), _path(3)]);
        gates[_path(3)]!.complete();
        gates[_path(2)]!.complete();
        gates[_path(1)]!.complete();
        await _flush();
        expect(client.networkReads, hasLength(4));
        gates[_path(0)]!.complete();
        await _flush();
        expect(client.networkReads, hasLength(5));
        gates[_path(4)]!.complete();
        await refresh;
        expect(service.currentSnapshot.networks.single.devicePath, _path(0));
        expect(client.maximumConcurrent, 4);
      } finally {
        for (final gate in gates.values) {
          if (!gate.isCompleted) gate.complete();
        }
        await service.dispose();
        await manager.events.close();
      }
    },
  );

  test(
    'powered-down stations are skipped and failed stations do not hide peers',
    () async {
      final manager = _Manager(4);
      manager.objects[DBusObjectPath(_path(1))]![_device]!['Powered'] =
          const DBusBoolean(false);
      final client = _Client()
        ..beforeNetworkRead = (path) async {
          if (path == _path(2)) throw StateError('station disappeared');
        };
      final service = IwdService(client: client, manager: manager);
      try {
        await service.refresh();
        expect(client.networkReads, [_path(0), _path(2), _path(3)]);
        expect(
          service.currentSnapshot.networks.map((network) => network.devicePath),
          [_path(0), _path(3)],
        );
      } finally {
        await service.dispose();
        await manager.events.close();
      }
    },
  );

  test('disposal during one batch prevents remaining station reads', () async {
    final manager = _Manager(8);
    final gate = Completer<void>();
    final client = _Client()..beforeNetworkRead = (_) => gate.future;
    final service = IwdService(client: client, manager: manager);
    final refresh = service.refresh();
    await _flush();
    expect(client.networkReads, hasLength(4));
    await service.dispose();
    gate.complete();
    await refresh;
    expect(client.networkReads, hasLength(4));
    expect(service.currentSnapshot.serviceAvailable, isFalse);
    await manager.events.close();
  });

  test('irrelevant signal bursts cause no reads and scan completion still refreshes', () {
    fakeAsync((async) {
      final manager = _Manager(1);
      final client = _Client();
      final service = IwdService(
        client: client,
        manager: manager,
        networkdSignals: const Stream.empty(),
      );
      unawaited(service.start());
      async.flushMicrotasks();
      expect(manager.reads, 1);
      for (var i = 0; i < 1000; i++) {
        manager.events.add(
          _properties('net.connman.iwd.StationDiagnostic', {
            'RSSI': const DBusInt16(-50),
          }),
        );
        manager.events.add(
          _properties(_adapter, {'Model': const DBusString('model')}),
        );
      }
      async.elapse(const Duration(milliseconds: 100));
      expect(manager.reads, 1);
      // The fake Scan method only records an in-memory request.
      unawaited(service.requestScan());
      async.flushMicrotasks();
      manager.events.add(
        _properties(_station, {
          'Scanning': const DBusBoolean(false),
        }, path: _path(0)),
      );
      async.elapse(const Duration(milliseconds: 100));
      expect(manager.reads, 2);
      expect(service.currentSnapshot.lastScan, 0);
      expect(client.scans, 1);
      unawaited(service.dispose());
      unawaited(manager.events.close());
      async.flushMicrotasks();
    });
  });

  test(
    'all consumed fields and network-ranking changes retain invalidations',
    () {
      for (final (interface, fields) in [
        (_adapter, ['Powered', 'SupportedModes']),
        (_device, ['Name', 'Mode', 'Powered']),
        (
          _station,
          ['Scanning', 'State', 'ConnectedNetwork', 'ConnectedAccessPoint'],
        ),
        (
          _network,
          [
            'Name',
            'Type',
            'Device',
            'KnownNetwork',
            'Connected',
            'ExtendedServiceSet',
          ],
        ),
        (
          'net.connman.iwd.KnownNetwork',
          ['Name', 'Type', 'LastConnectedTime', 'AutoConnect', 'Hidden'],
        ),
        ('net.connman.iwd.BasicServiceSet', ['SignalStrength']),
      ]) {
        for (final field in fields) {
          expect(
            iwdSignalAffectsSnapshot(
              _properties(interface, {field: const DBusString('value')}),
            ),
            isTrue,
            reason: '$interface.$field',
          );
          expect(
            iwdSignalAffectsSnapshot(
              _properties(interface, {}, invalidated: [field]),
            ),
            isTrue,
          );
        }
      }
      expect(iwdSignalAffectsSnapshot(_properties(_station, {})), isFalse);
      expect(
        iwdSignalAffectsSnapshot(
          _properties(_device, {}, invalidated: ['Address']),
        ),
        isFalse,
      );
    },
  );

  test(
    'topology changes use interface keys without losing relevant objects',
    () {
      for (final added in [false, true]) {
        for (final interface in [
          _adapter,
          _device,
          _station,
          _network,
          'net.connman.iwd.KnownNetwork',
          'net.connman.iwd.BasicServiceSet',
        ]) {
          expect(
            iwdSignalAffectsSnapshot(_interfaces([interface], added)),
            isTrue,
          );
        }
        expect(
          iwdSignalAffectsSnapshot(
            _interfaces(['net.connman.iwd.StationDiagnostic'], added),
          ),
          isFalse,
        );
      }
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);
String _path(int index) => '/device/d${index.toString().padLeft(2, '0')}';

DBusPropertiesChangedSignal _properties(
  String interface,
  Map<String, DBusValue> changed, {
  String path = '/device/d00',
  List<String> invalidated = const [],
}) => DBusPropertiesChangedSignal(
  DBusSignal(
    sender: ':1.42',
    path: DBusObjectPath(path),
    interface: 'org.freedesktop.DBus.Properties',
    name: 'PropertiesChanged',
    values: [
      DBusString(interface),
      DBusDict.stringVariant(changed),
      DBusArray.string(invalidated),
    ],
  ),
);

DBusSignal _interfaces(List<String> interfaces, bool added) {
  final signal = DBusSignal(
    sender: ':1.42',
    path: DBusObjectPath.root,
    interface: 'org.freedesktop.DBus.ObjectManager',
    name: added ? 'InterfacesAdded' : 'InterfacesRemoved',
    values: [
      DBusObjectPath('/device/d00'),
      if (added)
        DBusDict(DBusSignature('s'), DBusSignature('a{sv}'), {
          for (final interface in interfaces)
            DBusString(interface): DBusDict.stringVariant({}),
        })
      else
        DBusArray.string(interfaces),
    ],
  );
  return added
      ? DBusObjectManagerInterfacesAddedSignal(signal)
      : DBusObjectManagerInterfacesRemovedSignal(signal);
}

// These dependencies never connect to a bus or change a real radio.
class _Manager implements DBusRemoteObjectManager {
  _Manager(int count, {bool sharedName = false})
    : objects = {
        DBusObjectPath('/adapter'): {
          _adapter: {
            'Powered': const DBusBoolean(true),
            'SupportedModes': DBusArray.string(['station']),
          },
        },
        for (var i = 0; i < count; i++)
          DBusObjectPath(_path(i)): {
            _device: {
              'Name': DBusString('wlan$i'),
              'Mode': const DBusString('station'),
              'Powered': const DBusBoolean(true),
            },
            _station: {'State': const DBusString('disconnected')},
          },
        for (var i = 0; i < count; i++)
          DBusObjectPath('/network/${_path(i).split('/').last}'): {
            _network: {
              'Name': DBusString(sharedName ? 'Shared' : 'Network $i'),
              'Type': const DBusString('open'),
              'Device': DBusObjectPath(_path(i)),
            },
          },
      };
  final _Objects objects;
  final events = StreamController<DBusSignal>.broadcast(sync: true);
  int reads = 0;
  @override
  Stream<DBusSignal> get signals => events.stream;
  @override
  Future<_Objects> getManagedObjects() async {
    reads++;
    return objects;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements DBusClient {
  final owners = StreamController<DBusNameOwnerChangedEvent>.broadcast(
    sync: true,
  );
  final networkReads = <String>[];
  int concurrent = 0;
  int maximumConcurrent = 0;
  int scans = 0;
  Future<void> Function(String path)? beforeNetworkRead;
  @override
  Stream<DBusNameOwnerChangedEvent> get nameOwnerChanged => owners.stream;
  @override
  Future<String?> getNameOwner(String name) async => ':1.42';
  @override
  Future<bool> nameHasOwner(String name) async => false;
  @override
  Future<void> registerObject(DBusObject object) async {}
  @override
  Future<void> unregisterObject(DBusObject object) async {}
  @override
  Future<void> close() => owners.close();
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
    if (name == 'RegisterAgent' || name == 'UnregisterAgent') {
      return DBusMethodSuccessResponse();
    }
    if (name == 'Scan') {
      scans++;
      return DBusMethodSuccessResponse();
    }
    if (name != 'GetOrderedNetworks') {
      throw StateError('Unexpected method $name');
    }
    networkReads.add(path.value);
    concurrent++;
    if (concurrent > maximumConcurrent) maximumConcurrent = concurrent;
    try {
      await beforeNetworkRead?.call(path.value);
      return DBusMethodSuccessResponse([
        DBusArray(DBusSignature('(on)'), [
          DBusStruct([
            DBusObjectPath('/network/${path.value.split('/').last}'),
            const DBusInt16(-5000),
          ]),
        ]),
      ]);
    } finally {
      concurrent--;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
