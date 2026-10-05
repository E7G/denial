import '../../local_apps/local_flutter_application.dart';
import 'desktop_app.dart';

enum HomeGridItemType { clock, date, battery, network, app }

class HomeLayoutSlot {
  const HomeLayoutSlot({
    required this.id,
    this.colSpan,
    this.rowSpan,
    this.tileColorValue,
  });

  final String id;
  final int? colSpan;
  final int? rowSpan;
  final int? tileColorValue;
}

class HomeGridItem {
  const HomeGridItem._({
    required this.type,
    required this.id,
    required this.colSpan,
    required this.rowSpan,
    required this.app,
    required this.localApp,
    this.tileColorValue,
  });

  factory HomeGridItem.clock({
    int colSpan = defaultClockColSpan,
    int rowSpan = defaultClockRowSpan,
    int? tileColorValue,
  }) {
    return HomeGridItem._(
      type: HomeGridItemType.clock,
      id: 'widget:clock',
      colSpan: colSpan.clamp(clockMinColSpan, clockMaxColSpan).toInt(),
      rowSpan: rowSpan.clamp(clockMinRowSpan, clockMaxRowSpan).toInt(),
      app: null,
      localApp: null,
      tileColorValue: tileColorValue,
    );
  }

  factory HomeGridItem.date({
    int colSpan = defaultDateColSpan,
    int rowSpan = defaultDateRowSpan,
    int? tileColorValue,
  }) {
    return HomeGridItem._(
      type: HomeGridItemType.date,
      id: 'widget:date',
      colSpan: colSpan.clamp(systemMinColSpan, systemMaxColSpan).toInt(),
      rowSpan: rowSpan.clamp(systemMinRowSpan, systemMaxRowSpan).toInt(),
      app: null,
      localApp: null,
      tileColorValue: tileColorValue,
    );
  }

  factory HomeGridItem.battery({
    int colSpan = defaultBatteryColSpan,
    int rowSpan = defaultBatteryRowSpan,
    int? tileColorValue,
  }) {
    return HomeGridItem._(
      type: HomeGridItemType.battery,
      id: 'widget:battery',
      colSpan: colSpan.clamp(systemMinColSpan, systemMaxColSpan).toInt(),
      rowSpan: rowSpan.clamp(systemMinRowSpan, systemMaxRowSpan).toInt(),
      app: null,
      localApp: null,
      tileColorValue: tileColorValue,
    );
  }

  factory HomeGridItem.network({
    int colSpan = defaultNetworkColSpan,
    int rowSpan = defaultNetworkRowSpan,
    int? tileColorValue,
  }) {
    return HomeGridItem._(
      type: HomeGridItemType.network,
      id: 'widget:network',
      colSpan: colSpan.clamp(systemMinColSpan, systemMaxColSpan).toInt(),
      rowSpan: rowSpan.clamp(systemMinRowSpan, systemMaxRowSpan).toInt(),
      app: null,
      localApp: null,
      tileColorValue: tileColorValue,
    );
  }

  factory HomeGridItem.app(
    DesktopApp desktopApp, {
    int colSpan = defaultAppColSpan,
    int rowSpan = defaultAppRowSpan,
    int? tileColorValue,
  }) {
    return HomeGridItem._(
      type: HomeGridItemType.app,
      id: 'app:${desktopApp.id}',
      colSpan: colSpan.clamp(appMinColSpan, appMaxColSpan).toInt(),
      rowSpan: rowSpan.clamp(appMinRowSpan, appMaxRowSpan).toInt(),
      app: desktopApp,
      localApp: null,
      tileColorValue: tileColorValue,
    );
  }

  factory HomeGridItem.localApp(
    LocalFlutterApplication localApp, {
    int colSpan = defaultAppColSpan,
    int rowSpan = defaultAppRowSpan,
    int? tileColorValue,
  }) {
    return HomeGridItem._(
      type: HomeGridItemType.app,
      id: 'local:${localApp.id}',
      colSpan: colSpan.clamp(appMinColSpan, appMaxColSpan).toInt(),
      rowSpan: rowSpan.clamp(appMinRowSpan, appMaxRowSpan).toInt(),
      app: null,
      localApp: localApp,
      tileColorValue: tileColorValue,
    );
  }

  static const int defaultAppColSpan = 1;
  static const int defaultAppRowSpan = 1;
  static const int appMinColSpan = 1;
  static const int appMaxColSpan = 2;
  static const int appMinRowSpan = 1;
  static const int appMaxRowSpan = 2;

  static const int defaultClockColSpan = 2;
  static const int defaultClockRowSpan = 1;
  static const int clockMinColSpan = 2;
  static const int clockMaxColSpan = 4;
  static const int clockMinRowSpan = 1;
  static const int clockMaxRowSpan = 3;

  static const int defaultDateColSpan = 1;
  static const int defaultDateRowSpan = 1;
  static const int defaultBatteryColSpan = 1;
  static const int defaultBatteryRowSpan = 1;
  static const int defaultNetworkColSpan = 1;
  static const int defaultNetworkRowSpan = 1;
  static const int systemMinColSpan = 1;
  static const int systemMaxColSpan = 2;
  static const int systemMinRowSpan = 1;
  static const int systemMaxRowSpan = 2;

  final HomeGridItemType type;
  final String id;
  final int colSpan;
  final int rowSpan;
  final DesktopApp? app;
  final LocalFlutterApplication? localApp;

  /// Optional ARGB override. Null means use the deterministic Metro palette.
  final int? tileColorValue;

  bool get resizable => true;
  bool get isApplication => type == HomeGridItemType.app;
  bool get isSystemTile => !isApplication;

  int get minColSpan => switch (type) {
    HomeGridItemType.clock => clockMinColSpan,
    HomeGridItemType.date ||
    HomeGridItemType.battery ||
    HomeGridItemType.network => systemMinColSpan,
    HomeGridItemType.app => appMinColSpan,
  };

  int get maxColSpan => switch (type) {
    HomeGridItemType.clock => clockMaxColSpan,
    HomeGridItemType.date ||
    HomeGridItemType.battery ||
    HomeGridItemType.network => systemMaxColSpan,
    HomeGridItemType.app => appMaxColSpan,
  };

  int get minRowSpan => switch (type) {
    HomeGridItemType.clock => clockMinRowSpan,
    HomeGridItemType.date ||
    HomeGridItemType.battery ||
    HomeGridItemType.network => systemMinRowSpan,
    HomeGridItemType.app => appMinRowSpan,
  };

  int get maxRowSpan => switch (type) {
    HomeGridItemType.clock => clockMaxRowSpan,
    HomeGridItemType.date ||
    HomeGridItemType.battery ||
    HomeGridItemType.network => systemMaxRowSpan,
    HomeGridItemType.app => appMaxRowSpan,
  };

  HomeGridItem resize({required int colSpan, required int rowSpan}) {
    return _copy(
      colSpan: colSpan.clamp(minColSpan, maxColSpan).toInt(),
      rowSpan: rowSpan.clamp(minRowSpan, maxRowSpan).toInt(),
    );
  }

  HomeGridItem withTileColor(int? value) => _copy(tileColorValue: value);

  HomeGridItem _copy({
    int? colSpan,
    int? rowSpan,
    Object? tileColorValue = _homeUnset,
  }) {
    final color = identical(tileColorValue, _homeUnset)
        ? this.tileColorValue
        : tileColorValue as int?;
    return switch (type) {
      HomeGridItemType.clock => HomeGridItem.clock(
        colSpan: colSpan ?? this.colSpan,
        rowSpan: rowSpan ?? this.rowSpan,
        tileColorValue: color,
      ),
      HomeGridItemType.date => HomeGridItem.date(
        colSpan: colSpan ?? this.colSpan,
        rowSpan: rowSpan ?? this.rowSpan,
        tileColorValue: color,
      ),
      HomeGridItemType.battery => HomeGridItem.battery(
        colSpan: colSpan ?? this.colSpan,
        rowSpan: rowSpan ?? this.rowSpan,
        tileColorValue: color,
      ),
      HomeGridItemType.network => HomeGridItem.network(
        colSpan: colSpan ?? this.colSpan,
        rowSpan: rowSpan ?? this.rowSpan,
        tileColorValue: color,
      ),
      HomeGridItemType.app =>
        app != null
            ? HomeGridItem.app(
                app!,
                colSpan: colSpan ?? this.colSpan,
                rowSpan: rowSpan ?? this.rowSpan,
                tileColorValue: color,
              )
            : HomeGridItem.localApp(
                localApp!,
                colSpan: colSpan ?? this.colSpan,
                rowSpan: rowSpan ?? this.rowSpan,
                tileColorValue: color,
              ),
    };
  }
}

const Object _homeUnset = Object();
