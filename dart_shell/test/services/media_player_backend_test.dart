import 'dart:async';
import 'dart:collection';

import 'package:dbus/dbus.dart';
import 'package:denial_dart_shell/src/services/media_player_backend.dart';
import 'package:denial_dart_shell/src/models/mpris_playback.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

const _prefix = 'org.mpris.MediaPlayer2.';
const _playerInterface = 'org.mpris.MediaPlayer2.Player';

void main() {
  late _Client client;
  late MediaPlayerService service;
  late Map<String, _Player> players;
  late List<String> creations;
  late DateTime now;

  _Player addPlayer(String suffix, String identity, String status) {
    final player = _Player('$_prefix$suffix', identity, status);
    players[player.name] = player;
    client.names.add(player.name);
    return player;
  }

  setUp(() {
    client = _Client();
    players = {};
    creations = [];
    now = DateTime.utc(2026, 9, 26);
    service = MediaPlayerService(
      client: client,
      playerFactory: (name) {
        creations.add(name);
        return players[name]!;
      },
      now: () => now,
    );
  });
  tearDown(() async {
    await service.dispose();
    for (final player in players.values) {
      // Single-subscription streams let the cancellation-race test delay
      // cancellation. Unselected players never acquired a listener to drain.
      if (player.listens > 0) {
        await player.events.close();
      } else {
        unawaited(player.events.close());
      }
    }
  });

  test('selection preserves playback priority and identity ordering', () async {
    addPlayer('paused', 'A', 'Paused');
    addPlayer('z', 'Z', 'Playing');
    final winner = addPlayer('a', 'A', 'Playing');
    addPlayer('tied', 'A', 'Playing');
    addPlayer('stopped', '0', 'Stopped');
    await service.start();
    expect(service.current.serviceName, winner.name);
    expect(winner.listens, 1);
    expect(players.values.where((p) => p.listens > 0), [winner]);
  });

  test(
    'discovery reads at most sixteen players and ignores other names',
    () async {
      client.names.add('org.example.Unrelated');
      for (var i = 0; i < 20; i++) {
        addPlayer('p$i', i.toString().padLeft(2, '0'), 'Playing');
      }
      await service.start();
      expect(creations, hasLength(16));
      expect(players.values.take(16).every((p) => p.reads == 2), isTrue);
      expect(players.values.skip(16).every((p) => p.reads == 0), isTrue);
    },
  );

  test(
    'recovery refreshes reuse the selected proxy and signal subscription',
    () async {
      final player = addPlayer('main', 'Player', 'Playing');
      await service.start();
      for (var i = 0; i < 50; i++) {
        await service.refresh();
      }
      expect(creations, [player.name]);
      expect(player.listens, 1);
      expect(player.cancels, 0);
      expect(player.reads, 102);
    },
  );

  test(
    'concurrent starts and refreshes await the entire coalesced scan',
    () async {
      addPlayer('main', 'Player', 'Playing');
      final firstGate = Completer<List<String>>();
      final secondGate = Completer<List<String>>();
      final secondEntered = Completer<void>();
      client.onList = () {
        if (client.lists == 1) return firstGate.future;
        secondEntered.complete();
        return secondGate.future;
      };
      final start = service.start();
      expect(identical(service.start(), start), isTrue);
      final pending = List.generate(100, (_) => service.refresh());
      expect(pending.every((f) => identical(f, start)), isTrue);
      var completed = false;
      final observed = start.then((_) => completed = true);
      firstGate.complete(client.names);
      await secondEntered.future;
      expect(completed, isFalse);
      secondGate.complete(client.names);
      await Future.wait([start, ...pending, observed]);
      expect(client.lists, 2);
      expect(service.current.available, isTrue);
    },
  );

  test('failed discovery does not discard a pending refresh', () async {
    addPlayer('main', 'Player', 'Playing');
    final gate = Completer<List<String>>();
    client.onList = () =>
        client.lists == 1 ? gate.future : Future.value(client.names);
    final first = service.start();
    final pending = service.refresh();
    gate.completeError(StateError('temporary discovery failure'));
    await Future.wait([first, pending]);
    expect(client.lists, 2);
    expect(service.current.available, isTrue);
  });

  test('disposal during discovery avoids all player reads', () async {
    addPlayer('main', 'Player', 'Playing');
    final gate = Completer<List<String>>();
    client.onList = () => gate.future;
    final start = service.start();
    await service.dispose();
    gate.complete(client.names);
    await start;
    expect(creations, isEmpty);
    expect(client.closed, isTrue);
  });

  test('disposal during property reads prevents new subscriptions', () async {
    final player = addPlayer('main', 'Player', 'Playing');
    final gate = Completer<void>();
    final entered = Completer<void>();
    player.beforeRead = () {
      if (!entered.isCompleted) entered.complete();
      return gate.future;
    };
    final start = service.start();
    await entered.future;
    await service.dispose();
    gate.complete();
    await start;
    expect(player.listens, 0);
    expect(service.current.available, isFalse);
  });

  test(
    'disposal while cancelling the old player cannot attach the next one',
    () async {
      final old = addPlayer('old', 'Old', 'Playing');
      final next = addPlayer('next', 'Next', 'Paused');
      await service.start();
      old.status = 'Paused';
      next.status = 'Playing';
      final gate = Completer<void>();
      final cancelling = Completer<void>();
      old.onCancel = () {
        cancelling.complete();
        return gate.future;
      };
      final refresh = service.refresh();
      await cancelling.future;
      await service.dispose();
      gate.complete();
      await refresh;
      expect(next.listens, 0);
      expect(old.cancels, 1);
    },
  );

  test('property signals update playback without a discovery scan', () async {
    final player = addPlayer('main', 'Player', 'Playing');
    await service.start();
    player.events.add(_signal({'PlaybackStatus': const DBusString('Paused')}));
    expect(service.current.status, MprisPlaybackStatus.paused);
    expect(client.lists, 1);
    expect(player.reads, 2);
  });

  test('a malformed deferred candidate does not hide a valid player', () async {
    final malformed = addPlayer('bad', 'Bad', 'Playing');
    final valid = addPlayer('valid', 'Valid', 'Paused');
    malformed.readProperties = (_) async => _InvalidProperties();
    await service.start();
    expect(service.current.serviceName, valid.name);
  });

  test(
    'an in-flight refresh cannot overwrite a newer playback signal',
    () async {
      final player = addPlayer('main', 'Player', 'Playing');
      await service.start();
      final gate = Completer<void>();
      final entered = Completer<void>();
      player.beforeRead = () {
        if (!entered.isCompleted) entered.complete();
        return gate.future;
      };
      final refresh = service.refresh();
      await entered.future;
      player.events.add(
        _signal({'PlaybackStatus': const DBusString('Paused')}),
      );
      expect(service.current.status, MprisPlaybackStatus.paused);
      gate.complete();
      await refresh;
      expect(service.current.status, MprisPlaybackStatus.paused);
      expect(client.lists, 2);
      expect(player.reads, 4);
    },
  );

  test(
    'signals win only their fields and preserve their position anchor',
    () async {
      final player = addPlayer('main', 'Player', 'Playing');
      player.properties = {
        'Metadata': _metadata('Old track'),
        'Position': const DBusInt64(10000000),
      };
      await service.start();
      final gate = Completer<void>();
      final entered = Completer<void>();
      player.beforeRead = () {
        if (!entered.isCompleted) entered.complete();
        return gate.future;
      };
      // These fresh fields must survive alongside the later signal fields.
      player.identity = 'New identity';
      player.properties = {
        ...player.properties,
        'CanPause': const DBusBoolean(true),
      };
      final refresh = service.refresh();
      await entered.future;
      now = now.add(const Duration(seconds: 5));
      final signalTime = now;
      player.events.add(
        _signal({
          'Metadata': _metadata('New track'),
          'Position': const DBusInt64(30000000),
          'CanGoNext': const DBusBoolean(true),
        }),
      );
      now = now.add(const Duration(seconds: 10));
      gate.complete();
      await refresh;
      expect(service.current.title, 'New track');
      expect(service.current.identity, 'New identity');
      expect(service.current.canPause, isTrue);
      expect(service.current.canGoNext, isTrue);
      expect(service.current.observedAt, signalTime);
      expect(service.current.position, const Duration(seconds: 30));
      expect(service.current.positionAt(now), const Duration(seconds: 40));
      expect(player.reads, 4);
    },
  );

  test('unchanged temporal fields retain the refreshed position', () async {
    final player = addPlayer('main', 'Player', 'Playing');
    player.properties = {
      'Metadata': _metadata('Track'),
      'Position': const DBusInt64(10000000),
    };
    await service.start();
    final gate = Completer<void>();
    final entered = Completer<void>();
    player.beforeRead = () {
      if (!entered.isCompleted) entered.complete();
      return gate.future;
    };
    final refresh = service.refresh();
    await entered.future;
    player.events.add(
      _signal({
        'Metadata': _metadata('Track'),
        'PlaybackStatus': const DBusString('Playing'),
        'CanGoNext': const DBusBoolean(true),
      }),
    );
    player.properties['Position'] = const DBusInt64(30000000);
    now = now.add(const Duration(seconds: 1));
    gate.complete();
    await refresh;
    expect(service.current.position, const Duration(seconds: 30));
    expect(service.current.observedAt, now);
    expect(service.current.canGoNext, isTrue);
    // Changes from this read must not leak into the next read's reconciliation.
    player.beforeRead = null;
    player.properties['CanGoNext'] = const DBusBoolean(false);
    await service.refresh();
    expect(service.current.canGoNext, isFalse);
  });

  test(
    'signals remain authoritative while a different player is slow',
    () async {
      final active = addPlayer('active', 'A', 'Playing');
      final slow = addPlayer('slow', 'Z', 'Paused');
      await service.start();
      final gate = Completer<void>();
      final entered = Completer<void>();
      slow.beforeRead = () {
        if (!entered.isCompleted) entered.complete();
        return gate.future;
      };
      final refresh = service.refresh();
      await entered.future;
      await Future<void>.delayed(Duration.zero);
      active.events.add(
        _signal({'PlaybackStatus': const DBusString('Paused')}),
      );
      gate.complete();
      await refresh;
      expect(service.current.serviceName, active.name);
      expect(service.current.status, MprisPlaybackStatus.paused);
      expect(client.lists, 2);
    },
  );

  test('a stale stopped reply cannot discard a later playing signal', () async {
    final player = addPlayer('main', 'Player', 'Paused');
    await service.start();
    final gate = Completer<void>();
    final entered = Completer<void>();
    player.status = 'Stopped';
    player.beforeRead = () {
      if (!entered.isCompleted) entered.complete();
      return gate.future;
    };
    final refresh = service.refresh();
    await entered.future;
    player.events.add(_signal({'PlaybackStatus': const DBusString('Playing')}));
    gate.complete();
    await refresh;
    expect(service.current.status, MprisPlaybackStatus.playing);
    expect(service.current.serviceName, player.name);
  });

  test(
    'selection uses a later stopped signal rather than stale playing data',
    () async {
      final active = addPlayer('active', 'Active', 'Playing');
      final paused = addPlayer('paused', 'Paused', 'Paused');
      await service.start();
      final gate = Completer<void>();
      final entered = Completer<void>();
      active.beforeRead = () {
        if (!entered.isCompleted) entered.complete();
        return gate.future;
      };
      final refresh = service.refresh();
      await entered.future;
      active.events.add(
        _signal({'PlaybackStatus': const DBusString('Stopped')}),
      );
      // No explicit status here: it must not resurrect the stopped read state.
      active.events.add(_signal({'CanPlay': const DBusBoolean(true)}));
      gate.complete();
      await refresh;
      expect(service.current.serviceName, paused.name);
      expect(service.current.status, MprisPlaybackStatus.paused);
    },
  );

  test(
    '1000 position signals during a refresh do not cause more reads',
    () async {
      final player = addPlayer('main', 'Player', 'Playing');
      player.properties = {'Metadata': _metadata('Track')};
      await service.start();
      final gate = Completer<void>();
      final entered = Completer<void>();
      player.beforeRead = () {
        if (!entered.isCompleted) entered.complete();
        return gate.future;
      };
      final refresh = service.refresh();
      await entered.future;
      for (var i = 0; i < 1000; i++) {
        player.events.add(_signal({'Position': DBusInt64(i * 1000)}));
      }
      gate.complete();
      await refresh;
      expect(service.current.position, const Duration(microseconds: 999000));
      expect(client.lists, 2);
      expect(player.reads, 4);
    },
  );

  test(
    'a slow root read does not shift the player position timestamp',
    () async {
      final player = addPlayer('main', 'Player', 'Playing');
      final gate = Completer<void>();
      final entered = Completer<void>();
      player.readProperties = (interface) async {
        if (interface == _playerInterface) {
          return {
            'PlaybackStatus': const DBusString('Playing'),
            'Metadata': _metadata('Track'),
            'Position': const DBusInt64(10000000),
          };
        }
        entered.complete();
        await gate.future;
        return {'Identity': const DBusString('Player')};
      };
      final start = service.start();
      await entered.future;
      await Future<void>.delayed(Duration.zero);
      final playerReadTime = now;
      now = now.add(const Duration(seconds: 1));
      gate.complete();
      await start;
      expect(service.current.observedAt, playerReadTime);
      expect(service.current.positionAt(now), const Duration(seconds: 11));
    },
  );

  test(
    'unrelated invalidations do not scan, and mixed changes are applied',
    () {
      fakeAsync((async) {
        final player = addPlayer('main', 'Player', 'Playing');
        unawaited(service.start());
        async.flushMicrotasks();
        player.events.add(_signal({}, invalidated: ['Volume', 'Shuffle']));
        async.elapse(const Duration(milliseconds: 100));
        expect(client.lists, 1);
        player.events.add(
          _signal(
            {'PlaybackStatus': const DBusString('Paused')},
            invalidated: ['Metadata'],
          ),
        );
        expect(service.current.status, MprisPlaybackStatus.paused);
        async.elapse(const Duration(milliseconds: 100));
        expect(client.lists, 2);
        unawaited(service.dispose());
        async.flushMicrotasks();
      });
    },
  );

  test(
    'temporary disappearance keeps the existing unavailable grace',
    () async {
      addPlayer('main', 'Player', 'Playing');
      await service.start();
      final current = service.current;
      client.names.clear();
      await service.refresh();
      expect(identical(service.current, current), isTrue);
    },
  );
}

DBusDict _metadata(String title) => DBusDict.stringVariant({
  'xesam:title': DBusString(title),
  'mpris:length': const DBusInt64(120000000),
});

DBusPropertiesChangedSignal _signal(
  Map<String, DBusValue> changed, {
  List<String> invalidated = const [],
}) => DBusPropertiesChangedSignal(
  DBusSignal(
    sender: ':1.1',
    path: DBusObjectPath('/org/mpris/MediaPlayer2'),
    interface: 'org.freedesktop.DBus.Properties',
    name: 'PropertiesChanged',
    values: [
      const DBusString(_playerInterface),
      DBusDict.stringVariant(changed),
      DBusArray.string(invalidated),
    ],
  ),
);

// These fakes never connect to D-Bus or send events to the running desktop.
class _Client implements DBusClient {
  final events = StreamController<DBusNameOwnerChangedEvent>.broadcast(
    sync: true,
  );
  final names = <String>[];
  int lists = 0;
  bool closed = false;
  Future<List<String>> Function()? onList;

  @override
  Stream<DBusNameOwnerChangedEvent> get nameOwnerChanged => events.stream;

  @override
  Future<List<String>> listNames() {
    lists++;
    return onList?.call() ?? Future.value(names);
  }

  @override
  Future<void> close() async {
    closed = true;
    await events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements DBusRemoteObject {
  _Player(this.name, this.identity, this.status) {
    events.onListen = () => listens++;
    events.onCancel = () {
      cancels++;
      return onCancel?.call();
    };
  }

  @override
  final String name;
  String identity;
  String status;
  Map<String, DBusValue> properties = {};
  Future<Map<String, DBusValue>> Function(String interface)? readProperties;
  int reads = 0;
  int listens = 0;
  int cancels = 0;
  Future<void> Function()? beforeRead;
  Future<void> Function()? onCancel;
  final events = StreamController<DBusPropertiesChangedSignal>(sync: true);

  @override
  Stream<DBusPropertiesChangedSignal> get propertiesChanged => events.stream;

  @override
  Future<Map<String, DBusValue>> getAllProperties(String interface) async {
    reads++;
    if (readProperties case final read?) return read(interface);
    await beforeRead?.call();
    return interface == _playerInterface
        ? {'PlaybackStatus': DBusString(status), ...properties}
        : {'Identity': DBusString(identity)};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InvalidProperties extends MapBase<String, DBusValue> {
  @override
  DBusValue? operator [](Object? key) =>
      throw const FormatException('invalid properties');

  @override
  Iterable<String> get keys => const [];

  @override
  void operator []=(String key, DBusValue value) =>
      throw UnsupportedError('read only');

  @override
  void clear() => throw UnsupportedError('read only');

  @override
  DBusValue? remove(Object? key) => throw UnsupportedError('read only');
}
