import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/denial_bridge.dart';
import '../state/shell_controller.dart';

final systemActionsServiceProvider = Provider<SystemActionsService>((ref) {
  return SystemActionsService(ref.watch(denialBridgeProvider));
});

/// One-shot system actions triggered from the quick-settings shade.
class SystemActionsService {
  const SystemActionsService([this._bridge]);

  final DenialBridge? _bridge;

  Future<String?> takeScreenshot() async {
    return await _bridge?.takeScreenshotWithResult();
  }

  Future<bool> openScreenshot(String path) async {
    try {
      // No shell interpolation. The native reply supplies an absolute PNG path.
      final result = await Process.run('xdg-open', [path]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}
