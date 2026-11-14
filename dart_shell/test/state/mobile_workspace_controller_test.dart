import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/models/mobile_workspace.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_motion_harness.dart';

class _Bridge extends DenialBridge {
  final configured = <(int, Size?)>[];
  final closed = <int>[];
  @override
  void configureMobileWorkspaceWindow(DenialWindow window, Size? size) =>
      configured.add((window.objectId, size));
  @override
  void closeWindow(DenialWindow window) => closed.add(window.objectId);
}

class _Shell extends ShellController {
  final bridge = _Bridge();
  @override
  DenialBridge get workspaceBridge => bridge;
  @override
  ShellState build() => ShellState.initial().copyWith(
    windows: [for (var id = 1; id <= 4; id++) motionWindow(id)],
    foregroundObjectId: 1,
  );
  void seed(ShellState value) => state = value;
  @override
  void focusWindow(DenialWindow window) => state = state.copyWith(
    foregroundObjectId: window.objectId,
    overviewVisible: false,
  );
  @override
  void closeOverview() => state = state.copyWith(
    overviewVisible: false,
    clearForegroundObjectId: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Shell shell;
  ShellState current() => container.read(shellControllerProvider);
  setUp(() {
    container = ProviderContainer(
      overrides: [shellControllerProvider.overrideWith(_Shell.new)],
    );
    shell = container.read(shellControllerProvider.notifier) as _Shell;
  });
  tearDown(() => container.dispose());

  test('drag merge collapses two app identities into one recents entry', () {
    shell.mergeMobileWorkspace(1, 2);
    expect(current().mobileWorkspaces.single.members, [2, 1]);
    expect(current().mobileRecentsWindows.map((w) => w.objectId), [2, 3, 4]);
    expect(current().activeMobileWorkspace, isNotNull);
    expect(current().adjacentOpenAppWindow(1)?.objectId, 3);
  });

  test(
    'merging existing workspaces is deterministic and never duplicates members',
    () {
      shell.mergeMobileWorkspace(1, 2);
      shell.mergeMobileWorkspace(3, 4);
      shell.mergeMobileWorkspace(2, 4);
      expect(current().mobileWorkspaces.single.members, [4, 3, 2, 1]);
      shell.mergeMobileWorkspace(1, 4);
      expect(current().mobileWorkspaces, hasLength(1));
      expect(current().mobileRecentsWindows, hasLength(1));
    },
  );

  test(
    'locked, secure-transition and stale drops cannot create workspaces',
    () {
      shell.mergeMobileWorkspace(99, 2);
      expect(current().mobileWorkspaces, isEmpty);
      shell.seed(current().copyWith(locked: true));
      shell.mergeMobileWorkspace(1, 2);
      expect(current().mobileWorkspaces, isEmpty);
      shell.seed(current().copyWith(locked: false, lockLayerVisible: true));
      shell.mergeMobileWorkspace(1, 2);
      expect(current().mobileWorkspaces, isEmpty);
    },
  );

  test('scrolling translates the workspace without client configure spam', () {
    shell.mergeMobileWorkspace(1, 2);
    final id = current().mobileWorkspaces.single.id;
    shell.setMobileWorkspaceMode(id, MobileWorkspaceMode.scrolling);
    shell.synchronizeMobileWorkspaceGeometry(const Size(1024, 768));
    final initial = shell.bridge.configured.length;
    for (var i = 0; i < 120; i++) {
      shell.scrollMobileWorkspace(id, 2);
      shell.synchronizeMobileWorkspaceGeometry(const Size(1024, 768));
    }
    expect(initial, 2);
    expect(shell.bridge.configured.length, initial);
    expect(current().mobileWorkspaces.single.scrollOffset, greaterThan(0));
  });

  test(
    'divider moves paint immediately but negotiate client sizes only at commit',
    () {
      shell.mergeMobileWorkspace(1, 2);
      final id = current().mobileWorkspaces.single.id;
      shell.synchronizeMobileWorkspaceGeometry(const Size(1024, 768));
      shell.beginMobileWorkspaceResize(id);
      for (var i = 0; i < 8; i++) {
        shell.resizeMobileWorkspace(id, 0, 5);
        shell.synchronizeMobileWorkspaceGeometry(const Size(1024, 768));
      }
      expect(shell.bridge.configured, hasLength(2));
      shell.finishMobileWorkspaceResize();
      shell.synchronizeMobileWorkspaceGeometry(const Size(1024, 768));
      expect(shell.bridge.configured, hasLength(4));
    },
  );

  test(
    'cancelled divider drag restores weights without changing client sizes',
    () {
      shell.mergeMobileWorkspace(1, 2);
      final group = current().mobileWorkspaces.single;
      shell.synchronizeMobileWorkspaceGeometry(const Size(1024, 768));
      shell.beginMobileWorkspaceResize(group.id);
      shell.resizeMobileWorkspace(group.id, 0, 80);
      shell.finishMobileWorkspaceResize(cancel: true);
      shell.synchronizeMobileWorkspaceGeometry(const Size(1024, 768));
      expect(current().mobileWorkspaces.single.weights, group.weights);
      expect(shell.bridge.configured, hasLength(2));
    },
  );

  test(
    'closing a partner dissolves its singleton and restores real fullscreen',
    () {
      shell.mergeMobileWorkspace(1, 2);
      shell.synchronizeMobileWorkspaceGeometry(const Size(1024, 768));
      shell.seed(
        current().copyWith(
          windows: [motionWindow(1), motionWindow(3), motionWindow(4)],
        ),
      );
      shell.synchronizeMobileWorkspaceGeometry(const Size(1024, 768));
      expect(current().mobileWorkspaces, isEmpty);
      expect(shell.bridge.configured.last, (1, null));
    },
  );

  test(
    'ungroup restores every surviving client instead of leaving half-sized apps',
    () {
      shell.mergeMobileWorkspace(1, 2);
      final group = current().mobileWorkspaces.single;
      shell.synchronizeMobileWorkspaceGeometry(const Size(1024, 768));
      shell.ungroupMobileWorkspace(group.id);
      shell.synchronizeMobileWorkspaceGeometry(const Size(1024, 768));
      expect(
        shell.bridge.configured
            .where((item) => item.$2 == null)
            .map((item) => item.$1)
            .toSet(),
        {1, 2},
      );
    },
  );

  test('a workspace remembers its focused pane when selected from recents', () {
    shell.mergeMobileWorkspace(1, 2);
    shell.focusWindow(current().windowByObjectId(2)!);
    shell.focusWindow(current().windowByObjectId(3)!);
    shell.focusMobileRecentsEntry(current().windowByObjectId(2)!);
    expect(current().foregroundObjectId, 2);
    shell.focusWindow(current().windowByObjectId(1)!);
    shell.focusWindow(current().windowByObjectId(3)!);
    shell.focusMobileRecentsEntry(current().windowByObjectId(2)!);
    expect(current().foregroundObjectId, 1);
  });

  test('workspace dismissal closes its members only', () {
    shell.mergeMobileWorkspace(1, 2);
    shell.closeMobileRecentsEntry(current().windowByObjectId(2)!);
    expect(shell.bridge.closed, [2, 1]);
  });

  test('group scroll and resize retain the cached recents membership', () {
    shell.mergeMobileWorkspace(1, 2);
    final group = current().mobileWorkspaces.single;
    final entries = current().mobileRecentsWindows;
    for (var i = 0; i < 1200; i++) {
      final next = current().mobileWorkspaces.single.copyWith(
        scrollOffset: i.toDouble(),
      );
      shell.seed(current().copyWith(mobileWorkspaces: [next]));
      expect(current().mobileRecentsWindows, same(entries));
      expect(current().adjacentOpenAppWindow(1)?.objectId, 3);
    }
    expect(current().mobileWorkspaces.single.members, same(group.members));
  });
}
