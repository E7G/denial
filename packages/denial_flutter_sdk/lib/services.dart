import 'dart:typed_data';

import 'package:denial_sdk/system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

/// Public read-only workspace projection, without desktop-controller exposure.
class WorkspaceStatus {
  WorkspaceStatus({
    required this.count,
    required this.active,
    required Set<int> occupied,
  }) : occupied = Set.unmodifiable(occupied);

  final int count;
  final int active;
  final Set<int> occupied;
}

/// A user application window, without native surfaces or controller access.
class ApplicationWindow {
  const ApplicationWindow({
    required this.id,
    required this.appId,
    required this.title,
    required this.active,
    required this.minimized,
  });
  final int id;
  final String appId;
  final String title;
  final bool active;
  final bool minimized;
}

abstract interface class MediaCommands {
  MprisPlaybackState get current;
  Future<void> previous();
  Future<void> playPause();
  Future<void> next();
}

/// Native-backed reads and actions supplied explicitly by the shell runtime.
///
/// Listenable providers preserve selective subscriptions and the runtime's
/// existing ownership. Plugins cannot access private notifier/controller types.
/// This is fixed dependency injection, not a runtime plugin registry.
abstract interface class ShellServices {
  ProviderListenable<List<ApplicationWindow>> windows(int monitorId);
  void activateWindow(int id);
  void toggleLauncher();
  Widget buildApplicationIcon(BuildContext context, String appId);
  ProviderListenable<BatteryStatus> get battery;
  ProviderListenable<LoadSeries> get cpu;
  ProviderListenable<List<GpuLoad>> get gpus;
  ProviderListenable<AsyncValue<DateTime>> get clock;
  ProviderListenable<AsyncValue<MprisPlaybackState>> get media;
  ProviderListenable<MediaCommands> get mediaCommands;
  ProviderListenable<Color> get accent;
  ProviderListenable<bool> get workspacesEnabled;
  ProviderListenable<bool> get trayVisible;
  ProviderListenable<WorkspaceStatus> workspace(int monitorId);
  ProviderListenable<AsyncValue<Uint8List?>> imageBytes(String path);
  void switchWorkspace({required int monitorId, required int workspaceId});
  void openPowerSettings();
  MouseCursor get normalCursor;
  MouseCursor get linkCursor;
  ShellStrings strings(BuildContext context);

  /// Shared StatusNotifier presentation including menu/input ownership.
  /// Kept as a host component until the tray's own package is extracted.
  Widget buildSystemTray(
    BuildContext context, {
    required bool horizontal,
    bool wrap = false,
  });
}

/// Localized platform labels/formatters; implementations depend on the locale.
abstract interface class ShellStrings {
  String time(DateTime value);
  String shortDate(DateTime value);
  String batteryLine(String state, int capacity);
  String numberValue(int value);
  String workspaceLabel(int workspace);
  String get batteryTitle;
  String get percentSign;
  String get celsiusUnit;
  String get metricCpu;
  String get mediaControls;
  String get mediaNowPlaying;
  String get mediaPrevious;
  String get mediaNext;
  String get mediaPlay;
  String get mediaPause;
  String get workspaceOccupied;
  String get workspaceEmpty;
  String get workspaceActive;
}

/// Makes explicitly supplied services available below one composed component.
class ShellServicesScope extends InheritedWidget {
  const ShellServicesScope({
    required this.services,
    required super.child,
    super.key,
  });
  final ShellServices services;

  static ShellServices of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ShellServicesScope>();
    if (scope == null) throw StateError('ShellServicesScope is missing.');
    return scope.services;
  }

  @override
  bool updateShouldNotify(ShellServicesScope oldWidget) =>
      !identical(services, oldWidget.services);
}
