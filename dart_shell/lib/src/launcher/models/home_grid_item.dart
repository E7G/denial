import '../../local_apps/local_flutter_application.dart';
import 'desktop_app.dart';

enum HomeGridItemType { clock, app }

class HomeLayoutSlot {
  const HomeLayoutSlot({required this.id, this.colSpan, this.rowSpan});

  final String id;
  final int? colSpan;
  final int? rowSpan;
}

class HomeGridItem {
  const HomeGridItem._({
    required this.type,
    required this.id,
    required this.colSpan,
    required this.rowSpan,
    required this.app,
    required this.localApp,
  });

  factory HomeGridItem.clock({
    int colSpan = defaultClockColSpan,
    int rowSpan = defaultClockRowSpan,
  }) {
    return HomeGridItem._(
      type: HomeGridItemType.clock,
      id: 'widget:clock',
      colSpan: colSpan.clamp(clockMinColSpan, clockMaxColSpan).toInt(),
      rowSpan: rowSpan.clamp(clockMinRowSpan, clockMaxRowSpan).toInt(),
      app: null,
      localApp: null,
    );
  }

  factory HomeGridItem.app(
    DesktopApp desktopApp, {
    int colSpan = defaultAppColSpan,
    int rowSpan = defaultAppRowSpan,
  }) {
    return HomeGridItem._(
      type: HomeGridItemType.app,
      id: 'app:${desktopApp.id}',
      colSpan: colSpan.clamp(appMinColSpan, appMaxColSpan).toInt(),
      rowSpan: rowSpan.clamp(appMinRowSpan, appMaxRowSpan).toInt(),
      app: desktopApp,
      localApp: null,
    );
  }

  factory HomeGridItem.localApp(
    LocalFlutterApplication localApp, {
    int colSpan = defaultAppColSpan,
    int rowSpan = defaultAppRowSpan,
  }) {
    return HomeGridItem._(
      type: HomeGridItemType.app,
      id: 'local:${localApp.id}',
      colSpan: colSpan.clamp(appMinColSpan, appMaxColSpan).toInt(),
      rowSpan: rowSpan.clamp(appMinRowSpan, appMaxRowSpan).toInt(),
      app: null,
      localApp: localApp,
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

  final HomeGridItemType type;
  final String id;
  final int colSpan;
  final int rowSpan;
  final DesktopApp? app;
  final LocalFlutterApplication? localApp;

  bool get resizable => true;

  int get minColSpan {
    return switch (type) {
      HomeGridItemType.clock => clockMinColSpan,
      HomeGridItemType.app => appMinColSpan,
    };
  }

  int get maxColSpan {
    return switch (type) {
      HomeGridItemType.clock => clockMaxColSpan,
      HomeGridItemType.app => appMaxColSpan,
    };
  }

  int get minRowSpan {
    return switch (type) {
      HomeGridItemType.clock => clockMinRowSpan,
      HomeGridItemType.app => appMinRowSpan,
    };
  }

  int get maxRowSpan {
    return switch (type) {
      HomeGridItemType.clock => clockMaxRowSpan,
      HomeGridItemType.app => appMaxRowSpan,
    };
  }

  HomeGridItem resize({required int colSpan, required int rowSpan}) {
    if (!resizable) {
      return this;
    }
    return switch (type) {
      HomeGridItemType.clock => HomeGridItem.clock(
        colSpan: colSpan,
        rowSpan: rowSpan,
      ),
      HomeGridItemType.app =>
        app != null
            ? HomeGridItem.app(app!, colSpan: colSpan, rowSpan: rowSpan)
            : HomeGridItem.localApp(
                localApp!,
                colSpan: colSpan,
                rowSpan: rowSpan,
              ),
    };
  }
}
