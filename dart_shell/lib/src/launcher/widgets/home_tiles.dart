import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../localization/denial_localizations.dart';
import '../../settings/settings_controller.dart';
import '../../services/network_backend.dart';
import '../../state/network_connectivity.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_icon.dart';
import '../controllers/home_grid_controller.dart';
import '../models/home_clock_info.dart';
import '../models/home_grid_item.dart';

part 'home_app_tile.dart';
part 'home_clock_tile.dart';

const metroTilePalette = <Color>[
  Color(0xFF0078D7),
  Color(0xFF008272),
  Color(0xFF107C10),
  Color(0xFFD83B01),
  Color(0xFFE81123),
  Color(0xFF5C2D91),
  Color(0xFF744DA9),
  Color(0xFF2D7D9A),
  Color(0xFFC239B3),
  Color(0xFF498205),
];

Color metroTileColor(String identity, [int? overrideValue]) {
  if (overrideValue != null) {
    return Color(overrideValue).withAlpha(0xff);
  }
  if (identity == 'widget:clock') {
    return const Color(0xFF0078D7);
  }
  if (identity == 'widget:date') {
    return const Color(0xFFD83B01);
  }
  if (identity == 'widget:battery') {
    return const Color(0xFF107C10);
  }
  var hash = 0x811C9DC5;
  for (final unit in identity.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return metroTilePalette[hash % metroTilePalette.length];
}

class HomeGridItemCard extends ConsumerWidget {
  const HomeGridItemCard({
    super.key,
    required this.item,
    this.launchEnabled = true,
    required this.onLaunch,
  });

  final HomeGridItem item;
  final bool launchEnabled;
  final void Function(HomeGridItem item, Rect sourceRect) onLaunch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = item.isSystemTile ? ref.watch(homeClockProvider) : null;
    final tabletSettings = ref.watch(
      shellSettingsProvider.select((settings) => settings.tablet),
    );
    final network = item.type == HomeGridItemType.network
        ? ref.watch(networkConnectivityProvider).snapshot
        : null;
    final opacity = tabletSettings.enabled ? tabletSettings.tileOpacity : 0.22;
    final tileColor = metroTileColor(
      item.id,
      item.tileColorValue,
    ).withValues(alpha: opacity);
    return switch (item.type) {
      HomeGridItemType.clock => _MetroLiveTileTransition(
        animationKey: 'clock:${clock!.now.hour}:${clock.now.minute}',
        strength: tabletSettings.animationStrength,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: ColoredBox(
            color: tileColor,
            child: HomeClockWidget(clock: clock),
          ),
        ),
      ),
      HomeGridItemType.date => _MetroLiveTileTransition(
        animationKey:
            'date:${clock!.now.year}-${clock.now.month}-${clock.now.day}',
        strength: tabletSettings.animationStrength,
        child: _HomeDateTile(clock: clock, color: tileColor),
      ),
      HomeGridItemType.battery => _MetroLiveTileTransition(
        animationKey:
            'battery:${clock!.power.capacity}:${clock.power.state}:${clock.power.chargeProtocol}',
        strength: tabletSettings.animationStrength,
        child: _HomeBatteryTile(
          clock: clock,
          color: tileColor,
        ),
      ),
      HomeGridItemType.network => _MetroLiveTileTransition(
        animationKey:
            'network:${network!.connectedNetwork?.ssid}:${network.wirelessEnabled}:${network.connectedNetwork?.strength}',
        strength: tabletSettings.animationStrength,
        child: _HomeNetworkTile(
          snapshot: network,
          color: tileColor,
        ),
      ),
      HomeGridItemType.folder => _HomeFolderTile(
        item: item,
        color: tileColor,
        animationStrength: tabletSettings.animationStrength,
        onTap: launchEnabled ? (rect) => onLaunch(item, rect) : null,
      ),
      HomeGridItemType.app => _HomeAppTile(
        identity: item.id,
        name: item.localApp?.titleFor(context) ?? item.app!.name,
        iconPath: item.app?.iconPath,
        icon: item.localApp?.icon,
        colSpan: item.colSpan,
        rowSpan: item.rowSpan,
        tileColorValue: item.tileColorValue,
        tileOpacity: opacity,
        metroEnabled: tabletSettings.enabled,
        animationStrength: tabletSettings.animationStrength,
        onTap: launchEnabled ? (rect) => onLaunch(item, rect) : null,
      ),
    };
  }
}

class _MetroLiveTileTransition extends StatelessWidget {
  const _MetroLiveTileTransition({
    required this.animationKey,
    required this.strength,
    required this.child,
  });

  final Object animationKey;
  final double strength;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = Duration(
      milliseconds: (360 * strength.clamp(0.0, 1.5)).round(),
    );
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.22),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        return ClipRect(
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<Object>(animationKey),
        child: child,
      ),
    );
  }
}

class _HomeFolderTile extends StatefulWidget {
  const _HomeFolderTile({
    required this.item,
    required this.color,
    required this.animationStrength,
    required this.onTap,
  });

  final HomeGridItem item;
  final Color color;
  final double animationStrength;
  final ValueChanged<Rect>? onTap;

  @override
  State<_HomeFolderTile> createState() => _HomeFolderTileState();
}

class _HomeFolderTileState extends State<_HomeFolderTile> {
  final _tileKey = GlobalKey();
  bool _pressed = false;

  void _launch() {
    final render = _tileKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) {
      return;
    }
    widget.onTap?.call(
      MatrixUtils.transformRect(
        render.getTransformTo(null),
        Offset.zero & render.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strength = widget.animationStrength.clamp(0.0, 1.5);
    final scale = _pressed ? 1 - 0.035 * strength : 1.0;
    final children = widget.item.folderItems.take(4).toList(growable: false);
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: widget.item.folderName ?? 'Folder',
      child: AnimatedScale(
        scale: scale,
        duration: Duration(milliseconds: (90 * strength).round()),
        curve: Curves.easeOutCubic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.onTap == null
              ? null
              : (_) => setState(() => _pressed = true),
          onTapCancel: widget.onTap == null
              ? null
              : () => setState(() => _pressed = false),
          onTapUp: widget.onTap == null
              ? null
              : (_) => setState(() => _pressed = false),
          onTap: widget.onTap == null ? null : _launch,
          child: DecoratedBox(
            key: _tileKey,
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 78,
                        height: 78,
                        child: GridView.count(
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          mainAxisSpacing: 5,
                          crossAxisSpacing: 5,
                          padding: EdgeInsets.zero,
                          children: [
                            for (final child in children)
                              _FolderMiniIcon(item: child),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Text(
                    widget.item.folderName ?? 'Folder',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.l10n.tabletFolderAppCount(
                      widget.item.folderItems.length,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 10,
                      height: 1,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderMiniIcon extends StatelessWidget {
  const _FolderMiniIcon({required this.item});

  final HomeGridItem item;

  @override
  Widget build(BuildContext context) {
    final localIcon = item.localApp?.icon;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.18),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: localIcon != null
              ? Icon(localIcon, color: Colors.white, size: 24)
              : AppIconImage(iconPath: item.app?.iconPath),
        ),
      ),
    );
  }
}

class _HomeDateTile extends StatelessWidget {
  const _HomeDateTile({required this.clock, required this.color});

  final HomeClockInfo clock;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final date = clock.now;
    final weekday = MaterialLocalizations.of(context).formatFullDate(date);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: ColoredBox(
        color: color,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final big = math.min(constraints.maxWidth, constraints.maxHeight);
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      date.day.toString(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: (big * 0.42).clamp(34, 72).toDouble(),
                        height: 0.95,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      weekday,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.94),
                        fontSize: (big * 0.105).clamp(12, 17).toDouble(),
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Icon(
                      Icons.calendar_month_rounded,
                      color: Colors.white.withValues(alpha: 0.82),
                      size: (big * 0.18).clamp(20, 32).toDouble(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeNetworkTile extends StatelessWidget {
  const _HomeNetworkTile({required this.snapshot, required this.color});

  final NetworkSnapshot snapshot;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final connected = snapshot.connectedNetwork;
    final enabled =
        snapshot.serviceAvailable &&
        snapshot.wifiDeviceAvailable &&
        snapshot.wirelessHardwareEnabled &&
        snapshot.wirelessEnabled;
    final icon = !enabled
        ? Icons.wifi_off_rounded
        : connected != null
        ? Icons.wifi_rounded
        : Icons.wifi_find_rounded;
    final title =
        connected?.ssid ??
        (enabled
            ? context.l10n.tabletWifiNotConnected
            : context.l10n.tabletWifiOff);
    final detail = connected != null
        ? context.l10n.tabletSignalPercent(connected.strength)
        : enabled
        ? context.l10n.tabletWifiConnectHint
        : context.l10n.tabletWirelessDisabled;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: ColoredBox(
        color: color,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final big = math.min(constraints.maxWidth, constraints.maxHeight);
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Icon(
                      icon,
                      color: Colors.white,
                      size: (big * 0.30).clamp(32, 56).toDouble(),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: (big * 0.14).clamp(16, 24).toDouble(),
                        height: 1.05,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.84),
                        fontSize: (big * 0.095).clamp(11, 15).toDouble(),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeBatteryTile extends StatelessWidget {
  const _HomeBatteryTile({required this.clock, required this.color});

  final HomeClockInfo clock;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final power = clock.power;
    final capacity = power.capacity;
    final charging = power.state == 'charging' || power.chargeProtocol != null;
    final icon = capacity == null
        ? Icons.battery_unknown_rounded
        : charging
        ? Icons.battery_charging_full_rounded
        : capacity < 15
        ? Icons.battery_alert_rounded
        : Icons.battery_full_rounded;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: ColoredBox(
        color: color,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final big = math.min(constraints.maxWidth, constraints.maxHeight);
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Icon(
                      icon,
                      color: Colors.white,
                      size: (big * 0.31).clamp(34, 58).toDouble(),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      capacity == null ? '—' : '$capacity%',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: (big * 0.27).clamp(28, 52).toDouble(),
                        height: 1,
                        fontWeight: FontWeight.w300,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      charging
                          ? context.l10n.batteryCharging
                          : context.l10n.batteryTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: (big * 0.105).clamp(12, 16).toDouble(),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
