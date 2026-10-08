import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../input/input_layout.dart';
import '../../localization/denial_localizations.dart';
import '../../services/system_actions_service.dart';
import '../../state/shell_controller.dart';
import '../../state/system_status.dart';
import '../../theme/motion.dart';
import '../../theme/shell_color_scheme.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import 'shade_expansion_motion.dart';
import 'shade_reference_geometry.dart';
import 'status_glyphs.dart';

/// The always-on top status bar. Dragging it down opens the quick-settings
/// shade. Time and battery are isolated into their own consumers so their
/// periodic updates never rebuild the drag surface.
class ShadeStatusBar extends ConsumerWidget {
  const ShadeStatusBar({super.key, this.shadeProgress, this.onDragStart});

  final Animation<double>? shadeProgress;
  final ValueChanged<Offset>? onDragStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(shellControllerProvider.notifier);
    final topPadding = MediaQuery.paddingOf(context).top;
    final statusColorArgb = ref.watch(
      shellControllerProvider.select(
        (state) => state.foregroundWindow?.statusColorArgb,
      ),
    );
    final forceWhiteForeground = ref.watch(
      shellControllerProvider.select(
        (state) =>
            state.overviewVisible ||
            state.launchTransitionActive ||
            state.gestureDrag.dy < 0.0 ||
            state.homeTransitionActive,
      ),
    );
    final foreground = forceWhiteForeground
        ? ShellMediaColors.contrastLight
        : _statusForegroundFor(context.shellColors, statusColorArgb);
    final progress = shadeProgress ?? const AlwaysStoppedAnimation(0);
    final referenceScale = colorOsShadeScaleForViewport(
      MediaQuery.sizeOf(context),
    );
    final collapsedTop = topPadding + 10;
    const collapsedHeight = ShellMetrics.statusBarHeight - 18;
    final expandedTop = math.max(40 * referenceScale, topPadding);
    final expandedHeight = 18 * referenceScale;
    // Keep the expanded ColorOS geometry purely visual. The old implementation
    // used its ~110 px Mi Pad 2 extent as the permanent GestureDetector height,
    // which swallowed taps on Start's header actions underneath.
    final visualHeight = math.max(
      collapsedTop + collapsedHeight,
      expandedTop + expandedHeight,
    );
    final dragHitHeight = (topPadding + ShellMetrics.statusDragHeight)
        .clamp(0.0, MediaQuery.sizeOf(context).height)
        .toDouble();

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: visualHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: dragHitHeight,
            child: GestureDetector(
              key: const ValueKey<String>('status-bar-drag-surface'),
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (details) {
                onDragStart?.call(details.localPosition);
                controller.startQuickSettingsDrag(
                  progress: shadeProgress?.value,
                );
              },
              onVerticalDragUpdate: (details) {
                controller.updateQuickSettingsDrag(
                  Offset(
                    0.0,
                    details.delta.dy *
                        ShellMetrics.quickSettingsDragScale(
                          MediaQuery.sizeOf(context),
                        ),
                  ),
                );
              },
              onVerticalDragEnd: (details) {
                controller.endQuickSettingsDrag(details.primaryVelocity ?? 0.0);
              },
              onVerticalDragCancel: () => controller.endQuickSettingsDrag(0.0),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: progress,
              builder: (context, _) {
                final fraction = ColorOsShadeMotion.translationFraction(
                  progress.value,
                );
                final colorFraction = ColorOsShadeMotion.blurFraction(
                  progress.value,
                );
                final color = Color.lerp(
                  foreground,
                  context.shellColors.panelText,
                  colorFraction,
                )!;
                final top =
                    collapsedTop + (expandedTop - collapsedTop) * fraction;
                final height =
                    collapsedHeight +
                    (expandedHeight - collapsedHeight) * fraction;
                final horizontal = 20 + (35 * referenceScale - 20) * fraction;
                return Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: top,
                      left: horizontal,
                      right: horizontal,
                      height: height,
                      child: Row(
                        children: [
                          IgnorePointer(child: _StatusClock(color: color)),
                          const Spacer(),
                          _StatusScreenshotButton(color: color),
                          const SizedBox(width: 9),
                          IgnorePointer(child: _StatusCluster(color: color)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusScreenshotButton extends ConsumerStatefulWidget {
  const _StatusScreenshotButton({required this.color});

  final Color color;

  @override
  ConsumerState<_StatusScreenshotButton> createState() =>
      _StatusScreenshotButtonState();
}

class _StatusScreenshotButtonState
    extends ConsumerState<_StatusScreenshotButton> {
  bool _pressed = false;
  bool _capturing = false;

  Future<void> _capture() async {
    if (_capturing) {
      return;
    }
    setState(() {
      _capturing = true;
      _pressed = false;
    });
    // Let the pressed feedback clear before the compositor samples the live
    // output so the screenshot contains the normal status bar.
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (!mounted) {
      return;
    }
    try {
      await ref.read(systemActionsServiceProvider).takeScreenshot();
    } finally {
      if (mounted) {
        setState(() => _capturing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color.withValues(
      alpha: _capturing ? 0.42 : (_pressed ? 0.62 : 0.9),
    );
    return Semantics(
      button: true,
      enabled: !_capturing,
      label: 'Screenshot',
      child: GestureDetector(
        key: const ValueKey<String>('status-screenshot-action'),
        behavior: HitTestBehavior.opaque,
        onTapDown: _capturing ? null : (_) => setState(() => _pressed = true),
        onTapCancel: _capturing ? null : () => setState(() => _pressed = false),
        onTapUp: _capturing ? null : (_) => setState(() => _pressed = false),
        onTap: _capturing ? null : () => unawaited(_capture()),
        child: SizedBox(
          width: 30,
          height: 28,
          child: Icon(Icons.screenshot_rounded, color: color, size: 18),
        ),
      ),
    );
  }
}

class _StatusClock extends ConsumerWidget {
  const _StatusClock({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final time = localizedTime(context, now);
    final base = ShellText.statusClock.copyWith(
      fontSize: 16.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );
    final separator = time.indexOf(':');
    return Text.rich(
      TextSpan(
        children: separator <= 0 || separator == time.length - 1
            ? <InlineSpan>[TextSpan(text: time)]
            : <InlineSpan>[
                TextSpan(text: time.substring(0, separator + 1)),
                TextSpan(
                  text: time.substring(separator + 1),
                  style: TextStyle(color: color.withValues(alpha: 0.62)),
                ),
              ],
      ),
      style: base.copyWith(color: color),
    );
  }
}

class _StatusCluster extends ConsumerWidget {
  const _StatusCluster({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StatusCluster(battery: ref.watch(batteryProvider), color: color);
  }
}

Color _statusForegroundFor(ShellColorScheme colors, int? statusColorArgb) {
  if (statusColorArgb == null) {
    return colors.textPrimary;
  }

  final background = Color.alphaBlend(
    Color(statusColorArgb),
    colors.background,
  );
  return background.computeLuminance() > 0.52
      ? ShellMediaColors.darkness
      : ShellMediaColors.contrastLight;
}
