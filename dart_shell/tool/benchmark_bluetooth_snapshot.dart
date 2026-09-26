import 'dart:io';

import 'package:denial_dart_shell/src/services/bluetooth_backend.dart';

import '../test/support/bluetooth_fixtures.dart';
import '../test/support/legacy_bluetooth_snapshot.dart';

void main() {
  var checksum = 0;
  for (final (count, tied) in [
    (16, false),
    (128, false),
    (512, false),
    (2048, false),
    (2048, true),
  ]) {
    final managed = bluetoothObjects(count, seed: 919, tied: tied);
    final iterations = count > 128 ? 100 : 1000;
    double measure(bool optimized) {
      final watch = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        final result = optimized
            // This tool measures the same pure parser exercised by tests.
            // ignore: invalid_use_of_visible_for_testing_member
            ? buildBluetoothSnapshot(managed)
            : legacyBluetoothSnapshot(managed);
        checksum += result.devices.length + result.devices.first.name.length;
      }
      watch.stop();
      return watch.elapsedTicks * 1e6 / watch.frequency / iterations;
    }

    measure(false);
    measure(true);
    final before = <double>[];
    final after = <double>[];
    for (var sample = 0; sample < 7; sample++) {
      if (sample.isEven) {
        before.add(measure(false));
        after.add(measure(true));
      } else {
        after.add(measure(true));
        before.add(measure(false));
      }
    }
    before.sort();
    after.sort();
    stdout.writeln(
      '$count devices${tied ? " (tied)" : ""}: ${before[3].toStringAsFixed(2)} → ${after[3].toStringAsFixed(2)} µs (${(before[3] / after[3]).toStringAsFixed(2)}x)',
    );
  }
  stdout.writeln('checksum: $checksum');
}
