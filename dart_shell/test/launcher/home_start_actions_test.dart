import 'package:denial_dart_shell/src/launcher/controllers/home_grid_controller.dart';
import 'package:denial_dart_shell/src/launcher/home_surface.dart';
import 'package:denial_dart_shell/src/launcher/models/desktop_app.dart';
import 'package:denial_dart_shell/src/launcher/models/home_grid_item.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_motion_harness.dart';

void main() {
  const size = Size(768, 1024);

  testWidgets('Start All apps is actionable and keeps far rows lazy', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        homeGridControllerProvider.overrideWith(_StartActionGrid.new),
        shellControllerProvider.overrideWith(_StartActionShell.new),
        shellSettingsProvider.overrideWith(_StartActionSettings.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: mobileMotionHarness(const HomeSurface(), size: size),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final allApps = find.byKey(const ValueKey<String>('start-all-apps-action'));
    expect(allApps, findsOneWidget);

    await tester.tap(allApps);
    await tester.pump();

    final firstFrameSlide = tester.widget<SlideTransition>(
      find.byKey(const ValueKey<String>('metro-app-drawer-slide-transition')),
    );
    expect(
      firstFrameSlide.position.value.dx,
      greaterThan(0.08),
      reason:
          'The first drawer mount must animate instead of appearing at rest.',
    );
    await tester.pump(const Duration(milliseconds: 110));
    final midFrameSlide = tester.widget<SlideTransition>(
      find.byKey(const ValueKey<String>('metro-app-drawer-slide-transition')),
    );
    expect(midFrameSlide.position.value.dx, inExclusiveRange(0.0, 0.08));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SlideTransition>(
            find.byKey(
              const ValueKey<String>('metro-app-drawer-slide-transition'),
            ),
          )
          .position
          .value
          .dx,
      closeTo(0, 0.0001),
    );

    final drawerInteraction = tester.widget<IgnorePointer>(
      find.byKey(const ValueKey<String>('metro-app-drawer-interaction')),
    );
    expect(drawerInteraction.ignoring, isFalse);
    expect(find.text('App 000'), findsWidgets);
    expect(find.text('App 119'), findsNothing);
  });

  testWidgets('Start Quick settings button opens the real system shade', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        homeGridControllerProvider.overrideWith(_StartActionGrid.new),
        shellControllerProvider.overrideWith(_StartActionShell.new),
        shellSettingsProvider.overrideWith(_StartActionSettings.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: mobileMotionHarness(const HomeSurface(), size: size),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(shellControllerProvider).quickSettingsVisible,
      isFalse,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('start-quick-settings-action')),
    );
    await tester.pump();
    expect(
      container.read(shellControllerProvider).quickSettingsVisible,
      isTrue,
    );
  });

  testWidgets('portrait drawer reveal begins before swipe release', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        homeGridControllerProvider.overrideWith(_StartActionGrid.new),
        shellControllerProvider.overrideWith(_StartActionShell.new),
        shellSettingsProvider.overrideWith(_StartActionSettings.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: mobileMotionHarness(const HomeSurface(), size: size),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('metro-app-drawer-interaction')),
      findsNothing,
    );

    final gesture = await tester.startGesture(const Offset(700, 930));
    await gesture.moveBy(const Offset(-64, 2));
    await tester.pump();

    final drawerInteraction = tester.widget<IgnorePointer>(
      find.byKey(const ValueKey<String>('metro-app-drawer-interaction')),
    );
    expect(drawerInteraction.ignoring, isFalse);

    await gesture.up();
    await tester.pump();
  });
}

HomeGridItem _app(int id) => HomeGridItem.app(
  DesktopApp(
    id: '$id',
    name: 'App ${id.toString().padLeft(3, '0')}',
    exec: 'unused',
    desktopPath: 'unused',
    categories: const <String>[],
  ),
);

class _StartActionGrid extends HomeGridController {
  @override
  Future<HomeGridState> build() async {
    final allItems = <HomeGridItem>[
      for (var id = 0; id < 120; id += 1) _app(id),
    ];
    return HomeGridState(
      slots: allItems.take(3).toList(growable: false),
      allItems: allItems,
    );
  }

  @override
  void setLauncherActive(bool active) {}
}

class _StartActionShell extends ShellController {
  @override
  ShellState build() => ShellState.initial(locked: false);
}

class _StartActionSettings extends ShellSettingsController {
  @override
  ShellSettings build() => const ShellSettings();
}
