import 'package:denial_flutter_sdk/panels.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/shell_plugin_services.dart';
import '../features/default_shell/panel_composition.dart';
import '../models/display_layout.dart';

export 'package:denial_top_bar/denial_top_bar.dart'
    show DesktopSystemBarIndicatorSlot, systemBarBatteryButtonKey;

/// Compatibility host for the statically composed panel.
class DesktopSystemBar extends ConsumerWidget {
  const DesktopSystemBar({
    required this.monitorId,
    required this.side,
    required this.onOpenPowerSettings,
    required this.onToggleLauncher,
    this.panel = selectedDesktopPanel,
    super.key,
  });
  final int monitorId;
  final SystemBarSide side;
  final VoidCallback onOpenPowerSettings;
  final VoidCallback onToggleLauncher;
  final ShellPanel panel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final child = panel.build(
      context,
      monitorId: monitorId,
      edge: side,
      services: RuntimeShellServices(
        ref: ref,
        onOpenPowerSettings: onOpenPowerSettings,
        onToggleLauncher: onToggleLauncher,
      ),
    );
    final placement = panel.placement;
    if (placement == null || !placement.reserveWindowSpacing) return child;
    return Align(
      alignment: switch (side) {
        PanelEdge.top => Alignment.topCenter,
        PanelEdge.bottom => Alignment.bottomCenter,
        PanelEdge.left => Alignment.centerLeft,
        PanelEdge.right => Alignment.centerRight,
        PanelEdge.hidden => Alignment.center,
      },
      child: SizedBox(
        width: side.isHorizontal ? double.infinity : placement.thickness,
        height: side.isHorizontal ? placement.thickness : double.infinity,
        child: child,
      ),
    );
  }
}
