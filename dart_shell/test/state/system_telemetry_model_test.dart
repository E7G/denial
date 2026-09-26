import 'dart:math';

import 'package:denial_dart_shell/src/models/shell_power_status.dart';
import 'package:denial_dart_shell/src/models/system_telemetry.dart';
import 'package:denial_dart_shell/src/services/linux_cpu_usage.dart';
import 'package:denial_dart_shell/src/services/linux_gpu_usage.dart';
import 'package:denial_dart_shell/src/state/system_telemetry_model.dart';
import 'package:test/test.dart';

void main() {
  test(
    'history keeps the newest 45 values and retains absent temperatures',
    () {
      var series = const LoadSeries(temperatureC: 50);
      for (var i = 0; i < 100; i++) {
        series = series.append(i / 100);
      }
      expect(series.history, List.generate(45, (i) => (i + 55) / 100));
      expect(series.current, 0.99);
      expect(series.temperatureC, 50);
      expect(series.append(0.5, temperatureC: 60).temperatureC, 60);
      expect(() => series.history.add(0), throwsUnsupportedError);
    },
  );

  test('append owns its copy and leaves earlier snapshots unchanged', () {
    final source = [0.1, 0.2];
    final first = LoadSeries(history: source).append(0.3);
    source[0] = 1;
    final second = first.append(0.4);
    expect(first.history, [0.1, 0.2, 0.3]);
    expect(second.history, [0.1, 0.2, 0.3, 0.4]);
  });

  test('only a complete repeated history can reuse its series', () {
    var series = const LoadSeries(temperatureC: 40).append(0.7);
    for (var i = 0; i < 45; i++) {
      final next = series.append(0);
      expect(identical(next, series), isFalse);
      series = next;
    }
    expect(series.history, List.filled(45, 0));
    expect(identical(series.append(0), series), isTrue);
    final warmer = series.append(0, temperatureC: 50);
    expect(identical(warmer, series), isFalse);
    expect(identical(warmer.history, series.history), isTrue);
    expect(warmer.temperatureC, 50);
    expect(identical(warmer.append(0), warmer), isTrue);
    expect(series.append(0.1).history.last, 0.1);
  });

  test('an external constant-valued history is still copied and frozen', () {
    final source = List<double>.filled(45, 0);
    final supplied = LoadSeries(current: 0, history: source);
    final appended = supplied.append(0);
    expect(identical(appended, supplied), isFalse);
    source[0] = 1;
    expect(appended.history.first, 0);
    expect(() => appended.history[0] = 1, throwsUnsupportedError);
  });

  test(
    'long repeated runs and temperature changes retain every sample value',
    () {
      final random = Random(3902);
      var series = const LoadSeries();
      var expected = <double>[];
      double? temperature;
      for (var run = 0; run < 200; run++) {
        final usage = random.nextInt(5) / 4;
        for (var i = 0; i < random.nextInt(150) + 50; i++) {
          final reportedTemperature = random.nextInt(10) == 0
              ? random.nextInt(80).toDouble()
              : null;
          temperature = reportedTemperature ?? temperature;
          expected = [...expected, usage];
          if (expected.length > 45) expected.removeAt(0);
          series = series.append(usage, temperatureC: reportedTemperature);
          expect(series.history, expected);
          expect(series.current, usage);
          expect(series.temperatureC, temperature);
        }
      }
    },
  );

  test('removing a settled GPU retains the remaining history in a new immutable list', () {
    final model = SystemTelemetryModel();
    var current = const SystemTelemetrySnapshot();
    for (var i = 0; i < 45; i++) {
      current = _update(model, current, gpus: [_gpu('a', 0), _gpu('b', 0)]);
    }
    final previous = current;
    current = _update(model, current, gpus: [_gpu('a', 0)]);
    expect(current.gpus, hasLength(1));
    expect(identical(current.gpus.single, previous.gpus.first), isTrue);
    expect(previous.gpus, hasLength(2));
    expect(() => current.gpus.clear(), throwsUnsupportedError);
  });

  test(
    '1000 unchanged polls retain the snapshot and advance the CPU anchor',
    () {
      final model = SystemTelemetryModel();
      var current = const SystemTelemetrySnapshot();
      for (var i = 0; i <= 45; i++) {
        current = _update(
          model,
          current,
          cpu: CpuSample(busy: 0, total: i * 100),
          gpus: [_gpu('a', 0, temperature: 40)],
        );
      }
      final settled = current;
      var publications = 0;
      for (var i = 46; i <= 1045; i++) {
        final next = _update(
          model,
          current,
          cpu: CpuSample(busy: 0, total: i * 100),
          gpus: [_gpu('a', 0, temperature: 40)],
        );
        if (!identical(next, current)) publications++;
        current = next;
      }
      expect(publications, 0);
      expect(identical(current, settled), isTrue);
      final active = _update(
        model,
        current,
        cpu: const CpuSample(busy: 50, total: 104600),
        gpus: [_gpu('a', 0, temperature: 40)],
      );
      expect(active.cpu.current, 0.5);
      expect(identical(active.gpus, settled.gpus), isTrue);
    },
  );

  test('settled GPU histories still publish device, order, and temperature changes', () {
    final model = SystemTelemetryModel();
    var current = const SystemTelemetrySnapshot();
    for (var i = 0; i < 45; i++) {
      current = _update(model, current, gpus: [_gpu('a', 0), _gpu('b', 0)]);
    }
    final a = current.gpus[0];
    final b = current.gpus[1];
    current = _update(model, current, gpus: [_gpu('b', 0), _gpu('a', 0)]);
    expect(identical(current.gpus[0], b), isTrue);
    expect(identical(current.gpus[1], a), isTrue);
    current = _update(
      model,
      current,
      gpus: [_gpu('b', 0, temperature: 60), _gpu('a', 0)],
    );
    expect(current.gpus.first.series.temperatureC, 60);
    expect(identical(current.gpus[1], a), isTrue);
    current = _update(model, current, gpus: [_gpu('b', 0, label: 'renamed')]);
    expect(current.gpus, hasLength(1));
    expect(current.gpus.single.label, 'renamed');
    current = _update(
      model,
      current,
      gpus: [
        _gpu('b', 0, label: 'renamed'),
        _gpu('c', 0),
      ],
    );
    expect(current.gpus.map((g) => g.id), ['b', 'c']);
  });

  test('arbitrary histories match the previous bounded append', () {
    final random = Random(383);
    for (var sample = 0; sample < 5000; sample++) {
      final history = List.generate(
        random.nextInt(250),
        (_) => random.nextDouble(),
      );
      final usage = random.nextDouble();
      final expected = [...history, usage];
      if (expected.length > 45) expected.removeRange(0, expected.length - 45);
      expect(LoadSeries(history: history).append(usage).history, expected);
    }
  });

  test('missing CPU reads preserve the counter anchor without publishing', () {
    final model = SystemTelemetryModel();
    var current = const SystemTelemetrySnapshot();
    final initial = current;
    current = _update(
      model,
      current,
      cpu: const CpuSample(busy: 20, total: 100),
    );
    expect(identical(current, initial), isTrue);
    current = _update(model, current);
    expect(identical(current, initial), isTrue);
    current = _update(
      model,
      current,
      cpu: const CpuSample(busy: 70, total: 200, temperatureC: 65),
    );
    expect(current.cpu.history, [0.5]);
    expect(current.cpu.temperatureC, 65);
  });

  test('invalid counters establish a new anchor without adding history', () {
    final model = SystemTelemetryModel();
    var current = const SystemTelemetrySnapshot();
    current = _update(
      model,
      current,
      cpu: const CpuSample(busy: 100, total: 200),
    );
    current = _update(
      model,
      current,
      cpu: const CpuSample(busy: 10, total: 20),
    );
    expect(current.cpu.history, isEmpty);
    current = _update(
      model,
      current,
      cpu: const CpuSample(busy: 40, total: 120),
    );
    expect(current.cpu.history, [0.3]);
    final restarted = SystemTelemetryModel();
    expect(
      identical(
        _update(restarted, current, cpu: const CpuSample(busy: 90, total: 200)),
        current,
      ),
      isTrue,
    );
  });

  test(
    'GPU histories follow identity when devices reorder, change, or disappear',
    () {
      final model = SystemTelemetryModel();
      var current = _update(
        model,
        const SystemTelemetrySnapshot(),
        gpus: [_gpu('a', 0.1, temperature: 40), _gpu('b', 0.2)],
      );
      final before = current;
      current = _update(
        model,
        current,
        gpus: [
          _gpu('b', 0.3),
          _gpu('a', 0.4, label: 'renamed'),
          _gpu('c', 0.5),
        ],
      );
      expect(current.gpus.map((g) => g.id), ['b', 'a', 'c']);
      expect(current.gpus[0].series.history, [0.2, 0.3]);
      expect(current.gpus[1].series.history, [0.1, 0.4]);
      expect(current.gpus[1].series.temperatureC, 40);
      expect(current.gpus[1].label, 'renamed');
      expect(current.gpus[2].series.history, [0.5]);
      expect(before.gpus[0].series.history, [0.1]);
      expect(() => current.gpus.clear(), throwsUnsupportedError);
      current = _update(model, current);
      expect(current.gpus, isEmpty);
      expect(identical(_update(model, current), current), isTrue);
    },
  );

  test(
    'one GPU retains its history and duplicate identities use the last match',
    () {
      final model = SystemTelemetryModel();
      var current = _update(
        model,
        const SystemTelemetrySnapshot(),
        gpus: [_gpu('a', 0.1)],
      );
      current = _update(model, current, gpus: [_gpu('a', 0.2)]);
      expect(current.gpus.single.series.history, [0.1, 0.2]);
      current = _update(model, current, gpus: [_gpu('a', 0.3), _gpu('a', 0.4)]);
      current = _update(model, current, gpus: [_gpu('a', 0.5)]);
      expect(current.gpus.single.series.history, [0.1, 0.2, 0.4, 0.5]);
      current = _update(model, current, gpus: [_gpu('b', 0.6)]);
      expect(current.gpus.single.series.history, [0.6]);
    },
  );

  test(
    'equal power data reuses the published state and its snapshot identity',
    () {
      final model = SystemTelemetryModel();
      final power = ShellPowerStatus.fromFields({
        'STATE': 'charging',
        'CAPACITY': '50',
      });
      final current = _update(
        model,
        const SystemTelemetrySnapshot(),
        power: power,
      );
      final same = ShellPowerStatus.fromFields({
        'STATE': 'charging',
        'CAPACITY': '50',
      });
      expect(identical(_update(model, current, power: same), current), isTrue);
      final withGpu = _update(
        model,
        current,
        power: same,
        gpus: [_gpu('a', 0.1)],
      );
      expect(identical(withGpu.power, power), isTrue);
    },
  );
}

GpuSample _gpu(
  String id,
  double usage, {
  String label = 'GPU',
  double? temperature,
}) => GpuSample(id: id, label: label, usage: usage, temperatureC: temperature);

SystemTelemetrySnapshot _update(
  SystemTelemetryModel model,
  SystemTelemetrySnapshot current, {
  CpuSample? cpu,
  List<GpuSample> gpus = const [],
  ShellPowerStatus power = ShellPowerStatus.unknown,
}) =>
    model.update(current, cpuSample: cpu, gpuSamples: gpus, powerStatus: power);
