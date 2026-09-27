@Plugin()
library;

import 'package:denial_sdk/composition.dart';
import 'package:denial_flutter_sdk/panels.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:flutter/widgets.dart';

import 'src/desktop_system_bar.dart';

export 'src/desktop_system_bar.dart'
    show
        DesktopSystemBar,
        DesktopSystemBarIndicatorSlot,
        systemBarBatteryButtonKey;

@Provides(ShellPanel)
final class TopBarPlugin implements ShellPanel {
  const TopBarPlugin();

  @override
  PanelPlacement? get placement => null;

  @override
  Widget build(
    BuildContext context, {
    required int monitorId,
    required PanelEdge edge,
    required ShellServices services,
  }) => DesktopSystemBar(monitorId: monitorId, side: edge, services: services);
}
