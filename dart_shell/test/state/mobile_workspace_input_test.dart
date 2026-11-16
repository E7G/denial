import 'package:denial_dart_shell/src/input/input_layout.dart';
import 'package:denial_dart_shell/src/input/shell_interaction_registry.dart';
import 'package:denial_dart_shell/src/models/mobile_workspace.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/state/shell_input_layout_coordinator.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_motion_harness.dart';

class _Bridge extends DenialBridge {
  InputLayoutSnapshot? snapshot;
  @override
  bool publishInputLayout(InputLayoutSnapshot value) {
    snapshot = value;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native and self-managed apps receive independent matching pane routes',
    () {
      final a = motionWindow(1);
      final b = motionWindow(2, selfManagedInsets: true);
      final group = MobileWorkspace(id: 1, members: [1, 2]);
      final state = ShellState.initial().copyWith(
        windows: [a, b],
        mobileWorkspaces: [group],
        foregroundObjectId: 1,
      );
      final bridge = _Bridge();
      ShellInputLayoutCoordinator(bridge).publish(
        state: state,
        viewSize: const Size(1024, 768),
        interactions: const ShellInteractionSnapshot.empty(),
      );
      final regions = bridge.snapshot!.windows;
      expect(regions, hasLength(2));
      expect(regions.every((region) => region.geometryLocked), isTrue);
      expect(regions[0].rect.top, 48);
      expect(regions[1].rect.top, 48);
      expect(regions[0].rect.right, lessThanOrEqualTo(506));
      expect(regions[1].rect.left, greaterThanOrEqualTo(518));
      for (final region in regions) {
        expect(
          region.rect.width / region.sourceRect.width,
          closeTo(region.rect.height / region.sourceRect.height, 0.0001),
        );
      }
    },
  );

  test(
    'offscreen workspace panes are not input targets or sampled windows',
    () {
      final group = MobileWorkspace(
        id: 1,
        members: [1, 2, 3],
        mode: MobileWorkspaceMode.scrolling,
        scrollOffset: 10000,
      );
      final state = ShellState.initial().copyWith(
        windows: [for (var id = 1; id <= 3; id++) motionWindow(id)],
        mobileWorkspaces: [group],
        foregroundObjectId: 1,
      );
      final bridge = _Bridge();
      ShellInputLayoutCoordinator(bridge).publish(
        state: state,
        viewSize: const Size(1024, 768),
        interactions: const ShellInteractionSnapshot.empty(),
      );
      expect(
        bridge.snapshot!.windows.any((region) => region.window.objectId == 1),
        isFalse,
      );
      for (final region in bridge.snapshot!.windows) {
        expect(region.rect.left, greaterThanOrEqualTo(0));
        expect(region.rect.right, lessThanOrEqualTo(1024));
        expect(region.sourceRect.left, greaterThanOrEqualTo(0));
      }
    },
  );

  test('secure lock owns the complete input scene, never a workspace pane', () {
    final state = ShellState.initial(locked: true).copyWith(
      windows: [motionWindow(1), motionWindow(2)],
      mobileWorkspaces: [
        MobileWorkspace(id: 1, members: [1, 2]),
      ],
      foregroundObjectId: 1,
    );
    final bridge = _Bridge();
    ShellInputLayoutCoordinator(bridge).publish(
      state: state,
      viewSize: const Size(1024, 768),
      interactions: const ShellInteractionSnapshot.empty(),
    );
    expect(bridge.snapshot!.keyboardCapture, isTrue);
    expect(
      bridge.snapshot!.shellRegions,
      contains(const Rect.fromLTWH(0, 0, 1024, 768)),
    );
    expect(bridge.snapshot!.windows.any((region) => region.hitTest), isFalse);
  });
}
