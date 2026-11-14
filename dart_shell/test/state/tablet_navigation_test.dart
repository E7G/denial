import 'package:denial_dart_shell/src/state/tablet_navigation.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:denial_dart_shell/src/launcher/controllers/home_overlay_navigation.dart';
import 'package:denial_dart_shell/src/widgets/shell_surface_host.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_motion_harness.dart';

class _Shell extends ShellController {
  int backCalls = 0;
  int homeCalls = 0;
  @override
  ShellState build() => ShellState.initial();
  void seed(ShellState value) => state = value;
  @override
  void navigateBack() => backCalls++;
  @override
  void goHome() { homeCalls++; state = state.copyWith(clearForegroundObjectId: true); }
  @override
  void closeEdgePanel() => state = state.copyWith(edgePanelVisible: false, edgePanelDrag: Offset.zero);
  @override
  void closeQuickSettings() => state = state.copyWith(quickSettingsVisible: false, quickSettingsDrag: Offset.zero);
  @override
  void openOverview() => state = state.copyWith(overviewVisible: true);
  @override
  void closeOverview() => state = state.copyWith(overviewVisible: false, clearForegroundObjectId: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Shell shell;
  late TabletNavigationController navigation;
  setUp(() {
    container = ProviderContainer(overrides: [shellControllerProvider.overrideWith(_Shell.new)]);
    shell = container.read(shellControllerProvider.notifier) as _Shell;
    navigation = container.read(tabletNavigationProvider);
  });
  tearDown(() => container.dispose());
  void surface({ShellDismissPolicy policy = ShellDismissPolicy.outsideTapAndEscape}) {
    container.read(shellSurfaceControllerProvider.notifier).show(
      debugLabel: 'test settings', dismissPolicy: policy,
      presentation: ShellSurfacePresentation.fullscreen,
      builder: (_, _) => const SizedBox(),
    );
  }
  test('locked navigation cannot dismiss a surface or change apps', () {
    surface(); shell.seed(ShellState.initial(locked: true));
    navigation.back(); navigation.home(); navigation.overview();
    expect(container.read(shellSurfaceControllerProvider), hasLength(1));
    expect(shell.backCalls + shell.homeCalls, 0);
    expect(container.read(shellControllerProvider).overviewVisible, isFalse);
  });
  test('Back hides keyboard before dismissing Settings', () {
    surface(); shell.seed(container.read(shellControllerProvider).copyWith(edgePanelVisible: true));
    navigation.back();
    expect(container.read(shellControllerProvider).edgePanelVisible, isFalse);
    expect(container.read(shellSurfaceControllerProvider).single.closing, isFalse);
    expect(shell.backCalls, 0);
  });
  test('Back dismisses the top ordinary Settings surface', () {
    surface(); navigation.back();
    expect(container.read(shellSurfaceControllerProvider).single.closing, isTrue);
    expect(shell.backCalls, 0);
  });
  test('protected prompts are not bypassed by any navigation button', () {
    surface(policy: ShellDismissPolicy.none);
    navigation.back(); navigation.home(); navigation.overview();
    expect(container.read(shellSurfaceControllerProvider).single.closing, isFalse);
    expect(shell.backCalls + shell.homeCalls, 0);
    expect(container.read(shellControllerProvider).overviewVisible, isFalse);
  });
  test('Home dismisses ordinary Settings and returns from an app', () {
    surface(); shell.seed(container.read(shellControllerProvider).copyWith(windows: [motionWindow(1)], foregroundObjectId: 1));
    navigation.home();
    expect(container.read(shellSurfaceControllerProvider), isEmpty);
    expect(shell.homeCalls, 1);
  });
  test('Overview dismisses Settings and toggles recent tasks', () {
    surface(); navigation.overview();
    expect(container.read(shellSurfaceControllerProvider), isEmpty);
    expect(container.read(shellControllerProvider).overviewVisible, isTrue);
    navigation.overview();
    expect(container.read(shellControllerProvider).overviewVisible, isFalse);
  });
  test('Back first delegates to an open launcher modal', () {
    container.read(homeOverlayNavigationProvider.notifier).setModalOpen(true);
    navigation.back();
    expect(container.read(homeOverlayNavigationProvider).backRequestSerial, 1);
    expect(shell.backCalls, 0);
  });
  test('Back without overlays uses the shell compatibility action', () {
    navigation.back(); expect(shell.backCalls, 1);
  });
}
