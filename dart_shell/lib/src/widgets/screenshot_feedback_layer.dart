import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart'
    show Icons, IconButton, Material, Tooltip;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../input/shell_interaction_registry.dart';
import '../localization/denial_localizations.dart';
import '../state/screenshot_feedback.dart';
import '../state/shell_controller.dart';
import '../theme/shell_theme.dart';

/// Transient feedback, not a modal: only the thumbnail accepts input.
class ScreenshotFeedbackLayer extends ConsumerWidget {
  const ScreenshotFeedbackLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(shellControllerProvider.select((s) => s.locked));
    final feedback = ref.watch(screenshotFeedbackProvider);
    final path = feedback.path;
    if (locked || (path == null && !feedback.failed)) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(screenshotFeedbackProvider.notifier);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final text = context.l10n;
    final colors = context.shellColors;
    final gap = MediaQuery.paddingOf(context).bottom;
    final card = ShellInputRegion(
      debugLabel: 'screenshot feedback',
      pointerPolicy: ShellPointerPolicy.childBounds,
      child: Dismissible(
        key: ValueKey(path ?? 'screenshot-failed-card'),
        direction: DismissDirection.horizontal,
        resizeDuration: null,
        onDismissed: (_) => controller.dismiss(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colors.textTertiary.withValues(alpha: .35),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (path != null)
                  Tooltip(
                    message: text.screenshotOpen,
                    child: Semantics(
                      button: true,
                      label: text.screenshotOpen,
                      child: GestureDetector(
                        key: const ValueKey('screenshot-preview-open'),
                        onTap: () => unawaited(controller.open()),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(path),
                            width: 116,
                            height: 92,
                            cacheWidth: 240,
                            fit: BoxFit.contain,
                            excludeFromSemantics: true,
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 116,
                              height: 92,
                              child: Icon(Icons.image_rounded),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      text.screenshotFailed,
                      style: TextStyle(color: colors.panelText, fontSize: 14),
                    ),
                  ),
                Material(
                  color: const Color(0x00000000),
                  child: IconButton(
                    tooltip: text.screenshotDismiss,
                    icon: Icon(Icons.close_rounded, color: colors.panelText),
                    onPressed: controller.dismiss,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Positioned.fill(
      key: ValueKey(path ?? 'screenshot-failed'),
      child: Stack(
        children: [
          if (path != null && !reduceMotion)
            Positioned.fill(
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 220),
                  tween: Tween(begin: .56, end: 0),
                  curve: Curves.easeOutCubic,
                  builder: (_, opacity, _) =>
                      ColoredBox(color: Color.fromRGBO(255, 255, 255, opacity)),
                ),
              ),
            ),
          Positioned(
            left: 12,
            bottom: 20 + gap,
            child: path != null && !reduceMotion
                ? TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 240),
                    tween: Tween(begin: .8, end: 1),
                    curve: Curves.easeOutCubic,
                    builder: (_, scale, child) => Transform.scale(
                      scale: scale,
                      alignment: Alignment.bottomLeft,
                      child: child,
                    ),
                    child: card,
                  )
                : card,
          ),
        ],
      ),
    );
  }
}
