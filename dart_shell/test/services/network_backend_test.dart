import 'dart:math';

import 'package:denial_dart_shell/src/services/network_backend.dart';
import 'package:test/test.dart';

import '../support/legacy_wifi_normalization.dart';

void main() {
  test('network updates share immutable identity data', () {
    final bytes = [65, 66];
    final original = _network(1, bytes: bytes);
    bytes[0] = 67;
    final updated = original.copyWith(
      savedNetworkPath: '/saved/1',
      connected: true,
      available: false,
      supported: false,
      devicePath: '/device/2',
      networkPath: '/ap/2',
    );
    expect(original.ssidBytes, [65, 66]);
    expect(updated.ssidBytes, same(original.ssidBytes));
    expect(updated.identity, same(original.identity));
    expect(() => updated.ssidBytes.add(1), throwsUnsupportedError);
    expect(updated.savedNetworkPath, '/saved/1');
    expect(updated.connected, isTrue);
    expect(updated.available, isFalse);
    expect(updated.supported, isFalse);
    expect(updated.devicePath, '/device/2');
    expect(updated.networkPath, '/ap/2');
    expect(updated.strength, original.strength);
    expect(updated.frequency, original.frequency);
    expect(original.connected, isFalse);
  });

  test('unchanged updates preserve the network instance', () {
    final original = _network(1).copyWith(savedNetworkPath: '/saved/1');
    expect(original.copyWith(), same(original));
    expect(
      original.copyWith(
        devicePath: original.devicePath,
        networkPath: original.networkPath,
        savedNetworkPath: original.savedNetworkPath,
        connected: original.connected,
        available: original.available,
        supported: original.supported,
      ),
      same(original),
    );
    expect(original.copyWith(savedNetworkPath: null), same(original));
  });

  test('connected access points beat stronger disconnected duplicates', () {
    final connected = _network(1, strength: 10, connected: true);
    final result = normalizeWifiNetworks(
      [_network(1, strength: 90), connected, _network(1, strength: 50)],
      [],
      defaultDevicePath: '/device',
    );
    expect(result, [connected]);
  });

  test(
    'first saved profile wins and invisible saved networks remain usable',
    () {
      final visible = _network(1);
      final result = normalizeWifiNetworks(
        [visible],
        [_saved(1, '/first'), _saved(1, '/duplicate'), _saved(2, '/offline')],
        defaultDevicePath: '/fallback',
      );
      expect(result.map((n) => n.savedNetworkPath), ['/first', '/offline']);
      final offline = result.last;
      expect(offline.available, isFalse);
      expect(offline.connected, isFalse);
      expect(offline.devicePath, '/fallback');
      expect(offline.networkPath, '/');
      expect(offline.connectable, isTrue);
    },
  );

  test('results are bounded, independently owned, and immutable', () {
    final source = [_network(1), _network(2)];
    final result = normalizeWifiNetworks(
      source,
      [],
      defaultDevicePath: '',
      maximum: 1,
    );
    source.clear();
    expect(result, hasLength(1));
    expect(() => result.clear(), throwsUnsupportedError);
    expect(
      normalizeWifiNetworks([], [], defaultDevicePath: '', maximum: 0),
      isEmpty,
    );
    expect(
      () => normalizeWifiNetworks([], [], defaultDevicePath: '', maximum: -1),
      throwsRangeError,
    );
  });

  test('copying preserves value equality and hash behavior', () {
    final original = _network(1);
    final updated = original.copyWith(savedNetworkPath: '/saved');
    final legacy = legacyCopyWifiNetwork(original, savedNetworkPath: '/saved');
    expect(updated, legacy);
    expect(updated.hashCode, legacy.hashCode);
    expect(_snapshot([updated]), _snapshot([legacy]));
    expect(_snapshot([updated]).hashCode, _snapshot([legacy]).hashCode);
    expect(_snapshot([updated]), isNot(_snapshot([original])));
    expect(_saved(1, '/a'), _saved(1, '/a'));
    expect(_saved(1, '/a').hashCode, _saved(1, '/a').hashCode);
  });

  test('randomized normalization retains previous grouping and ordering', () {
    final random = Random(734);
    for (var trial = 0; trial < 1000; trial++) {
      final candidates = List.generate(random.nextInt(130), (i) {
        final id = random.nextInt(40);
        return _network(
          id,
          strength: random.nextInt(5) * 20,
          connected: random.nextInt(8) == 0,
          security:
              WifiSecurity.values[random.nextInt(WifiSecurity.values.length)],
          name: i.isEven ? 'WiFi $id' : 'wifi $id',
        );
      });
      final saved = List.generate(
        random.nextInt(40),
        (i) => _saved(random.nextInt(40), '/saved/$i'),
      );
      final maximum = random.nextInt(65);
      expect(
        normalizeWifiNetworks(
          candidates,
          saved,
          defaultDevicePath: '/default',
          maximum: maximum,
        ),
        legacyNormalizeWifiNetworks(
          candidates,
          saved,
          defaultDevicePath: '/default',
          maximum: maximum,
        ),
        reason: 'trial $trial',
      );
    }
  });
}

WifiNetwork _network(
  int id, {
  List<int>? bytes,
  int strength = 50,
  bool connected = false,
  WifiSecurity security = WifiSecurity.wpaPersonal,
  String? name,
}) => WifiNetwork(
  ssid: name ?? 'network $id',
  ssidBytes: bytes ?? [id],
  security: security,
  strength: strength,
  frequency: 2400,
  devicePath: '/device/1',
  networkPath: '/ap/$id',
  savedNetworkPath: null,
  connected: connected,
  available: true,
);

SavedWifiConnectionInfo _saved(int id, String path) => SavedWifiConnectionInfo(
  objectPath: path,
  name: 'network $id',
  ssidBytes: [id],
  security: WifiSecurity.wpaPersonal,
);

NetworkSnapshot _snapshot(List<WifiNetwork> networks) => NetworkSnapshot(
  serviceAvailable: true,
  wifiDeviceAvailable: true,
  wirelessHardwareEnabled: true,
  wirelessEnabled: true,
  status: NetworkConnectivityStatus.online,
  networks: networks,
  activeNetworkPath: '/connection',
  devicePath: '/device',
  lastScan: 10,
  radioPermission: NetworkPermission.allowed,
  controlPermission: NetworkPermission.allowed,
  modifyPermission: NetworkPermission.allowed,
);
