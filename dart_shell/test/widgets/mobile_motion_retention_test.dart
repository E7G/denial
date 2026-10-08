import 'package:denial_dart_shell/src/features/mobile/mobile_primary_window_stage.dart';
import 'package:denial_dart_shell/src/input/input_layout.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:denial_dart_shell/src/widgets/edge_panel_layer.dart';
import 'package:denial_dart_shell/src/widgets/window_content_rect.dart';
import 'package:denial_dart_shell/src/widgets/osk/shell_osk_panel.dart';
import 'package:denial_dart_shell/src/widgets/overview/overview_grid.dart';
import 'package:denial_dart_shell/src/widgets/overview/overview_window_preview.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_motion_harness.dart';

void main() {
  testWidgets('hiding a retained keyboard releases a held key', (tester) async {
    final intents = <ShellOskKeyIntent>[];
    Widget keyboard(bool enabled) => ProviderScope(
      child: mobileMotionHarness(
        Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: 320,
            child: TickerMode(
              enabled: enabled,
              child: ShellOskPanel(onKey: intents.add),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(keyboard(true));
    final backspace = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == 'Backspace',
    );
    final pointer = await tester.startGesture(tester.getCenter(backspace));
    await tester.pump();
    expect(intents.map((intent) => intent.phase), [ShellOskKeyPhase.pressed]);
    final element = find.byType(ShellOskPanel).evaluate().single;
    await tester.pumpWidget(keyboard(false));
    expect(find.byType(ShellOskPanel).evaluate().single, same(element));
    expect(intents.map((intent) => intent.phase), [
      ShellOskKeyPhase.pressed,
      ShellOskKeyPhase.released,
    ]);
    await pointer.cancel();
    await tester.pumpAndSettle();
    expect(intents, hasLength(2));
    await tester.pumpWidget(keyboard(true));
    final letter = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == 'q',
    );
    final pendingTap = await tester.startGesture(tester.getCenter(letter));
    await tester.pump();
    await tester.pumpWidget(keyboard(false));
    await pendingTap.up();
    await tester.pumpAndSettle();
    expect(
      intents,
      hasLength(2),
      reason: 'An inactive key must not finish a pending tap',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('switch start, cancellation and promotion retain app elements', (
    tester,
  ) async {
    final drag = ValueNotifier(0.0);
    addTearDown(drag.dispose);
    final first = motionWindow(1);
    final second = motionWindow(2);
    Widget stage({bool switching = false, bool promoted = false}) =>
        ProviderScope(
          child: mobileMotionHarness(
            MobilePrimaryWindowStage(
              currentWindow: promoted ? second : first,
              switchTargetWindow: switching ? second : null,
              switchDragX: drag,
              opacity: 1,
            ),
          ),
        );
    final current = find.byKey(const ValueKey<int>(1));
    await tester.pumpWidget(stage());
    final element = current.evaluate().single;
    final original = tester.getRect(current);
    drag.value = -40;
    await tester.pumpWidget(stage(switching: true));
    expect(current.evaluate().single, same(element));
    expect(tester.getRect(current), original.shift(const Offset(-40, 0)));
    // Removing the target resets translation even if the last drag is nonzero.
    await tester.pumpWidget(stage());
    expect(current.evaluate().single, same(element));
    expect(tester.getRect(current), original);
    await tester.pumpWidget(stage(switching: true));
    final target = find.byKey(const ValueKey<int>(2));
    final targetElement = target.evaluate().single;
    await tester.pumpWidget(stage(promoted: true));
    expect(target.evaluate().single, same(targetElement));
    expect(tester.getRect(target), original);
    expect(current, findsNothing);
  });

  testWidgets('native mobile stage keeps the complete client source frame', (
    tester,
  ) async {
    final drag = ValueNotifier(0.0);
    addTearDown(drag.dispose);
    final window = motionWindow(7);
    await tester.pumpWidget(
      ProviderScope(
        child: mobileMotionHarness(
          MobilePrimaryWindowStage(
            currentWindow: window,
            switchTargetWindow: null,
            switchDragX: drag,
            opacity: 1,
          ),
        ),
      ),
    );

    final content = tester.widget<WindowContentRect>(
      find.byType(WindowContentRect),
    );
    expect(content.cropToContentBounds, isTrue);
    expect(content.sourceCropTop, 0.0);
  });

  testWidgets(
    '30 landscape previews move for 60 frames without widget builds',
    (tester) async {
      const size = Size(1000, 600);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final progress = AnimationController(vsync: tester);
      addTearDown(progress.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: mobileMotionHarness(
            OverviewGrid(
              windows: [for (var id = 0; id < 30; id++) motionWindow(id)],
              progress: progress,
              foregroundObjectId: 0,
              onDismissWindow: (_) {},
              onFocusWindow: (_, _) {},
            ),
            size: size,
          ),
        ),
      );
      final previews = find.byType(OverviewWindowPreview);
      expect(previews, findsNWidgets(30));
      final before = tester.getTopLeft(previews.last);
      final builds = <String>[];
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, _) =>
          builds.add(element.widget.runtimeType.toString());
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      for (var frame = 1; frame <= 60; frame++) {
        progress.value = frame / 60;
        await tester.pump();
      }
      expect(tester.getTopLeft(previews.last), isNot(before));
      expect(builds, isEmpty);
    },
  );

  testWidgets(
    'floating keyboard moves and resizes without moving application content',
    (tester) async {
      const size = Size(768, 1024);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final shell = _MotionShell();
      final settings = _FloatingSettingsMemory();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shellControllerProvider.overrideWith(() => shell),
            shellSettingsProvider.overrideWith(
              () => _FloatingSettingsController(settings),
            ),
          ],
          child: mobileMotionHarness(
            const Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  key: ValueKey('floating-app-content'),
                  color: Color(0xff123456),
                ),
                EdgePanelLayer(),
              ],
            ),
            size: size,
          ),
        ),
      );

      shell.position(1);
      await tester.pumpAndSettle();

      final surface = find.byKey(const ValueKey('floating-osk-surface'));
      expect(surface, findsOneWidget);
      final before = tester.getRect(surface);
      expect(before.width, closeTo(470, 0.1));
      expect(before.height, closeTo(300, 0.1));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('floating-app-content'))),
        Offset.zero,
      );

      final moveHandle = find.byKey(const ValueKey('osk-floating-move-handle'));
      final move = await tester.startGesture(tester.getCenter(moveHandle));
      await move.moveBy(const Offset(-60, -80));
      await move.up();
      await tester.pump();

      final moved = tester.getRect(surface);
      expect(moved.left, lessThan(before.left));
      expect(moved.top, lessThan(before.top));
      expect(
        settings.value.tablet.oskFloatingPortrait.x,
        closeTo(moved.left, 0.1),
      );
      expect(
        settings.value.tablet.oskFloatingPortrait.y,
        closeTo(moved.top, 0.1),
      );

      final resizeHandle = find.byKey(
        const ValueKey('osk-floating-resize-handle'),
      );
      final resize = await tester.startGesture(tester.getCenter(resizeHandle));
      await resize.moveBy(const Offset(-40, -30));
      await resize.up();
      await tester.pump();

      final resized = tester.getRect(surface);
      expect(resized.width, lessThan(moved.width));
      expect(resized.height, lessThan(moved.height));
      expect(
        settings.value.tablet.oskFloatingPortrait.width,
        closeTo(resized.width, 0.1),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('floating-app-content'))),
        Offset.zero,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard slides and viewport pans retain content and build only at phase changes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final shell = _MotionShell();
      const contentKey = ValueKey('viewport-content');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [shellControllerProvider.overrideWith(() => shell)],
          child: mobileMotionHarness(
            const Stack(
              fit: StackFit.expand,
              children: [
                MobileKeyboardViewport(
                  child: ColoredBox(key: contentKey, color: Color(0xffabcdef)),
                ),
                EdgePanelLayer(),
              ],
            ),
          ),
        ),
      );
      final keyboard = find.byType(ShellOskPanel, skipOffstage: false);
      final keyboardElement = keyboard.evaluate().single;
      shell.position(0.1);
      await tester.pump();
      final builds = <String>[];
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, _) {
        // Riverpod's scheduler rebuilds its root scope to flush notifications.
        // Count the UI boundaries and their descendants, not that scheduler.
        if (element.widget is MobileKeyboardViewport ||
            element.widget is EdgePanelLayer ||
            element.findAncestorWidgetOfExactType<MobileKeyboardViewport>() !=
                null ||
            element.findAncestorWidgetOfExactType<EdgePanelLayer>() != null) {
          builds.add(element.widget.runtimeType.toString());
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      final height = ShellMetrics.edgePanelHeight(const Size(400, 800));
      for (var frame = 1; frame <= 60; frame++) {
        final progress = 0.1 + frame / 100;
        final scroll = frame.toDouble();
        shell.position(progress, scroll: scroll);
        await tester.pump();
        expect(tester.getTopLeft(find.byKey(contentKey)), Offset.zero);
        expect(keyboard.evaluate().single, same(keyboardElement));
      }
      expect(builds, isEmpty);
      debugOnRebuildDirtyWidget = previous;
      // Exercise the real close path: even stale viewport-pan state must never
      // move the app, and dismissal still clears that legacy state.
      shell.closeEdgePanel();
      await tester.pump();
      expect(shell.state.edgePanelViewportScroll, 0.0);
      // The content must snap back immediately; the keyboard itself may still
      // be finishing its short exit animation during this frame.
      expect(tester.getTopLeft(find.byKey(contentKey)), Offset.zero);
      await tester.pumpAndSettle();
      expect(find.byType(ShellOskPanel), findsNothing);
      expect(keyboard.evaluate().single, same(keyboardElement));
      shell.position(0.5);
      await tester.pump();
      expect(
        find.byType(ShellOskPanel).evaluate().single,
        same(keyboardElement),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _FloatingSettingsMemory {
  ShellSettings value = const ShellSettings(
    tablet: ShellTabletSettings(oskLayoutMode: TabletOskLayoutMode.floating),
  );
}

class _FloatingSettingsController extends ShellSettingsController {
  _FloatingSettingsController(this.memory);

  final _FloatingSettingsMemory memory;

  @override
  ShellSettings build() => memory.value;

  @override
  void setTabletOskFloatingPlacement({
    required bool portrait,
    required TabletOskFloatingPlacement placement,
  }) {
    memory.value = state.copyWith(
      tablet: portrait
          ? state.tablet.copyWith(oskFloatingPortrait: placement)
          : state.tablet.copyWith(oskFloatingLandscape: placement),
    );
    state = memory.value;
  }

  @override
  void setTabletOskFloatingLocked(bool value) {
    memory.value = state.copyWith(
      tablet: state.tablet.copyWith(oskFloatingLocked: value),
    );
    state = memory.value;
  }
}

class _MotionShell extends ShellController {
  @override
  ShellState build() => ShellState.initial();

  void position(double progress, {double scroll = 0}) {
    state = state.copyWith(
      edgePanelDrag: Offset(0, progress * ShellMetrics.edgePanelDragDistance),
      edgePanelDragActive: true,
      edgePanelViewportScroll: scroll,
    );
  }
}
