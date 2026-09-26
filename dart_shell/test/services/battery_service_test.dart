import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:denial_dart_shell/src/models/battery_status.dart';
import 'package:denial_dart_shell/src/services/battery_service.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Map<String, String> attributes;
  late List<String> reads;
  late BatteryService service;

  Future<void> supply(String name, Map<String, String> values) async {
    final directory = await Directory('${root.path}/$name').create();
    for (final entry in values.entries) {
      attributes['${directory.path}/${entry.key}'] = entry.value;
    }
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('denial-battery-test-');
    attributes = {};
    reads = [];
    service = BatteryService(
      powerSupplyRoot: root.path,
      readAttribute: (path) async {
        reads.add(path);
        return attributes[path];
      },
    );
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'energy weights take precedence without reading charge fallback',
    () async {
      await supply('BAT0', {
        'type': 'Battery',
        'present': '1',
        'capacity': '10',
        'energy_full': '3',
        'charge_full': '1000',
        'status': 'Charging',
      });
      await supply('BAT1', {
        'type': 'Battery',
        'capacity': '90',
        'energy_full': '1',
        'charge_full': '1000',
        'status': 'Discharging',
      });
      expect(
        await service.read(),
        const BatteryStatus(capacity: 30, charging: true),
      );
      expect(reads, hasLength(10));
      expect(reads.any((path) => path.endsWith('/charge_full')), isFalse);
    },
  );

  test('missing or invalid energy falls back to charge weights', () async {
    await supply('BAT0', {
      'type': 'Battery',
      'capacity': '10',
      'energy_full': '-1',
      'charge_full': '1',
    });
    await supply('BAT1', {
      'type': 'Battery',
      'capacity': '90',
      'charge_full': '3',
    });
    expect(
      await service.read(),
      const BatteryStatus(capacity: 70, charging: false),
    );
    expect(reads.where((p) => p.endsWith('/charge_full')), hasLength(2));
  });

  test(
    'mixed weight dimensions use an unweighted measurable average',
    () async {
      await supply('BAT0', {
        'type': 'Battery',
        'capacity': '10',
        'energy_full': '90000',
      });
      await supply('BAT1', {
        'type': 'Battery',
        'capacity': '90',
        'charge_full': '3',
      });
      await supply('placeholder', {
        'type': 'Battery',
        'capacity': '0',
        'status': 'Charging',
      });
      expect(
        await service.read(),
        const BatteryStatus(capacity: 50, charging: false),
      );
    },
  );

  test(
    'unmeasurable batteries are retained when no measured ones exist',
    () async {
      await supply('BAT0', {'type': 'Battery', 'capacity': '10'});
      await supply('BAT1', {
        'type': 'Battery',
        'capacity': '91',
        'status': 'Charging',
      });
      expect(
        await service.read(),
        const BatteryStatus(capacity: 51, charging: true),
      );
    },
  );

  test(
    'non-battery and absent supplies stop before reading capacity',
    () async {
      await supply('AC', {'type': 'Mains'});
      await supply('BAT0', {'type': 'Battery', 'present': '0'});
      expect(await service.read(), BatteryStatus.unknown);
      expect(reads, hasLength(3));
      expect(reads.any((path) => path.endsWith('/capacity')), isFalse);
    },
  );

  test(
    'capacity, weight, and status reads overlap after presence check',
    () async {
      await supply('BAT0', {'type': 'Battery', 'present': '1'});
      final gates = {
        'capacity': Completer<String?>(),
        'energy_full': Completer<String?>(),
        'status': Completer<String?>(),
      };
      final allStarted = Completer<void>();
      final started = <String>{};
      service = BatteryService(
        powerSupplyRoot: root.path,
        readAttribute: (path) async {
          final name = path.substring(path.lastIndexOf('/') + 1);
          if (gates[name] case final gate?) {
            started.add(name);
            if (started.length == 3) allStarted.complete();
            return gate.future;
          }
          return attributes[path];
        },
      );
      final read = service.read();
      await allStarted.future.timeout(const Duration(seconds: 2));
      gates['capacity']!.complete('42');
      gates['energy_full']!.complete('100');
      gates['status']!.complete('Charging');
      expect(await read, const BatteryStatus(capacity: 42, charging: true));
    },
  );

  test(
    'the real sysfs reader trims values and tolerates missing nodes',
    () async {
      final directory = await Directory('${root.path}/BAT0').create();
      for (final (name, text) in [
        ('type', 'Battery\n'),
        ('capacity', ' 64\n'),
        ('status', 'Charging\n'),
      ]) {
        await File('${directory.path}/$name').writeAsString(text);
      }
      final real = BatteryService(powerSupplyRoot: root.path);
      expect(
        await real.read(),
        const BatteryStatus(capacity: 64, charging: true),
      );
      await File('${directory.path}/capacity').writeAsString('101\n');
      expect(await real.read(), BatteryStatus.unknown);
      expect(
        await BatteryService(powerSupplyRoot: '${root.path}/missing').read(),
        BatteryStatus.unknown,
      );
    },
  );

  test(
    'random supply combinations match the previous aggregation rules',
    () async {
      for (var i = 0; i < 6; i++) {
        await supply('BAT$i', {});
      }
      final random = Random(911);
      for (var sample = 0; sample < 1000; sample++) {
        attributes.clear();
        final valid =
            <({int capacity, bool charging, int? weight, bool energy})>[];
        for (var i = 0; i < 6; i++) {
          final isBattery = random.nextInt(5) != 0;
          final present = random.nextInt(5) != 0;
          final capacity = random.nextInt(105) - 2;
          final charging = random.nextBool();
          final energy = random.nextInt(5) - 1;
          final charge = random.nextInt(5) - 1;
          final prefix = '${root.path}/BAT$i';
          attributes.addAll({
            '$prefix/type': isBattery ? 'Battery' : 'Mains',
            '$prefix/present': present ? '1' : '0',
            '$prefix/capacity': '$capacity',
            '$prefix/status': charging ? 'Charging' : 'Discharging',
            '$prefix/energy_full': '$energy',
            '$prefix/charge_full': '$charge',
          });
          if (isBattery && present && capacity >= 0 && capacity <= 100) {
            valid.add((
              capacity: capacity,
              charging: charging,
              weight: energy > 0
                  ? energy
                  : charge > 0
                  ? charge
                  : null,
              energy: energy > 0,
            ));
          }
        }
        final measured = valid.where((s) => s.weight != null).toList();
        final selected = measured.isEmpty ? valid : measured;
        final weighted =
            measured.isNotEmpty &&
            measured.map((s) => s.energy).toSet().length == 1;
        final expected = selected.isEmpty
            ? BatteryStatus.unknown
            : BatteryStatus(
                capacity: weighted
                    ? (selected.fold<int>(
                                0,
                                (sum, s) => sum + s.capacity * s.weight!,
                              ) /
                              selected.fold<int>(
                                0,
                                (sum, s) => sum + s.weight!,
                              ))
                          .round()
                    : (selected.fold<int>(0, (sum, s) => sum + s.capacity) /
                              selected.length)
                          .round(),
                charging: selected.any((s) => s.charging),
              );
        expect(await service.read(), expected, reason: 'sample $sample');
      }
    },
  );
}
