import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../localization/denial_localizations.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_icon.dart';
import '../controllers/home_grid_controller.dart';
import '../models/home_clock_info.dart';
import '../models/home_grid_item.dart';

part 'home_app_tile.dart';
part 'home_clock_tile.dart';

const _metroTilePalette = <Color>[
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

Color _metroTileColor(String identity) {
  if (identity == 'widget:clock') {
    return const Color(0xFF0078D7);
  }
  var hash = 0x811C9DC5;
  for (final unit in identity.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return _metroTilePalette[hash % _metroTilePalette.length];
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
    return switch (item.type) {
      HomeGridItemType.clock => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: ColoredBox(
          color: _metroTileColor(item.id),
          child: HomeClockWidget(clock: ref.watch(homeClockProvider)),
        ),
      ),
      HomeGridItemType.app => _HomeAppTile(
        identity: item.id,
        name: item.localApp?.titleFor(context) ?? item.app!.name,
        iconPath: item.app?.iconPath,
        icon: item.localApp?.icon,
        colSpan: item.colSpan,
        rowSpan: item.rowSpan,
        onTap: launchEnabled ? (rect) => onLaunch(item, rect) : null,
      ),
    };
  }
}
