import 'dart:async';

import 'package:denial_dart_shell/src/services/lact_client.dart';
import 'package:test/test.dart';

void main() {
  test(
    '101 overlapping reads share one discovery/configuration pair',
    () async {
      final daemon = _Daemon();
      final gate = Completer<void>();
      daemon.beforeRequest = (command) =>
          command == 'get_gpu_config' ? gate.future : Future.value();
      final service = LactService(requestSender: daemon.send);
      final first = service.readAmdPerformancePreset();
      final reads = List.generate(
        100,
        (_) => service.readAmdPerformancePreset(),
      );
      expect(reads, everyElement(same(first)));
      await _flush();
      expect(daemon.commands, ['list_devices', 'get_gpu_config']);
      gate.complete();
      final snapshots = await Future.wait([first, ...reads]);
      expect(
        snapshots.every((snapshot) => identical(snapshot, snapshots.first)),
        isTrue,
      );
      expect(snapshots.first.preset, 'auto');
      expect(daemon.commands, hasLength(2));
      daemon.beforeRequest = null;
      daemon.config['performance_level'] = 'low';
      expect((await service.readAmdPerformancePreset()).preset, 'low');
      expect(daemon.commands, hasLength(4));
    },
  );

  test('reads queued after a write never join a pre-write snapshot', () async {
    final daemon = _Daemon();
    final gate = Completer<void>();
    daemon.beforeRequest = (command) =>
        daemon.commands.length == 2 ? gate.future : Future.value();
    final service = LactService(requestSender: daemon.send);
    final before = service.readAmdPerformancePreset();
    await _flush();
    final write = service.applyAmdPerformancePreset('high');
    final after = service.readAmdPerformancePreset();
    expect(after, isNot(same(before)));
    expect(service.readAmdPerformancePreset(), same(after));
    gate.complete();
    expect((await before).preset, 'auto');
    await write;
    expect((await after).preset, 'high');
    expect(daemon.commands, [
      'list_devices',
      'get_gpu_config',
      'list_devices',
      'get_gpu_config',
      'set_gpu_config',
      'confirm_pending_config',
      'list_devices',
      'get_gpu_config',
    ]);
  });

  test(
    'overlapping changes keep each set/confirm transaction together',
    () async {
      final daemon = _Daemon();
      final gate = Completer<void>();
      daemon.beforeRequest = (command) =>
          command == 'confirm_pending_config' && daemon.commands.length == 4
          ? gate.future
          : Future.value();
      final service = LactService(requestSender: daemon.send);
      final high = service.applyAmdPerformancePreset('high');
      final low = service.applyAmdPerformancePreset('low');
      final finalRead = service.readAmdPerformancePreset();
      await _flush();
      expect(daemon.commands, [
        'list_devices',
        'get_gpu_config',
        'set_gpu_config',
        'confirm_pending_config',
      ]);
      expect(daemon.confirmed, isEmpty);
      gate.complete();
      await Future.wait([high, low]);
      expect(daemon.confirmed, ['high', 'low']);
      expect((await finalRead).preset, 'low');
      expect(daemon.commands, hasLength(10));
    },
  );

  test(
    'a read between two changes sees the intervening configuration',
    () async {
      final daemon = _Daemon();
      final service = LactService(requestSender: daemon.send);
      final high = service.applyAmdPerformancePreset('high');
      final between = service.readAmdPerformancePreset();
      final low = service.applyAmdPerformancePreset('low');
      final after = service.readAmdPerformancePreset();
      await high;
      expect((await between).preset, 'high');
      await low;
      expect((await after).preset, 'low');
      expect(daemon.confirmed, ['high', 'low']);
    },
  );

  for (final failingCommand in [
    'list_devices',
    'get_gpu_config',
    'set_gpu_config',
    'confirm_pending_config',
  ]) {
    test('a failed $failingCommand does not poison later operations', () async {
      final daemon = _Daemon();
      var fail = true;
      daemon.beforeRequest = (command) async {
        if (command == failingCommand && fail) {
          fail = false;
          throw StateError('failed $command');
        }
      };
      final service = LactService(requestSender: daemon.send);
      final first = service.applyAmdPerformancePreset('high');
      final failure = expectLater(first, throwsStateError);
      final recovery = service.applyAmdPerformancePreset('low');
      await failure;
      await recovery;
      expect(daemon.confirmed, ['low']);
      expect((await service.readAmdPerformancePreset()).preset, 'low');
    });
  }

  test('failed reads are shared only while pending and can recover', () async {
    final daemon = _Daemon()..devices = [];
    final service = LactService(requestSender: daemon.send);
    final failed = service.readAmdPerformancePreset();
    expect(service.readAmdPerformancePreset(), same(failed));
    expect((await failed).available, isFalse);
    daemon.devices = [
      {'id': '1002:new'},
    ];
    final recovered = await service.readAmdPerformancePreset();
    expect(recovered.available, isTrue);
    expect(daemon.readIds, ['1002:new']);
  });

  test(
    'discovery preserves the first AMD device and detects replacements',
    () async {
      final daemon = _Daemon()
        ..devices = [
          null,
          'invalid',
          {'id': 42},
          {'id': '10DE:Nvidia'},
          {'id': '1002:AbCd'},
          {'id': '1002:second'},
        ];
      final service = LactService(requestSender: daemon.send);
      await service.readAmdPerformancePreset();
      daemon.devices = [
        {'id': '1002:replacement'},
      ];
      await service.readAmdPerformancePreset();
      expect(daemon.readIds, ['1002:AbCd', '1002:replacement']);
    },
  );

  test(
    'config writes own their map and preserve unrelated tuning values',
    () async {
      final nested = {'enabled': true, 'temperature': 75};
      final daemon = _Daemon()
        ..config = {
          'performance_level': 'auto',
          'fan_control': nested,
          'power_cap': 150,
        };
      final original = daemon.config;
      final service = LactService(requestSender: daemon.send);
      await service.applyAmdPerformancePreset('high');
      expect(original['performance_level'], 'auto');
      expect(daemon.config, {
        'performance_level': 'high',
        'fan_control': nested,
        'power_cap': 150,
      });
      expect(daemon.config['fan_control'], same(nested));
    },
  );

  test(
    'unchanged presets do not write, and invalid presets do no I/O',
    () async {
      final daemon = _Daemon()..config['performance_level'] = ' AUTO ';
      final service = LactService(requestSender: daemon.send);
      await expectLater(
        service.applyAmdPerformancePreset('invalid'),
        throwsArgumentError,
      );
      expect(daemon.commands, isEmpty);
      await service.applyAmdPerformancePreset('auto');
      expect(daemon.commands, ['list_devices', 'get_gpu_config']);
      expect(daemon.confirmed, isEmpty);
    },
  );

  test('malformed replies keep the existing unavailable behavior', () async {
    for (final config in [
      null,
      [],
      {'performance_level': 'unknown'},
      {42: 'non-string key'},
    ]) {
      final service = LactService(
        requestSender: (request) async => request['command'] == 'list_devices'
            ? [
                {'id': '1002:first'},
              ]
            : config,
      );
      final snapshot = await service.readAmdPerformancePreset();
      expect(snapshot.available, config is Map<String, String>);
      expect(snapshot.preset, isNull);
    }
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

// This sender holds all state in memory. No socket, GPU, or daemon is touched.
class _Daemon {
  final commands = <String>[];
  final confirmed = <String>[];
  final readIds = <String>[];
  List<Object?> devices = [
    {'id': '1002:first'},
  ];
  Map<String, Object?> config = {'performance_level': 'auto'};
  Map<String, Object?>? pending;
  Future<void> Function(String command)? beforeRequest;

  Future<Object?> send(Map<String, Object?> request) async {
    final command = request['command']! as String;
    commands.add(command);
    await beforeRequest?.call(command);
    final args = request['args'] as Map<String, Object?>?;
    return switch (command) {
      'list_devices' => devices,
      'get_gpu_config' => _read(args!),
      'set_gpu_config' => pending = args!['config']! as Map<String, Object?>,
      'confirm_pending_config' => _confirm(),
      _ => throw StateError('Unexpected command $command'),
    };
  }

  Map<String, Object?> _read(Map<String, Object?> args) {
    readIds.add(args['id']! as String);
    return config;
  }

  Object? _confirm() {
    config = pending!;
    pending = null;
    confirmed.add(config['performance_level']! as String);
    return null;
  }
}
