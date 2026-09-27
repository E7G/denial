import 'dart:typed_data';

import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_sdk/system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../desktop/desktop_workspace.dart';
import '../desktop/system_tray_module.dart';
import '../localization/denial_localizations.dart';
import '../launcher/controllers/home_grid_controller.dart';
import '../widgets/app_icon.dart';
import '../services/media_player_service.dart';
import '../settings/settings_controller.dart';
import '../state/shell_controller.dart';
import '../state/system_status.dart';
import '../state/system_tray.dart';
import '../theme/shell_theme.dart';
import '../wallpaper/state/wallpaper_accent.dart';
import '../widgets/notification_media.dart';
import '../widgets/shell_cursor.dart';

final _accent = Provider.autoDispose(
  (ref) => ref.watch(shellAccentProvider).color,
);
final _workspacesEnabled = Provider.autoDispose(
  (ref) => ref.watch(
    shellSettingsProvider.select(
      (settings) => settings.layout.workspacesEnabled,
    ),
  ),
);
final _trayVisible = Provider.autoDispose(
  (ref) => ref.watch(systemTrayProvider.select((items) => items.isNotEmpty)),
);
final _workspace = Provider.autoDispose.family<WorkspaceStatus, int>((
  ref,
  monitorId,
) {
  final desktop = ref.watch(desktopWorkspaceProvider);
  return WorkspaceStatus(
    count: ref.watch(
      shellSettingsProvider.select(
        (settings) => settings.layout.workspaceCount,
      ),
    ),
    active: desktop.activeWorkspaceFor(monitorId),
    occupied: desktop.placements.values
        .where(
          (placement) =>
              !placement.minimized && placement.monitorId == monitorId,
        )
        .map((placement) => placement.workspaceId)
        .toSet(),
  );
});
final _mediaCommands = Provider<MediaCommands>(
  (ref) => _MediaCommands(ref.watch(mediaPlayerServiceProvider)),
);

final _windows = Provider.autoDispose.family<List<ApplicationWindow>, int>((
  ref,
  monitorId,
) {
  final shell = ref.watch(shellControllerProvider);
  final desktop = ref.watch(desktopWorkspaceProvider);
  return List.unmodifiable([
    for (final window in shell.openAppWindows)
      if (window.monitorId == monitorId &&
          (window.minimized ||
              window.pinned ||
              window.workspaceId == desktop.activeWorkspaceFor(monitorId)))
        ApplicationWindow(
          id: window.objectId,
          appId: window.appId,
          title: window.title.isEmpty ? window.appId : window.title,
          active:
              shell.foregroundObjectId == window.objectId && !window.minimized,
          minimized: window.minimized,
        ),
  ]);
});

/// Adapts native-owned shell services to the public plugin boundary.
/// Provider lifetimes and mutations remain owned by their existing controllers.
final class RuntimeShellServices implements ShellServices {
  const RuntimeShellServices({
    required this.ref,
    required this.onOpenPowerSettings,
    required this.onToggleLauncher,
  });
  final WidgetRef ref;
  final VoidCallback onOpenPowerSettings;
  final VoidCallback onToggleLauncher;

  @override
  ProviderListenable<List<ApplicationWindow>> windows(int monitorId) =>
      _windows(monitorId);
  @override
  void activateWindow(int id) {
    for (final window in ref.read(shellControllerProvider).openAppWindows) {
      if (window.objectId != id) continue;
      ref.read(desktopWorkspaceProvider.notifier).activate(id);
      ref.read(shellControllerProvider.notifier).focusWindow(window);
      return;
    }
  }

  @override
  void toggleLauncher() => onToggleLauncher();
  @override
  Widget buildApplicationIcon(BuildContext context, String appId) =>
      _ApplicationIcon(appId: appId);

  @override
  ProviderListenable<BatteryStatus> get battery => batteryProvider;
  @override
  ProviderListenable<LoadSeries> get cpu => cpuUsageProvider;
  @override
  ProviderListenable<List<GpuLoad>> get gpus => gpuUsageProvider;
  @override
  ProviderListenable<AsyncValue<DateTime>> get clock => clockProvider;
  @override
  ProviderListenable<AsyncValue<MprisPlaybackState>> get media =>
      mediaPlaybackProvider;
  @override
  ProviderListenable<MediaCommands> get mediaCommands => _mediaCommands;
  @override
  ProviderListenable<Color> get accent => _accent;
  @override
  ProviderListenable<bool> get workspacesEnabled => _workspacesEnabled;
  @override
  ProviderListenable<bool> get trayVisible => _trayVisible;
  @override
  ProviderListenable<WorkspaceStatus> workspace(int monitorId) =>
      _workspace(monitorId);
  @override
  ProviderListenable<AsyncValue<Uint8List?>> imageBytes(String path) =>
      notificationStaticImageProvider(path);
  @override
  void switchWorkspace({required int monitorId, required int workspaceId}) =>
      ref
          .read(denialBridgeProvider)
          .switchWorkspace(monitorId: monitorId, workspaceId: workspaceId);
  @override
  void openPowerSettings() => onOpenPowerSettings();
  @override
  MouseCursor get normalCursor => ShellMouseCursors.normal;
  @override
  MouseCursor get linkCursor => ShellMouseCursors.link;
  @override
  ShellStrings strings(BuildContext context) => _Strings(context);
  @override
  Widget buildSystemTray(
    BuildContext context, {
    required bool horizontal,
    bool wrap = false,
  }) => _RuntimeSystemTray(horizontal: horizontal, wrap: wrap);
}

class _ApplicationIcon extends ConsumerWidget {
  const _ApplicationIcon({required this.appId});
  final String appId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(
      homeGridControllerProvider.select((value) {
        final id = appId.toLowerCase().replaceFirst(RegExp(r'\.desktop$'), '');
        for (final slot in value.value?.slots ?? []) {
          final app = slot?.app;
          if (app == null) continue;
          if (app.id.toLowerCase().replaceFirst(RegExp(r'\.desktop$'), '') ==
                  id ||
              app.startupWmClass?.toLowerCase() == id) {
            return app.iconPath;
          }
        }
        return null;
      }),
    );
    return AppIconImage(iconPath: path);
  }
}

class _RuntimeSystemTray extends ConsumerWidget {
  const _RuntimeSystemTray({required this.horizontal, required this.wrap});
  final bool horizontal;
  final bool wrap;
  @override
  Widget build(BuildContext context, WidgetRef ref) => SystemTrayModule(
    wrap: wrap,
    horizontal: horizontal,
    accent: context.shellTheme.accent,
    items: ref.watch(systemTrayProvider),
  );
}

final class _MediaCommands implements MediaCommands {
  const _MediaCommands(this.service);
  final MediaPlayerService service;
  @override
  MprisPlaybackState get current => service.current;
  @override
  Future<void> previous() => service.previous();
  @override
  Future<void> playPause() => service.playPause();
  @override
  Future<void> next() => service.next();
}

// Instances are created during build and not retained by the adapter.
final class _Strings implements ShellStrings {
  const _Strings(this.context);
  final BuildContext context;
  @override
  String time(DateTime value) => localizedTime(context, value);
  @override
  String shortDate(DateTime value) => localizedShortDate(context, value);
  @override
  String batteryLine(String state, int capacity) =>
      localizedBatteryLine(context.l10n, state, capacity);
  @override
  String numberValue(int value) => context.l10n.numberValue(value);
  @override
  String workspaceLabel(int workspace) =>
      context.l10n.workspaceLabel(workspace);
  @override
  String get batteryTitle => context.l10n.batteryTitle;
  @override
  String get percentSign => context.l10n.percentSign;
  @override
  String get celsiusUnit => context.l10n.celsiusUnit;
  @override
  String get metricCpu => context.l10n.metricCpu;
  @override
  String get mediaControls => context.l10n.mediaControls;
  @override
  String get mediaNowPlaying => context.l10n.mediaNowPlaying;
  @override
  String get mediaPrevious => context.l10n.mediaPrevious;
  @override
  String get mediaNext => context.l10n.mediaNext;
  @override
  String get mediaPlay => context.l10n.mediaPlay;
  @override
  String get mediaPause => context.l10n.mediaPause;
  @override
  String get workspaceOccupied => context.l10n.workspaceOccupied;
  @override
  String get workspaceEmpty => context.l10n.workspaceEmpty;
  @override
  String get workspaceActive => context.l10n.workspaceActive;
}
