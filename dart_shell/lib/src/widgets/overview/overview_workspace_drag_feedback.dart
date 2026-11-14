import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/mobile/mobile_workspace_strings.dart';
import '../../state/shell_controller.dart';
import '../../theme/shell_theme.dart';

/// Flutter puts drag avatars above the scene Overlay entry, including the
/// lock layer. Observe security state in the avatar itself, never retain an
/// application title/preview over a newly locked desktop.
class OverviewWorkspaceDragFeedback extends ConsumerWidget {
  const OverviewWorkspaceDragFeedback({
    super.key,
    required this.title,
    required this.width,
  });
  final String title;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secure = ref.watch(
      shellControllerProvider.select(
        (state) => state.locked || state.lockLayerVisible,
      ),
    );
    if (secure) return const SizedBox.shrink();
    return SizedBox(
      width: width,
      height: 76,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.shellColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.shellColors.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.shellColors.textPrimary,
                  fontSize: 14,
                ),
              ),
              Text(
                MobileWorkspaceStrings(context).merge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.shellColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
