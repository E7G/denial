import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:denial_dart_shell/src/services/network_backend.dart';
import 'package:denial_dart_shell/src/services/network_service_backend.dart';
import 'package:test/test.dart';

const _nm = 'org.freedesktop.NetworkManager';
const _iwd = 'net.connman.iwd';

void main() {
  late _Client client;
  late _Backend nm;
  late _Backend iwd;
  late NetworkService service;

  setUp(() {
    client = _Client();
    nm = _Backend();
    iwd = _Backend();
    service = NetworkService(
      client: client,
      networkManagerFactory: () => nm,
      iwdFactory: () => iwd,
    );
  });
  tearDown(() async {
    await service.dispose();
    await nm.events.close();
    await iwd.events.close();
  });

  test(
    'NetworkManager wins and concurrent starts share initialization',
    () async {
      final gate = Completer<void>();
      final entered = Completer<void>();
      nm.onStart = () {
        entered.complete();
        return gate.future;
      };
      final first = service.start();
      await entered.future;
      final second = service.start();
      expect(identical(first, second), isTrue);
      expect(client.lookups, [_nm]);
      expect(iwd.starts, 0);
      gate.complete();
      await Future.wait([first, second]);
      expect(nm.starts, 1);
    },
  );

  test(
    '101 overlapping refreshes use two reads and actions await both',
    () async {
      await service.start();
      client.lookups.clear();
      final firstGate = Completer<void>();
      final lastGate = Completer<void>();
      final firstEntered = Completer<void>();
      final lastEntered = Completer<void>();
      nm.onRefresh = () {
        if (nm.refreshes == 1) {
          firstEntered.complete();
          return firstGate.future;
        }
        lastEntered.complete();
        return lastGate.future;
      };
      final first = service.refresh();
      await firstEntered.future;
      final pending = List.generate(100, (_) => service.refresh());
      expect(pending.every((future) => identical(future, first)), isTrue);
      final action = service.requestScan();
      expect(nm.scans, 0);
      firstGate.complete();
      await lastEntered.future;
      expect(nm.scans, 0);
      lastGate.complete();
      await Future.wait([first, ...pending, action]);
      expect(nm.refreshes, 2);
      expect(client.lookups, [_nm, _nm]);
      expect(nm.scans, 1);
    },
  );

  test(
    'pending selection observes a backend change before actions run',
    () async {
      await service.start();
      final gate = Completer<void>();
      final entered = Completer<void>();
      nm.onRefresh = () {
        entered.complete();
        return gate.future;
      };
      final first = service.refresh();
      await entered.future;
      client.owners.remove(_nm);
      final followUp = service.refresh();
      final action = service.requestScan();
      gate.complete();
      await Future.wait([first, followUp, action]);
      expect(nm.disposals, 1);
      expect(nm.scans, 0);
      expect(iwd.starts, 1);
      expect(iwd.scans, 1);
    },
  );

  test('owner event bursts schedule one selection', () async {
    await service.start();
    client.lookups.clear();
    client.owners.remove(_nm);
    final started = Completer<void>();
    iwd.onStart = () async => started.complete();
    for (var i = 0; i < 100; i++) {
      client.events.add(const DBusNameOwnerChangedEvent(_nm));
    }
    await started.future;
    await service.start();
    expect(client.lookups, [_nm, _iwd]);
    expect(iwd.starts, 1);
    expect(nm.disposals, 1);
  });

  test('a failed active refresh still runs its pending replacement', () async {
    await service.start();
    final gate = Completer<void>();
    final entered = Completer<void>();
    nm.onRefresh = () {
      if (nm.refreshes == 1) {
        entered.complete();
        return gate.future;
      }
      return Future<void>.value();
    };
    final first = service.refresh();
    await entered.future;
    final pending = service.refresh();
    gate.completeError(StateError('stale read failed'));
    await Future.wait([first, pending]);
    expect(nm.refreshes, 2);
  });

  test(
    'a final failure reaches callers and later refreshes can recover',
    () async {
      await service.start();
      nm.onRefresh = () async => throw StateError('read failed');
      await expectLater(service.refresh(), throwsStateError);
      nm.onRefresh = null;
      await service.refresh();
      expect(nm.refreshes, 2);
    },
  );

  test(
    'failed startup disposes the backend and leaves selection retryable',
    () async {
      nm.onStart = () async => throw StateError('start failed');
      await service.start();
      expect(nm.disposals, 1);
      expect(service.currentSnapshot.serviceAvailable, isFalse);
      nm = _Backend();
      await service.refresh();
      expect(nm.starts, 1);
      expect(service.currentSnapshot.serviceAvailable, isTrue);
    },
  );

  test('disposal during owner lookup avoids backend creation', () async {
    final gate = Completer<bool>();
    client.onLookup = (_) => gate.future;
    final start = service.start();
    final disposal = service.dispose();
    gate.complete(false);
    await Future.wait([start, disposal]);
    expect(client.lookups, [_nm]);
    expect(nm.starts, 0);
    expect(iwd.starts, 0);
    expect(client.closed, isTrue);
  });

  test('disposal drops pending work and suppresses late snapshots', () async {
    await service.start();
    final before = service.currentSnapshot;
    final emitted = <NetworkSnapshot>[];
    final subscription = service.snapshots.listen(emitted.add);
    final gate = Completer<void>();
    final entered = Completer<void>();
    nm.onRefresh = () async {
      entered.complete();
      await gate.future;
      nm.current = const NetworkSnapshot.unavailable();
      nm.events.add(nm.current);
    };
    final first = service.refresh();
    await entered.future;
    final pending = service.refresh();
    final disposal = service.dispose();
    gate.complete();
    await Future.wait([first, pending, disposal]);
    expect(nm.refreshes, 1);
    expect(nm.disposals, 1);
    expect(emitted, isEmpty);
    expect(identical(service.currentSnapshot, before), isTrue);
    await expectLater(service.requestScan(), throwsStateError);
    expect(nm.scans, 0);
    await subscription.cancel();
  });
}

// In-memory buses and backends only: no network device or live service is used.
class _Client implements DBusClient {
  final events = StreamController<DBusNameOwnerChangedEvent>.broadcast(
    sync: true,
  );
  final owners = {_nm, _iwd};
  final lookups = <String>[];
  Future<bool> Function(String)? onLookup;
  bool closed = false;

  @override
  Stream<DBusNameOwnerChangedEvent> get nameOwnerChanged => events.stream;

  @override
  Future<bool> nameHasOwner(String name) {
    lookups.add(name);
    return onLookup?.call(name) ?? Future.value(owners.contains(name));
  }

  @override
  Future<void> close() async {
    closed = true;
    await events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Backend implements NetworkBackend {
  final events = StreamController<NetworkSnapshot>.broadcast(sync: true);
  int starts = 0;
  int refreshes = 0;
  int disposals = 0;
  int scans = 0;
  Future<void> Function()? onStart;
  Future<void> Function()? onRefresh;
  NetworkSnapshot current = NetworkSnapshot(
    serviceAvailable: true,
    wifiDeviceAvailable: true,
    wirelessHardwareEnabled: true,
    wirelessEnabled: true,
    status: NetworkConnectivityStatus.disconnected,
    networks: [],
    activeNetworkPath: null,
    devicePath: '/wifi',
    lastScan: -1,
    radioPermission: NetworkPermission.allowed,
    controlPermission: NetworkPermission.allowed,
    modifyPermission: NetworkPermission.allowed,
  );

  @override
  Stream<NetworkSnapshot> get snapshots => events.stream;
  @override
  NetworkSnapshot get currentSnapshot => current;

  @override
  Future<void> start() async {
    starts++;
    await onStart?.call();
  }

  @override
  Future<void> refresh() async {
    refreshes++;
    await onRefresh?.call();
  }

  @override
  Future<void> requestScan() async => scans++;

  @override
  Future<void> dispose() async {
    disposals++;
    await events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
