import 'dart:async';

import 'package:denial_dart_shell/src/services/upower_service.dart';
import 'package:denial_dart_shell/src/state/upower.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'obsolete reads cannot clear the rebuilt controller refresh guard',
    () async {
      final first = _Backend();
      final second = _Backend();
      var active = first;
      final container = ProviderContainer(
        overrides: [upowerServiceProvider.overrideWith((ref) => active)],
      );
      final subscription = container.listen(upowerProvider, (_, _) {});
      try {
        final controller = container.read(upowerProvider.notifier);
        await container.pump();
        expect(first.requests, hasLength(1));
        active = second;
        container.invalidate(upowerServiceProvider);
        container.read(upowerProvider);
        await container.pump();
        expect(second.requests, hasLength(1));

        first.requests.single.complete(_snapshot('old'));
        await container.pump();
        await controller.refresh();
        expect(second.requests, hasLength(1));
        expect(container.read(upowerProvider).snapshot, isNull);

        second.requests.single.complete(_snapshot('new'));
        await container.pump();
        expect(container.read(upowerProvider).snapshot?.daemonVersion, 'new');
        final refreshed = controller.refresh();
        expect(second.requests, hasLength(2));
        second.requests.last.complete(_snapshot('latest'));
        await refreshed;
        expect(
          container.read(upowerProvider).snapshot?.daemonVersion,
          'latest',
        );
      } finally {
        subscription.close();
        container.dispose();
      }
    },
  );
}

UPowerSnapshot _snapshot(String version) => UPowerSnapshot(
  daemonVersion: version,
  onBattery: false,
  batteries: const [],
);

class _Backend implements UPowerBackend {
  final requests = <Completer<UPowerSnapshot>>[];
  @override
  Future<UPowerSnapshot> readSnapshot() {
    final request = Completer<UPowerSnapshot>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<void> setChargeThresholdEnabled(
    String objectPath,
    bool enabled,
  ) async {}

  @override
  Future<void> dispose() async {}
}
