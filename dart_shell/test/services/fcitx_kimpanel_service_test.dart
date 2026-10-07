import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:denial_dart_shell/src/services/fcitx_kimpanel_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DBusServer bus;
  late DBusClient shellClient;
  late DBusClient fcitxClient;
  late FcitxKimpanelService service;
  late _FakeFcitxKimpanelEndpoint fcitxEndpoint;

  setUp(() async {
    bus = DBusServer();
    final address = await bus.listenAddress(
      DBusAddress.unix(dir: Directory.systemTemp),
    );
    shellClient = DBusClient(address);
    fcitxClient = DBusClient(address);
    fcitxEndpoint = _FakeFcitxKimpanelEndpoint();
    await fcitxClient.registerObject(fcitxEndpoint);
    service = FcitxKimpanelService(client: shellClient);
  });

  tearDown(() async {
    await service.dispose();
    await fcitxClient.unregisterObject(fcitxEndpoint);
    await fcitxClient.close();
    await shellClient.close();
    await bus.close();
  });

  test('structured lookup table is exposed without a popup surface', () async {
    await fcitxClient.requestName('org.kde.kimpanel.inputmethod');
    await service.start();

    final panel = DBusRemoteObject(
      fcitxClient,
      name: 'org.kde.impanel',
      path: DBusObjectPath('/org/kde/impanel'),
    );
    await panel.callMethod('org.kde.impanel2', 'SetLookupTable', <DBusValue>[
      DBusArray.string(const <String>['1', '2', '3']),
      DBusArray.string(const <String>['你好', '你', '拟好']),
      DBusArray.string(const <String>['', '', '']),
      const DBusBoolean(true),
      const DBusBoolean(true),
      const DBusInt32(1),
      const DBusInt32(2),
    ], replySignature: DBusSignature(''));

    expect(service.current.available, isTrue);
    expect(service.current.visible, isTrue);
    expect(service.current.items.map((item) => item.text), <String>[
      '你好',
      '你',
      '拟好',
    ]);
    expect(service.current.items[1].label, '2');
    expect(service.current.cursor, 1);
    expect(service.current.hasPrevious, isTrue);
    expect(service.current.hasNext, isTrue);

    final hidden = service.snapshots
        .firstWhere((snapshot) => !snapshot.visible)
        .timeout(const Duration(seconds: 2));
    await fcitxEndpoint.showLookupTable(false);
    await hidden;
    expect(service.current.visible, isFalse);
    expect(service.current.items, hasLength(3));
  });

  test('selection and paging are returned through Kimpanel signals', () async {
    await fcitxClient.requestName('org.kde.kimpanel.inputmethod');
    await service.start();

    final panel = DBusRemoteObject(
      fcitxClient,
      name: 'org.kde.impanel',
      path: DBusObjectPath('/org/kde/impanel'),
    );
    await panel.callMethod('org.kde.impanel2', 'SetLookupTable', <DBusValue>[
      DBusArray.string(const <String>['1', '2']),
      DBusArray.string(const <String>['候选一', '候选二']),
      DBusArray.string(const <String>['', '']),
      const DBusBoolean(true),
      const DBusBoolean(true),
      const DBusInt32(0),
      const DBusInt32(2),
    ], replySignature: DBusSignature(''));

    final signals = DBusSignalStream(
      fcitxClient,
      path: DBusObjectPath('/org/kde/impanel'),
      interface: 'org.kde.impanel',
    ).asBroadcastStream();

    final selected = signals
        .firstWhere((signal) => signal.name == 'SelectCandidate')
        .timeout(const Duration(seconds: 2));
    await service.selectCandidate(1);
    final selectedSignal = await selected;
    expect(selectedSignal.values.single.asInt32(), 1);

    final pageUp = signals
        .firstWhere((signal) => signal.name == 'LookupTablePageUp')
        .timeout(const Duration(seconds: 2));
    await service.previousPage();
    await pageUp;

    final pageDown = signals
        .firstWhere((signal) => signal.name == 'LookupTablePageDown')
        .timeout(const Duration(seconds: 2));
    await service.nextPage();
    await pageDown;
  });

  test(
    'late Fcitx Kimpanel startup receives a fresh panel handshake',
    () async {
      await service.start();

      final panelCreated = DBusSignalStream(
        fcitxClient,
        path: DBusObjectPath('/org/kde/impanel'),
        interface: 'org.kde.impanel',
        name: 'PanelCreated',
      ).first.timeout(const Duration(seconds: 2));

      final panelCreated2 = DBusSignalStream(
        fcitxClient,
        path: DBusObjectPath('/org/kde/impanel'),
        interface: 'org.kde.impanel2',
        name: 'PanelCreated2',
      ).first.timeout(const Duration(seconds: 2));

      await fcitxClient.requestName('org.kde.kimpanel.inputmethod');
      await Future.wait(<Future<DBusSignal>>[panelCreated, panelCreated2]);
    },
  );
}

class _FakeFcitxKimpanelEndpoint extends DBusObject {
  _FakeFcitxKimpanelEndpoint() : super(DBusObjectPath('/kimpanel'));

  Future<void> showLookupTable(bool visible) {
    return emitSignal(
      'org.kde.kimpanel.inputmethod',
      'ShowLookupTable',
      <DBusValue>[DBusBoolean(visible)],
    );
  }

  @override
  List<DBusIntrospectInterface> introspect() => <DBusIntrospectInterface>[
    DBusIntrospectInterface(
      'org.kde.kimpanel.inputmethod',
      signals: <DBusIntrospectSignal>[
        DBusIntrospectSignal(
          'ShowLookupTable',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('b'),
              DBusArgumentDirection.out,
            ),
          ],
        ),
      ],
    ),
  ];
}
