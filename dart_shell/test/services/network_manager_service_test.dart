import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:denial_dart_shell/src/services/network_manager_service.dart';
import 'package:test/test.dart';

void main() {
  test('independent root reads start before any of them completes', () async {
    final gate = Completer<void>();
    final started = <String>[];
    final client = _Client({})
      ..beforeCall = (method, interface, path) async {
        started.add(method);
        await gate.future;
      };
    final service = NetworkManagerService(client: client);
    try {
      final refresh = service.refresh();
      await _flush();
      expect(started, ['GetAll', 'GetPermissions', 'GetDevices']);
      gate.complete();
      await refresh;
      expect(service.currentSnapshot.serviceAvailable, isTrue);
      expect(service.currentSnapshot.wifiDeviceAvailable, isFalse);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await service.dispose();
    }
  });

  test('101 overlapping refreshes share two bounded scans', () async {
    final gates = [Completer<bool>(), Completer<bool>()];
    final client = _Client({});
    client.readOwner = () => gates[client.ownerReads - 1].future;
    final service = NetworkManagerService(client: client);
    var completed = false;
    try {
      final first = service.refresh();
      final pending = List.generate(100, (_) => service.refresh());
      expect(pending, everyElement(same(first)));
      unawaited(first.then((_) => completed = true));
      expect(client.ownerReads, 1);
      gates.first.complete(true);
      await _flush();
      expect(client.ownerReads, 2);
      expect(completed, isFalse);
      gates.last.complete(true);
      await Future.wait([first, ...pending]);
      expect(completed, isTrue);
      expect(client.ownerReads, 2);
    } finally {
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete(false);
      }
      await service.dispose();
    }
  });

  test('a failed scan keeps the coalesced retry and its waiters', () async {
    final gate = Completer<bool>();
    final client = _Client({});
    client.readOwner = () async =>
        client.ownerReads == 1 ? await gate.future : true;
    final service = NetworkManagerService(client: client);
    try {
      final first = service.refresh();
      final second = service.refresh();
      gate.completeError(StateError('service temporarily unavailable'));
      await Future.wait([first, second]);
      expect(client.ownerReads, 2);
      expect(service.currentSnapshot.serviceAvailable, isTrue);
      // A later request starts a new cycle instead of retaining a completed one.
      await service.refresh();
      expect(client.ownerReads, 3);
    } finally {
      if (!gate.isCompleted) gate.complete(false);
      await service.dispose();
    }
  });

  test(
    'disposing during owner lookup drops pending reads and publication',
    () async {
      final gate = Completer<bool>();
      final calls = <String>[];
      final client = _Client({})
        ..readOwner = (() => gate.future)
        ..beforeCall = (method, interface, path) async => calls.add(method);
      final service = NetworkManagerService(client: client);
      final snapshots = <NetworkSnapshot>[];
      service.snapshots.listen(snapshots.add);
      final first = service.refresh();
      final second = service.refresh();
      await service.dispose();
      gate.complete(true);
      await Future.wait([first, second]);
      expect(client.ownerReads, 1);
      expect(calls, isEmpty);
      expect(snapshots, isEmpty);
      expect(service.currentSnapshot.serviceAvailable, isFalse);
      await service.refresh();
      expect(client.ownerReads, 1);
    },
  );

  test('a root read failure drains concurrent reads before retrying', () async {
    final gate = Completer<void>();
    var failRoot = true;
    final client = _Client({})
      ..beforeCall = (method, interface, path) async {
        if (!failRoot) return;
        if (method == 'GetAll') throw StateError('root unavailable');
        await gate.future;
      };
    final service = NetworkManagerService(client: client);
    var completed = false;
    try {
      final first = service.refresh();
      final second = service.refresh();
      unawaited(first.then((_) => completed = true));
      await _flush();
      expect(completed, isFalse);
      expect(client.ownerReads, 1);
      failRoot = false;
      gate.complete();
      await Future.wait([first, second]);
      expect(client.ownerReads, 2);
      expect(service.currentSnapshot.serviceAvailable, isTrue);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await service.dispose();
    }
  });

  test('refresh requested by a snapshot listener joins the drain', () async {
    final client = _Client({});
    final service = NetworkManagerService(client: client);
    Future<void>? listenerRefresh;
    final subscription = service.snapshots.listen((_) {
      listenerRefresh ??= service.refresh();
    });
    try {
      final first = service.refresh();
      await first;
      expect(listenerRefresh, same(first));
      expect(client.ownerReads, 2);
    } finally {
      await subscription.cancel();
      await service.dispose();
    }
  });

  test(
    'disposal stops remaining access-point batches and saved reads',
    () async {
      final gate = Completer<void>();
      var inFlight = 0;
      var savedReads = 0;
      final client =
          _Client({'/device/one': List.generate(30, (i) => '/ap/$i')})
            ..beforeCall = (method, interface, path) async {
              if (interface == 'org.freedesktop.NetworkManager.AccessPoint') {
                inFlight++;
                await gate.future;
                inFlight--;
              } else if (method == 'ListConnections') {
                savedReads++;
              }
            };
      final service = NetworkManagerService(client: client);
      try {
        final refresh = service.refresh();
        await _flush();
        expect(inFlight, 12);
        await service.dispose();
        gate.complete();
        await refresh;
        expect(client.accessPointReads, hasLength(12));
        expect(savedReads, 0);
        expect(service.currentSnapshot.serviceAvailable, isFalse);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await service.dispose();
      }
    },
  );

  test(
    'shared access points are read once and belong to the preferred adapter',
    () async {
      final client = _Client({
        '/device/idle': ['/ap/shared', '/ap/idle'],
        '/device/active': ['/ap/shared', '/ap/active'],
      }, activeDevice: '/device/active');
      final service = NetworkManagerService(client: client);
      try {
        await service.refresh();
        expect(client.accessPointReads, [
          '/ap/shared',
          '/ap/active',
          '/ap/idle',
        ]);
        final networks = service.currentSnapshot.networks;
        expect(networks, hasLength(3));
        expect(networks.first.networkPath, '/ap/shared');
        expect(networks.first.devicePath, '/device/active');
        expect(networks.first.connected, isTrue);
        expect(
          networks.singleWhere((n) => n.networkPath == '/ap/idle').devicePath,
          '/device/idle',
        );
      } finally {
        await service.dispose();
      }
    },
  );

  test(
    'duplicate paths do not consume the 128 access-point read limit',
    () async {
      final paths = List.generate(150, (i) => '/ap/$i');
      final client = _Client({
        '/device/one': [
          for (final path in paths) ...[path, path],
        ],
        '/device/two': paths,
      });
      final service = NetworkManagerService(client: client);
      try {
        await service.refresh();
        expect(client.accessPointReads, paths.take(128));
        expect(service.currentSnapshot.networks, hasLength(64));
      } finally {
        await service.dispose();
      }
    },
  );

  test('an empty adapter still yields a usable empty snapshot', () async {
    final client = _Client({'/device/one': []});
    final service = NetworkManagerService(client: client);
    try {
      await service.refresh();
      expect(client.accessPointReads, isEmpty);
      expect(service.currentSnapshot.wifiDeviceAvailable, isTrue);
      expect(service.currentSnapshot.networks, isEmpty);
    } finally {
      await service.dispose();
    }
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

// In-memory method replies exercise the real refresh/parsing path. No system
// bus connection, radio scan, or other visible event is involved.
class _Client implements DBusClient {
  _Client(this.devices, {this.activeDevice});
  final Map<String, List<String>> devices;
  final String? activeDevice;
  final accessPointReads = <String>[];
  int ownerReads = 0;
  Future<bool> Function()? readOwner;
  Future<void> Function(String method, String? interface, String path)?
  beforeCall;

  @override
  Future<bool> nameHasOwner(String name) async {
    ownerReads++;
    return await readOwner?.call() ?? true;
  }

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
    await beforeCall?.call(
      name,
      name == 'GetAll' ? values.single.asString() : interface,
      path.value,
    );
    if (name == 'GetDevices') {
      return DBusMethodSuccessResponse([
        DBusArray.objectPath(devices.keys.map(DBusObjectPath.new)),
      ]);
    }
    if (name == 'ListConnections') {
      return DBusMethodSuccessResponse([DBusArray.objectPath([])]);
    }
    if (name == 'GetPermissions') {
      return DBusMethodSuccessResponse([
        DBusDict(DBusSignature('s'), DBusSignature('s'), {}),
      ]);
    }
    if (name != 'GetAll') throw StateError('Unexpected method $name');
    final requestedInterface = values.single.asString();
    const root = 'org.freedesktop.NetworkManager';
    final Map<String, DBusValue> properties;
    if (requestedInterface == root) {
      properties = {
        'WirelessEnabled': const DBusBoolean(true),
        'WirelessHardwareEnabled': const DBusBoolean(true),
      };
    } else if (requestedInterface == '$root.Device') {
      properties = {
        'DeviceType': const DBusUint32(2),
        'State': DBusUint32(path.value == activeDevice ? 100 : 30),
        'ActiveConnection': DBusObjectPath(
          path.value == activeDevice ? '/active' : '/',
        ),
      };
    } else if (requestedInterface == '$root.Device.Wireless') {
      properties = {
        'AccessPoints': DBusArray.objectPath(
          devices[path.value]!.map(DBusObjectPath.new),
        ),
        'ActiveAccessPoint': DBusObjectPath(
          path.value == activeDevice ? '/ap/shared' : '/',
        ),
      };
    } else if (requestedInterface == '$root.AccessPoint') {
      accessPointReads.add(path.value);
      properties = {
        'Ssid': DBusArray.byte(path.value.codeUnits),
        'Strength': const DBusByte(50),
      };
    } else {
      throw StateError('Unexpected interface $requestedInterface');
    }
    return DBusMethodSuccessResponse([DBusDict.stringVariant(properties)]);
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
