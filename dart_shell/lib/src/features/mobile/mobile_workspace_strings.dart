import 'package:flutter/widgets.dart';

import '../../localization/denial_localizations.dart';
import '../../models/mobile_workspace.dart';

/// The shell currently supports English and Chinese; keep this feature's
/// compact labels together, using the same resolved locale as the shell.
class MobileWorkspaceStrings {
  MobileWorkspaceStrings(BuildContext context)
    : chinese = context.l10n.localeName.startsWith('zh');
  final bool chinese;
  String get title => chinese ? '工作区' : 'Workspace';
  String get merge => chinese ? '拖到这里合并工作区' : 'Drop to create a workspace';
  String get ungroup => chinese ? '拆开' : 'Ungroup';
  String get close => chinese ? '关闭窗口' : 'Close window';
  String get resize => chinese ? '拖动调整窗口比例' : 'Drag to resize panes';
  String get scroll => chinese ? '拖动标题栏滚动窗口' : 'Drag the title bar to scroll';
  String mode(MobileWorkspaceMode mode) => switch (mode) {
    MobileWorkspaceMode.automatic => chinese ? '自动' : 'Auto',
    MobileWorkspaceMode.split => chinese ? '分屏' : 'Split',
    MobileWorkspaceMode.scrolling => chinese ? '滚动平铺' : 'Scrolling',
  };
}
