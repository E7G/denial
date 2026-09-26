import 'dart:io';
import 'dart:math';

import 'package:denial_dart_shell/src/services/linux_cpu_usage.dart';
import 'package:denial_dart_shell/src/services/linux_gpu_usage.dart';
import 'package:test/test.dart';

void main() {
  test('CPU totals exclude guest counters and treat iowait as idle', () {
    final sample = parseProcStat(
      'cpu  100 2 30 400 5 6 7 8 90 1\ncpu0 1 2 3\nintr 999',
    );
    expect((sample!.busy, sample.total), (153, 558));
    expect(parseProcStat('cpu0 1 2 3\ncpu 1 2 3 4 5 6 7 8')!.total, 36);
    expect(parseProcStat('notcpu 1 2 3 4 5 6 7 8'), isNull);
    expect(parseProcStat(' cpu 1 2 3 4 5 6 7 8'), isNull);
  });

  test('CPU parser rejects incomplete or malformed aggregate rows', () {
    for (final content in [
      '',
      'cpu ',
      'cpu 1 2 3',
      'cpu 1 2 x 4 5 6 7 8',
      'cpu 1 2 3 4 5 6 7 8 bad',
      'cpu 1 2 3 4 5 6 7 99999999999999999999999999999',
      'cpu bad\ncpu 1 2 3 4 5 6 7 8',
    ]) {
      expect(parseProcStat(content), isNull, reason: content);
    }
    expect(parseProcStat('cpu  1 2 3 4 5 6 7 8\r\n')!.total, 36);
  });

  test('CPU parser matches previous semantics across randomized rows', () {
    final random = Random(190);
    for (var sample = 0; sample < 10000; sample++) {
      final count = random.nextInt(14);
      final fields = List.generate(
        count,
        (_) => random.nextInt(1000000).toString(),
      );
      if (fields.isNotEmpty && sample % 5 == 0) {
        fields[random.nextInt(fields.length)] = 'invalid';
      }
      final row =
          'cpu ${fields.join(' ' * (1 + random.nextInt(3)))}${sample.isEven ? '  ' : ''}';
      final content =
          '${sample % 3 == 0 ? 'cpu0 ignored\nbtime 1\n' : ''}$row${sample.isEven ? '\ncpu1 ignored\nintr 1 2 3' : ''}';
      final expected = _previousParseProcStat(content);
      final actual = parseProcStat(content);
      expect(
        actual == null ? null : (actual.busy, actual.total),
        expected == null ? null : (expected.busy, expected.total),
        reason: 'sample $sample',
      );
    }
  });

  test('counter deltas reject resets and clamp load', () {
    const previous = CpuSample(busy: 10, total: 20);
    expect(
      CpuSample.usageBetween(previous, const CpuSample(busy: 15, total: 30)),
      0.5,
    );
    expect(CpuSample.usageBetween(previous, previous), isNull);
    expect(
      CpuSample.usageBetween(previous, const CpuSample(busy: 5, total: 30)),
      isNull,
    );
    expect(
      CpuSample.usageBetween(previous, const CpuSample(busy: 50, total: 30)),
      1,
    );
  });

  test('temperature and GPU percentage parsers retain bounded values', () {
    expect(parseLinuxTemperatureC('42500\n'), 42.5);
    expect(parseLinuxTemperatureC('42.5'), 42.5);
    expect(parseLinuxTemperatureC('-25000'), -25);
    for (final value in ['NaN', 'Infinity', 'bad', '9999999']) {
      expect(parseLinuxTemperatureC(value), isNull);
    }
    expect(parseGpuBusyPercent(' 42\n'), 0.42);
    expect(parseGpuBusyPercent('101'), 1);
    expect(parseGpuBusyPercent('-2'), 0);
    expect(parseGpuBusyPercent('bad'), isNull);
  });

  group('temporary Linux sensor fixtures', () {
    late Directory root;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('denial-telemetry-');
    });
    tearDown(() async {
      await root.delete(recursive: true);
    });

    test(
      'overlapping CPU reads discover the sensor once and read fresh values',
      () async {
        final hwmon = await Directory('${root.path}/hwmon').create();
        final sensor = await Directory('${hwmon.path}/hwmon0').create();
        await _write('${sensor.path}/name', 'coretemp');
        await _write('${sensor.path}/temp1_label', 'Core 0');
        await _write('${sensor.path}/temp1_input', '30000');
        await _write('${sensor.path}/temp2_label', 'Package id 0');
        await _write('${sensor.path}/temp2_input', '42500');
        final directories = {
          hwmon.path: _CountingDirectory(hwmon),
          sensor.path: _CountingDirectory(sensor),
        };
        final reader = CpuTemperatureReader(
          hwmonRoot: hwmon.path,
          thermalRoot: '${root.path}/thermal',
        );
        final values = await IOOverrides.runZoned(
          () => Future.wait(List.generate(20, (_) => reader.read())),
          createDirectory: (path) => directories[path]!,
        );
        expect(values, everyElement(42.5));
        expect(directories[hwmon.path]!.listCount, 1);
        expect(directories[sensor.path]!.listCount, 1);
        await _write('${sensor.path}/temp2_input', '50000');
        expect(await reader.read(), 50);
        await File('${sensor.path}/temp2_input').delete();
        expect(await reader.read(), isNull);
      },
    );

    test('CPU thermal fallback prefers package sensors and tolerates missing files', () async {
      final thermal = await Directory('${root.path}/thermal').create();
      for (final (name, type, value) in [
        ('thermal_zone0', 'gpu', '80000'),
        ('thermal_zone1', 'cpu-thermal', '41000'),
        ('thermal_zone2', 'x86_pkg_temp', '43000'),
      ]) {
        final zone = await Directory('${thermal.path}/$name').create();
        await _write('${zone.path}/type', type);
        await _write('${zone.path}/temp', value);
      }
      final reader = CpuTemperatureReader(
        hwmonRoot: '${root.path}/missing',
        thermalRoot: thermal.path,
      );
      expect(await reader.read(), 43);
      final unavailable = CpuTemperatureReader(
        hwmonRoot: '${root.path}/missing',
        thermalRoot: '${root.path}/missing',
      );
      expect(await unavailable.read(), isNull);
    });

    test('CPU service combines counters with the selected sensor', () async {
      final statPath = '${root.path}/stat';
      await _write(statPath, 'cpu 1 2 3 4 5 6 7 8');
      final service = CpuUsageService(
        statPath: statPath,
        hwmonRoot: '${root.path}/missing',
        thermalRoot: '${root.path}/missing',
      );
      final sample = await service.read();
      expect((sample!.busy, sample.total, sample.temperatureC), (27, 36, null));
      await File(statPath).delete();
      expect(await service.read(), isNull);
    });

    test('overlapping GPU reads share discovery and never query a sleeping NVIDIA GPU', () async {
      final drm = await Directory('${root.path}/drm').create();
      final device = await Directory('${drm.path}/card0/device/power')
          .create(recursive: true);
      await _write('${device.parent.path}/vendor', '0x10de');
      final statusPath = '${device.path}/runtime_status';
      await _write(statusPath, 'suspended');
      final nvml = _FakeNvmlReader();
      final service = GpuUsageService(drmRoot: drm.path, nvml: nvml);
      final directory = _CountingDirectory(drm);
      final samples = await IOOverrides.runZoned(
        () => Future.wait(List.generate(20, (_) => service.read())),
        createDirectory: (path) {
          expect(path, drm.path);
          return directory;
        },
      );
      expect(directory.listCount, 1);
      expect(nvml.reads, 0);
      expect(
        samples.every((s) => s.single.id == 'nvml0' && s.single.usage == 0),
        isTrue,
      );
      await _write(statusPath, 'active');
      expect((await service.read()).single.usage, 0.75);
      expect(nvml.reads, 1);
    });

    test(
      'GPU sysfs samples preserve utilization and optional temperature',
      () async {
        final drm = await Directory('${root.path}/drm').create();
        final sensor = await Directory('${drm.path}/card1/device/hwmon/hwmon0')
            .create(recursive: true);
        final device = sensor.parent.parent;
        await _write('${device.path}/vendor', '0x1002');
        await _write('${device.path}/gpu_busy_percent', '42');
        await _write('${sensor.path}/temp1_label', 'edge');
        await _write('${sensor.path}/temp1_input', '56000');
        final service = GpuUsageService(
          drmRoot: drm.path,
          nvml: _FakeNvmlReader(),
        );
        final sample = (await service.read()).first;
        expect(
          (sample.id, sample.label, sample.usage, sample.temperatureC),
          ('card1', 'AMD', 0.42, 56),
        );
        await File('${sensor.path}/temp1_input').delete();
        expect((await service.read()).first.temperatureC, isNull);
      },
    );
  });
}

Future<void> _write(String path, String value) =>
    File(path).writeAsString(value);

class _CountingDirectory implements Directory {
  _CountingDirectory(this.delegate);
  final Directory delegate;
  int listCount = 0;
  @override
  String get path => delegate.path;
  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) {
    listCount++;
    return delegate.list(recursive: recursive, followLinks: followLinks);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNvmlReader extends NvmlReader {
  int reads = 0;
  @override
  Future<List<GpuSample>> read() async {
    reads++;
    return const [GpuSample(id: 'nvml0', label: 'NV', usage: 0.75)];
  }
}

CpuSample? _previousParseProcStat(String content) {
  for (final line in content.split('\n')) {
    if (!line.startsWith('cpu ')) continue;
    final fields = line
        .split(' ')
        .where((field) => field.isNotEmpty)
        .skip(1)
        .map(int.tryParse)
        .toList(growable: false);
    if (fields.length < 8 || fields.any((field) => field == null)) return null;
    final jiffies = fields.take(8).cast<int>().toList(growable: false);
    final total = jiffies.fold<int>(0, (sum, value) => sum + value);
    return CpuSample(busy: total - jiffies[3] - jiffies[4], total: total);
  }
  return null;
}
