import 'package:flutter/widgets.dart';

import '../../features/mobile/mobile_workspace_strings.dart';
import '../../models/denial_window.dart';
import '../../theme/shell_theme.dart';
import '../window_content_rect.dart';

class OverviewWorkspacePreview extends StatelessWidget {
  const OverviewWorkspacePreview({
    super.key,
    required this.previewKey,
    required this.windows,
    required this.size,
  });
  final Key previewKey;
  final List<DenialWindow> windows;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final horizontal =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    return Semantics(
      label: '${MobileWorkspaceStrings(context).title} · ${windows.length}',
      child: RepaintBoundary(
        child: SizedBox(
          key: previewKey,
          width: size.width,
          height: size.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              context.shellTheme.windowRadius,
            ),
            child: ColoredBox(
              color: context.shellColors.background,
              child: Flex(
                direction: horizontal ? Axis.horizontal : Axis.vertical,
                children: [
                  for (final window in windows)
                    Expanded(
                      child: ClipRect(
                        child: WindowContentRect(
                          key: ValueKey('workspace-preview-${window.objectId}'),
                          window: window,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          cropToContentBounds: true,
                          includeLocalStatusInset: false,
                        ),
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
