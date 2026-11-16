import 'package:denial_dart_shell/src/features/mobile/mobile_workspace_stage.dart';
import 'package:denial_dart_shell/src/input/shell_interaction_registry.dart';
import 'package:denial_dart_shell/src/local_apps/local_flutter_application.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/models/mobile_workspace.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_motion_harness.dart';

class _Calls {
  int ungroup = 0, scrollEnd = 0, resizeStart = 0;
  final scrolls = <double>[];
  final modes = <MobileWorkspaceMode>[];
  final closed = <int>[];
}

void main() {
  late _Calls calls;
  setUp(() => calls = _Calls());

  MobileWorkspaceStage stage({
    bool presented = true,
    bool scroll = false,
    Map<int, DenialWindow>? windows,
  }) => MobileWorkspaceStage(
    key: const ValueKey('stage'),
    workspace: MobileWorkspace(
      id: 1,
      members: [1, 2],
      mode: scroll
          ? MobileWorkspaceMode.scrolling
          : MobileWorkspaceMode.automatic,
    ),
    windows: windows ?? {1: motionWindow(1), 2: motionWindow(2)},
    focusedObjectId: 1,
    presented: presented,
    onFocus: (_) {},
    onClose: (window) => calls.closed.add(window.objectId),
    onUngroup: () => calls.ungroup++,
    onMode: calls.modes.add,
    onScroll: calls.scrolls.add,
    onScrollEnd: () => calls.scrollEnd++,
    onResizeStart: () => calls.resizeStart++,
    onResize: (_, _) {},
    onResizeEnd: (_) {},
  );

  Widget frame(Widget child) => ProviderScope(
    child: mobileMotionHarness(child, size: const Size(1024, 768)),
  );
  Future<void> prepare(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
  }

  testWidgets(
    'no permanent workspace toolbar or titles, real panes gain the space',
    (tester) async {
      await prepare(tester);
      await tester.pumpWidget(frame(stage()));
      expect(find.text('Workspace'), findsNothing);
      expect(find.text('App 1'), findsNothing);
      expect(find.text('Ungroup'), findsNothing);
      final rect = tester.getRect(
        find.byKey(const ValueKey('workspace-content-1')),
      );
      expect(rect, const Rect.fromLTWH(0, 48, 506, 720));
      expect(
        tester
            .getSize(find.byKey(const ValueKey('workspace-gesture-edge')))
            .height,
        8,
      );
    },
  );

  testWidgets(
    'holding divider opens transient actions without resizing clients',
    (tester) async {
      await prepare(tester);
      await tester.pumpWidget(frame(stage()));
      final content = find.byKey(const ValueKey('workspace-content-1'));
      final element = content.evaluate().single;
      final rect = tester.getRect(content);
      await tester.longPress(find.bySemanticsLabel('Drag to resize panes'));
      await tester.pump();
      expect(find.byKey(const ValueKey('workspace-actions')), findsOneWidget);
      expect(content.evaluate().single, same(element));
      expect(tester.getRect(content), rect);
      expect(calls.resizeStart, 0);
      await tester.tap(find.text('Ungroup'));
      await tester.pump();
      expect(calls.ungroup, 1);
      expect(find.byKey(const ValueKey('workspace-actions')), findsNothing);
    },
  );

  testWidgets('hold-drag the zero-layout top edge scrolls without app resize', (
    tester,
  ) async {
    await prepare(tester);
    await tester.pumpWidget(frame(stage(scroll: true)));
    final pointer = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('workspace-gesture-edge'))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 30));
    await pointer.moveBy(const Offset(-80, 0));
    await tester.pump();
    await pointer.up();
    await tester.pump();
    expect(calls.scrolls, isNotEmpty);
    expect(calls.scrolls.reduce((a, b) => a + b), closeTo(80, .001));
    expect(calls.scrollEnd, 1);
    expect(calls.resizeStart, 0);
    expect(find.byKey(const ValueKey('workspace-actions')), findsNothing);
  });

  testWidgets(
    'controls expire without reserving a toolbar or changing pane size',
    (tester) async {
      await prepare(tester);
      await tester.pumpWidget(frame(stage()));
      final rect = tester.getRect(
        find.byKey(const ValueKey('workspace-content-1')),
      );
      await tester.longPress(
        find.byKey(const ValueKey('workspace-gesture-edge')),
      );
      await tester.pump();
      expect(find.text('Ungroup'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('Ungroup'), findsNothing);
      expect(
        tester.getRect(find.byKey(const ValueKey('workspace-content-1'))),
        rect,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a secure transition removes controls and their pending timeout',
    (tester) async {
      await prepare(tester);
      await tester.pumpWidget(frame(stage()));
      await tester.longPress(
        find.byKey(const ValueKey('workspace-gesture-edge')),
      );
      await tester.pump();
      expect(find.text('Ungroup'), findsOneWidget);
      await tester.pumpWidget(frame(stage(presented: false)));
      await tester.pump();
      expect(find.text('Ungroup'), findsNothing);
      await tester.pump(const Duration(seconds: 7));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('only requested actions capture the full input scene', (
    tester,
  ) async {
    await prepare(tester);
    await tester.pumpWidget(frame(stage()));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MobileWorkspaceStage)),
    );
    expect(
      container.read(shellInteractionRegistryProvider).capturesFullScene,
      isFalse,
    );
    await tester.longPress(
      find.byKey(const ValueKey('workspace-gesture-edge')),
    );
    await tester.pump();
    await tester.pump();
    expect(
      container.read(shellInteractionRegistryProvider).capturesFullScene,
      isTrue,
    );
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump();
    expect(
      container.read(shellInteractionRegistryProvider).capturesFullScene,
      isFalse,
    );
  });

  testWidgets('local Flutter panes do not keep the removed header safe-area', (
    tester,
  ) async {
    await prepare(tester);
    double? top;
    final registry = LocalFlutterApplicationRegistry([
      LocalFlutterApplication(
        id: 'metrics.test',
        title: 'Metrics',
        builder: (context, _) {
          top = MediaQuery.paddingOf(context).top;
          return const SizedBox.expand();
        },
      ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFlutterApplicationRegistryProvider.overrideWithValue(registry),
        ],
        child: mobileMotionHarness(
          stage(
            windows: {
              1: motionWindow(1),
              2: motionWindow(
                2,
                appId: 'metrics.test',
                contentKind: DenialWindowContentKind.localFlutter,
              ),
            },
          ),
          size: const Size(1024, 768),
        ),
      ),
    );
    expect(top, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'top-edge actions stay reachable when a wide pane hides the divider',
    (tester) async {
      await prepare(tester);
      await tester.pumpWidget(
        frame(
          stage(
            scroll: true,
            windows: {
              1: motionWindow(1, minimumWidth: 1700),
              2: motionWindow(2),
            },
          ),
        ),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('workspace-content-1'))).right,
        1700,
      );
      await tester.longPress(
        find.byKey(const ValueKey('workspace-gesture-edge')),
      );
      await tester.pump();
      expect(find.text('Ungroup'), findsOneWidget);
    },
  );

  testWidgets(
    'hold-dragging the divider scrolls instead of changing its ratio',
    (tester) async {
      await prepare(tester);
      await tester.pumpWidget(frame(stage(scroll: true)));
      final pointer = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('Drag to resize panes')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 30));
      await pointer.moveBy(const Offset(-80, 0));
      await tester.pump();
      await pointer.up();
      await tester.pump();
      expect(calls.scrolls.reduce((a, b) => a + b), closeTo(80, .001));
      expect(calls.resizeStart, 0);
      expect(calls.scrollEnd, 1);
      expect(find.byKey(const ValueKey('workspace-actions')), findsNothing);
    },
  );

  testWidgets('portrait hold-drag follows the vertical tiling axis', (
    tester,
  ) async {
    await prepare(tester);
    await tester.binding.setSurfaceSize(const Size(768, 1024));
    await tester.pumpWidget(
      ProviderScope(
        child: mobileMotionHarness(
          stage(scroll: true),
          size: const Size(768, 1024),
        ),
      ),
    );
    final pointer = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('workspace-gesture-edge'))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 30));
    await pointer.moveBy(const Offset(0, -80));
    await tester.pump();
    await pointer.up();
    await tester.pump();
    expect(calls.scrolls.reduce((a, b) => a + b), closeTo(80, .001));
    expect(calls.scrollEnd, 1);
    expect(calls.resizeStart, 0);
  });

  testWidgets(
    'transient actions retain layout-mode and focused-window close operations',
    (tester) async {
      await prepare(tester);
      await tester.pumpWidget(frame(stage()));
      await tester.longPress(
        find.byKey(const ValueKey('workspace-gesture-edge')),
      );
      await tester.pump();
      await tester.tap(find.text('Auto'));
      await tester.pump();
      expect(calls.modes, [MobileWorkspaceMode.split]);
      expect(find.text('Ungroup'), findsNothing);
      await tester.longPress(
        find.byKey(const ValueKey('workspace-gesture-edge')),
      );
      await tester.pump();
      await tester.tap(find.text('Close window'));
      await tester.pump();
      expect(calls.closed, [1]);
      expect(find.text('Ungroup'), findsNothing);
    },
  );
}
