import 'package:denial_dart_shell/src/launcher/controllers/home_grid_layout.dart';
import 'package:denial_dart_shell/src/launcher/models/desktop_app.dart';
import 'package:denial_dart_shell/src/launcher/models/home_grid_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final originalColumns = HomeGridLayout.columns;
  tearDown(() => HomeGridLayout.columns = originalColumns);

  test('saved battery widget is removed without moving retained widgets', () {
    HomeGridLayout.columns = 4;
    final slots = HomeGridLayout.initialSlotsForApps([], [], [
      const HomeLayoutSlot(
        id: 'widget:battery-discharge',
        colSpan: 4,
        rowSpan: 2,
      ),
      for (var i = 1; i < 8; i++) null,
      const HomeLayoutSlot(id: 'widget:clock', colSpan: 3, rowSpan: 2),
    ]);
    expect(slots.whereType<HomeGridItem>().map((item) => item.id), [
      'widget:clock',
    ]);
    expect(slots[8]!.colSpan, 3);
    expect(slots[8]!.rowSpan, 2);
    expect(slots.take(8), everyElement(isNull));
  });

  test('application tile size survives application refresh', () {
    HomeGridLayout.columns = 4;
    const app = DesktopApp(
      id: 'org.example.Metro',
      name: 'Metro',
      exec: 'metro',
      desktopPath: '/usr/share/applications/metro.desktop',
      categories: <String>[],
    );
    final current = <HomeGridItem?>[
      HomeGridItem.app(app, colSpan: 2, rowSpan: 2),
    ];
    final refreshed = HomeGridLayout.refreshSlotsForApps(
      current,
      const <DesktopApp>[app],
      const [],
    );

    expect(refreshed.first, isNotNull);
    expect(refreshed.first!.id, 'app:org.example.Metro');
    expect(refreshed.first!.colSpan, 2);
    expect(refreshed.first!.rowSpan, 2);
  });

  test('application tiles expose Square Home style resize bounds', () {
    const app = DesktopApp(
      id: 'org.example.Tile',
      name: 'Tile',
      exec: 'tile',
      desktopPath: '/usr/share/applications/tile.desktop',
      categories: <String>[],
    );
    final item = HomeGridItem.app(app);

    expect(item.resizable, isTrue);
    expect(item.resize(colSpan: 2, rowSpan: 2).colSpan, 2);
    expect(item.resize(colSpan: 2, rowSpan: 2).rowSpan, 2);
    expect(item.resize(colSpan: 9, rowSpan: 9).colSpan, 2);
    expect(item.resize(colSpan: 9, rowSpan: 9).rowSpan, 2);
  });

  test('saved Start layout stays authoritative when new apps appear', () {
    HomeGridLayout.columns = 4;
    const pinned = DesktopApp(
      id: 'org.example.Pinned',
      name: 'Pinned',
      exec: 'pinned',
      desktopPath: '/usr/share/applications/pinned.desktop',
      categories: <String>[],
    );
    const newlyInstalled = DesktopApp(
      id: 'org.example.New',
      name: 'New',
      exec: 'new',
      desktopPath: '/usr/share/applications/new.desktop',
      categories: <String>[],
    );

    final slots = HomeGridLayout.initialSlotsForApps(
      const <DesktopApp>[pinned, newlyInstalled],
      const [],
      const <HomeLayoutSlot?>[
        HomeLayoutSlot(
          id: 'app:org.example.Pinned',
          colSpan: 2,
          rowSpan: 1,
          tileColorValue: 0xff5c2d91,
        ),
      ],
    );

    final items = slots.whereType<HomeGridItem>().toList(growable: false);
    expect(items.map((item) => item.id), <String>['app:org.example.Pinned']);
    expect(items.single.colSpan, 2);
    expect(items.single.rowSpan, 1);
    expect(items.single.tileColorValue, 0xff5c2d91);
  });

  test('first run creates live system tiles and only a starter app set', () {
    HomeGridLayout.columns = 4;
    final apps = <DesktopApp>[
      for (var index = 0; index < 12; index++)
        DesktopApp(
          id: 'org.example.$index',
          name: 'App $index',
          exec: 'app-$index',
          desktopPath: '/usr/share/applications/app-$index.desktop',
          categories: const <String>[],
        ),
    ];

    final slots = HomeGridLayout.initialSlotsForApps(apps, const [], null);
    final ids = slots
        .whereType<HomeGridItem>()
        .map((item) => item.id)
        .toList(growable: false);

    expect(ids.take(4), <String>[
      'widget:clock',
      'widget:date',
      'widget:battery',
      'widget:network',
    ]);
    expect(ids.where((id) => id.startsWith('app:')).length, 8);
    expect(ids, isNot(contains('app:org.example.11')));
  });

  test('application refresh does not auto-pin newly installed apps', () {
    HomeGridLayout.columns = 4;
    const pinned = DesktopApp(
      id: 'org.example.Pinned',
      name: 'Pinned',
      exec: 'pinned',
      desktopPath: '/usr/share/applications/pinned.desktop',
      categories: <String>[],
    );
    const newlyInstalled = DesktopApp(
      id: 'org.example.New',
      name: 'New',
      exec: 'new',
      desktopPath: '/usr/share/applications/new.desktop',
      categories: <String>[],
    );

    final refreshed = HomeGridLayout.refreshSlotsForApps(
      <HomeGridItem?>[HomeGridItem.app(pinned)],
      const <DesktopApp>[pinned, newlyInstalled],
      const [],
    );

    expect(refreshed.whereType<HomeGridItem>().map((item) => item.id), <String>[
      'app:org.example.Pinned',
    ]);
  });

  test('bounded hit lookup matches occupied cells for every widget span', () {
    for (final columns in [4, 7, 14]) {
      HomeGridLayout.columns = columns;
      for (var width = 2; width <= 4; width++) {
        for (var height = 1; height <= 3; height++) {
          for (var anchor = 0; anchor < columns * 5; anchor++) {
            final item = HomeGridItem.clock(colSpan: width, rowSpan: height);
            if (!HomeGridLayout.itemFitsAtColumn(item, anchor)) continue;
            final cells = HomeGridLayout.cellsFor(anchor, item).toSet();
            final slots = List<HomeGridItem?>.filled(anchor + 1, null)
              ..[anchor] = item;
            for (var cell = -1; cell < columns * 8; cell++) {
              expect(
                HomeGridLayout.anchorForCell(cell, slots),
                cells.contains(cell) ? anchor : null,
              );
            }
            final pageSize = columns * 3;
            expect(
              HomeGridLayout.itemFitsInPage(anchor, item, pageSize),
              cells.every((cell) => cell ~/ pageSize == anchor ~/ pageSize),
            );
          }
        }
      }
    }
  });
}
