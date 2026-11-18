import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/system_actions_service.dart';
import '../widgets/shade/shade_progress.dart';
import 'screenshot_selection.dart';
import 'shell_controller.dart';

@immutable
class ScreenshotFeedback {
  const ScreenshotFeedback({this.busy = false, this.path, this.failed = false});

  final bool busy;
  final String? path;
  final bool failed;
}

final screenshotFeedbackProvider =
    NotifierProvider<ScreenshotFeedbackController, ScreenshotFeedback>(
      ScreenshotFeedbackController.new,
    );

class ScreenshotFeedbackController extends Notifier<ScreenshotFeedback> {
  Timer? _dismissal;
  int _generation = 0;

  @override
  ScreenshotFeedback build() {
    ref.onDispose(() {
      _generation++;
      _dismissal?.cancel();
    });
    ref.listen(shellControllerProvider.select((value) => value.locked), (
      _,
      locked,
    ) {
      if (locked) _reset();
    });
    return const ScreenshotFeedback();
  }

  void _reset() {
    _generation++;
    _dismissal?.cancel();
    state = const ScreenshotFeedback();
  }

  void dismiss() {
    if (!state.busy) _reset();
  }

  Future<void> capture() async {
    if (state.busy ||
        ref.read(shellControllerProvider).locked ||
        ref.read(screenshotSelectionProvider) != null) {
      return;
    }
    final generation = ++_generation;
    _dismissal?.cancel();
    state = const ScreenshotFeedback(busy: true);
    final progress = ref.read(shadeProgressProvider);
    final actions = ref.read(systemActionsServiceProvider);
    ref.read(shellControllerProvider.notifier).closeQuickSettings();

    try {
      // Wait for the actual collapse, then for Flutter to paint without the
      // shade/previous thumbnail. The compositor consumes that clean scene.
      if (progress.value > 0) {
        final closed = Completer<void>();
        void check() {
          if (progress.value <= 0 && !closed.isCompleted) closed.complete();
        }

        progress.addListener(check);
        try {
          check();
          await closed.future.timeout(const Duration(seconds: 2));
        } finally {
          progress.removeListener(check);
        }
      }
      if (generation != _generation) return;
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(seconds: 2),
      );
      // The current KMS frame is sourced from the scanout pool, not the
      // Flutter widget tree. Allow the shade-free frame to reach presentation.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (generation != _generation) return;
      final shell = ref.read(shellControllerProvider);
      if (shell.locked ||
          shell.quickSettingsVisible ||
          shell.quickSettingsDragActive ||
          progress.value > 0 ||
          ref.read(screenshotSelectionProvider) != null) {
        _reset();
        return;
      }
      final path = await actions.takeScreenshot();
      if (generation != _generation) return;
      _show(ScreenshotFeedback(path: path, failed: path == null));
    } catch (_) {
      if (generation != _generation) return;
      _show(const ScreenshotFeedback(failed: true));
    }
  }

  void _show(ScreenshotFeedback result) {
    _dismissal?.cancel();
    state = result;
    _dismissal = Timer(const Duration(seconds: 5), dismiss);
  }

  Future<void> open() async {
    final path = state.path;
    if (path == null || ref.read(shellControllerProvider).locked) return;
    final actions = ref.read(systemActionsServiceProvider);
    dismiss();
    final generation = _generation;
    if (!await actions.openScreenshot(path) && generation == _generation) {
      _show(const ScreenshotFeedback(failed: true));
    }
  }
}
