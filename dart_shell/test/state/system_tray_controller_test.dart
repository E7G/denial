import 'dart:async';

import 'package:denial_dart_shell/src/models/system_tray_item.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/services/status_notifier_service.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/system_tray.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unchanged tray events reuse state without notifying consumers',
    () async {
      final bridge = _Bridge();
      final service = _Service([_item('a')]);
      final container = ProviderContainer(
        overrides: [
          denialBridgeProvider.overrideWithValue(bridge),
          statusNotifierServiceProvider.overrideWithValue(service),
        ],
      );
      var changes = 0;
      final subscription = container.listen(
        systemTrayProvider,
        (_, _) => changes++,
      );
      try {
        final initial = container.read(systemTrayProvider);
        expect(identical(initial, service.current), isTrue);
        service.started.complete();
        await container.pump();
        service.events.add(List.unmodifiable(service.current));
        bridge.events.add(
          const XEmbedTrayEvent(
            kind: XEmbedTrayEventKind.removed,
            windowId: 42,
          ),
        );
        expect(identical(container.read(systemTrayProvider), initial), isTrue);
        expect(changes, 0);
      } finally {
        subscription.close();
        container.dispose();
        await service.dispose();
        await bridge.events.close();
      }
    },
  );

  test(
    'an obsolete startup cannot publish through a rebuilt controller',
    () async {
      final bridge = _Bridge();
      final first = _Service([_item('old')]);
      final second = _Service([_item('new')]);
      var active = first;
      final container = ProviderContainer(
        overrides: [
          denialBridgeProvider.overrideWithValue(bridge),
          statusNotifierServiceProvider.overrideWith((ref) => active),
        ],
      );
      final subscription = container.listen(systemTrayProvider, (_, _) {});
      try {
        await container.pump();
        active = second;
        container.invalidate(statusNotifierServiceProvider);
        final rebuilt = container.read(systemTrayProvider);
        await container.pump();
        expect(rebuilt.single.id, 'new');
        second.current = List.unmodifiable([_item('not-ready')]);
        first.started.complete();
        await container.pump();
        expect(identical(container.read(systemTrayProvider), rebuilt), isTrue);
        second.started.complete();
        await container.pump();
        expect(container.read(systemTrayProvider).single.id, 'not-ready');
      } finally {
        subscription.close();
        container.dispose();
        await first.dispose();
        await second.dispose();
        await bridge.events.close();
      }
    },
  );
}

class _Bridge implements DenialBridge {
  final events = StreamController<XEmbedTrayEvent>.broadcast(sync: true);
  @override
  Map<int, SystemTrayItem> get xembedTrayItems => const {};
  @override
  Stream<XEmbedTrayEvent> get xembedTrayEvents => events.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service implements StatusNotifierService {
  _Service(List<SystemTrayItem> initial) : current = List.unmodifiable(initial);
  final events = StreamController<List<SystemTrayItem>>.broadcast(sync: true);
  final started = Completer<void>();
  @override
  List<SystemTrayItem> current;
  @override
  Stream<List<SystemTrayItem>> get snapshots => events.stream;
  @override
  Future<void> start() => started.future;
  @override
  Future<void> dispose() => events.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SystemTrayItem _item(String id) => SystemTrayItem(
  id: id,
  source: SystemTrayItemSource.statusNotifier,
  title: id,
  status: SystemTrayStatus.active,
  iconName: '',
  iconThemePath: '',
  iconPixmap: null,
  menuAvailable: false,
  primaryOpensMenu: false,
);
