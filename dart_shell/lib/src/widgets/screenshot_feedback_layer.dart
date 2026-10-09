import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/screenshot_file_monitor.dart';

@immutable
class ScreenshotFeedback {
  const ScreenshotFeedback({required this.path, required this.serial});

  final String path;
  final int serial;
}

final screenshotFeedbackProvider =
    NotifierProvider<ScreenshotFeedbackController, ScreenshotFeedback?>(
      ScreenshotFeedbackController.new,
    );

class ScreenshotFeedbackController extends Notifier<ScreenshotFeedback?> {
  int _serial = 0;

  @override
  ScreenshotFeedback? build() => null;

  void saved(String path) {
    state = ScreenshotFeedback(path: path, serial: ++_serial);
  }

  void dismiss() => state = null;
}

/// Android-like post-capture feedback for the mobile shell. Observes complete
/// screenshot files instead of a command-accepted result so failed saves never
/// produce a false success animation. Does not intercept app touch input except
/// inside the small, dismissible thumbnail.
class ScreenshotFeedbackLayer extends ConsumerStatefulWidget {
  const ScreenshotFeedbackLayer({super.key, this.directory});

  /// Optional directory injection for tests; normal shells follow deniald's
  /// DENIAL_SCREENSHOT_DIR -> xdg-user-dir PICTURES -> ~/Pictures resolution.
  final Directory? directory;

  @override
  ConsumerState<ScreenshotFeedbackLayer> createState() =>
      _ScreenshotFeedbackLayerState();
}

class _ScreenshotFeedbackLayerState
    extends ConsumerState<ScreenshotFeedbackLayer>
    with TickerProviderStateMixin {
  static const _displayTime = Duration(milliseconds: 3800);

  ScreenshotFileMonitor? _monitor;
  Timer? _hideTimer;
  late final AnimationController _flash;
  late final AnimationController _thumbnail;
  late final Animation<double> _flashOpacity;
  late final Animation<double> _thumbnailOpacity;
  late final Animation<Offset> _thumbnailSlide;
  late final Animation<double> _thumbnailScale;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _thumbnail = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _flashOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: 0.26,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.26,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 80,
      ),
    ]).animate(_flash);
    final curved = CurvedAnimation(
      parent: _thumbnail,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _thumbnailOpacity = curved;
    _thumbnailSlide = Tween<Offset>(
      begin: const Offset(-0.28, 0.20),
      end: Offset.zero,
    ).animate(curved);
    _thumbnailScale = Tween<double>(begin: 0.88, end: 1).animate(curved);
    unawaited(_watchScreenshotFiles());
  }

  Future<void> _watchScreenshotFiles() async {
    final directory = widget.directory ?? await denialScreenshotDirectory();
    if (!mounted) return;
    final monitor = ScreenshotFileMonitor(
      directory: directory,
      onSaved: (path) {
        if (mounted) ref.read(screenshotFeedbackProvider.notifier).saved(path);
      },
    );
    _monitor = monitor;
    await monitor.start();
  }

  void _show(ScreenshotFeedback feedback) {
    _hideTimer?.cancel();
    _flash.forward(from: 0);
    _thumbnail.forward(from: 0);
    _hideTimer = Timer(_displayTime, () => _dismiss(feedback.serial));
  }

  void _dismiss(int serial) {
    _hideTimer?.cancel();
    if (ref.read(screenshotFeedbackProvider)?.serial != serial) return;
    unawaited(
      _thumbnail.reverse().then((_) {
        if (!mounted) return;
        if (ref.read(screenshotFeedbackProvider)?.serial == serial) {
          ref.read(screenshotFeedbackProvider.notifier).dismiss();
        }
      }),
    );
  }

  void _openScreenshot(String path) {
    unawaited(
      Process.start('xdg-open', <String>[
        path,
      ], mode: ProcessStartMode.detached).then(
        (_) {},
        onError: (Object error) {
          debugPrint('Could not open screenshot preview: $error');
        },
      ),
    );
  }

  @override
  void dispose() {
    _monitor?.dispose();
    _hideTimer?.cancel();
    _flash.dispose();
    _thumbnail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ScreenshotFeedback?>(screenshotFeedbackProvider, (old, next) {
      if (next != null && next.serial != old?.serial) {
        _show(next);
      }
    });
    final feedback = ref.watch(screenshotFeedbackProvider);
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final chinese = Localizations.maybeLocaleOf(context)?.languageCode == 'zh';
    final width = math.min(238.0, math.max(140.0, size.width - 32.0));

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _flash,
            builder: (context, _) => ColoredBox(
              color: Colors.white.withValues(alpha: _flashOpacity.value),
            ),
          ),
        ),
        if (feedback != null)
          Positioned(
            left: math.max(12, padding.left + 12),
            bottom: math.max(24, padding.bottom) + 64,
            width: width,
            child: FadeTransition(
              opacity: _thumbnailOpacity,
              child: SlideTransition(
                position: _thumbnailSlide,
                child: ScaleTransition(
                  scale: _thumbnailScale,
                  alignment: Alignment.bottomLeft,
                  child: RepaintBoundary(
                    child: Semantics(
                      liveRegion: true,
                      label: chinese ? '截图已保存' : 'Screenshot saved',
                      child: Material(
                        color: const Color(0xF21D242D),
                        elevation: 12,
                        borderRadius: BorderRadius.circular(18),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            InkWell(
                              key: const ValueKey(
                                'screenshot-feedback-thumbnail',
                              ),
                              onTap: () => _openScreenshot(feedback.path),
                              child: Padding(
                                padding: const EdgeInsets.all(9),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(
                                        width: 70,
                                        height: 90,
                                        child: Image.file(
                                          File(feedback.path),
                                          key: ValueKey(feedback.path),
                                          cacheWidth: 140,
                                          fit: BoxFit.cover,
                                          filterQuality: FilterQuality.low,
                                          errorBuilder: (_, _, _) =>
                                              const ColoredBox(
                                                color: Color(0xFF394553),
                                                child: Icon(
                                                  Icons.image_rounded,
                                                  color: Colors.white70,
                                                ),
                                              ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            size: 21,
                                            color: Color(0xFF7AE2AD),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            chinese
                                                ? '截图已保存'
                                                : 'Screenshot saved',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            chinese ? '点击查看' : 'Tap to open',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFFBAC8D2),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              right: 2,
                              top: 2,
                              child: IconButton(
                                key: const ValueKey(
                                  'screenshot-feedback-dismiss',
                                ),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 17,
                                  color: Colors.white70,
                                ),
                                tooltip: chinese ? '关闭' : 'Dismiss',
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () => _dismiss(feedback.serial),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
