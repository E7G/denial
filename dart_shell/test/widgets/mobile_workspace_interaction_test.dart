import 'package:denial_dart_shell/src/features/mobile/mobile_workspace_stage.dart';
import 'package:denial_dart_shell/src/local_apps/local_flutter_application.dart';
import 'package:denial_dart_shell/src/local_apps/local_flutter_window_host.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/models/mobile_workspace.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:denial_dart_shell/src/widgets/overview/overview_window_card.dart';
import 'package:denial_dart_shell/src/widgets/overview/overview_workspace_drag_feedback.dart';
import 'package:denial_dart_shell/src/widgets/overview/overview_workspace_preview.dart';
import 'package:denial_dart_shell/src/widgets/window_content_rect.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_motion_harness.dart';

class _Shell extends ShellController {
  @override
  ShellState build() => ShellState.initial().copyWith(
    windows: [motionWindow(1), motionWindow(2)],
    foregroundObjectId: 1,
  );
  void lockForTest() =>
      state = state.copyWith(locked: true, lockLayerVisible: true);
  @override
  void focusWindow(DenialWindow window) =>
      state = state.copyWith(foregroundObjectId: window.objectId);
}

void main() {
  testWidgets(
    'long-press drop merges cards without triggering swipe dismissal',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final shell = _Shell();
      var dismissals = 0;
      final scene = mobileMotionHarness(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => Row(
                children: [
                  for (var id = 1; id <= 2; id++)
                    Expanded(
                      child: OverviewWindowCard(
                        key: ValueKey('card-$id'),
                        window: motionWindow(id),
                        cardSize: const Size(240, 320),
                        foreground: false,
                        onDismiss: (_) => dismissals++,
                        onFocus: (_, _) {},
                        onMerge: shell.mergeMobileWorkspace,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        size: const Size(800, 600),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [shellControllerProvider.overrideWith(() => shell)],
          child: Consumer(
            builder: (_, ref, child) {
              ref.watch(shellControllerProvider);
              return child!;
            },
            child: scene,
          ),
        ),
      );
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('card-1'))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 30));
      await pointer.moveTo(
        tester.getCenter(find.byKey(const ValueKey('card-2'))),
      );
      await tester.pump();
      await pointer.up();
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OverviewWindowCard).first),
      );
      expect(
        container.read(shellControllerProvider).mobileWorkspaces.single.members,
        [2, 1],
      );
      expect(dismissals, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an active drag avatar hides app metadata immediately when locked',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final shell = _Shell();
      final scene = mobileMotionHarness(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => Row(
                children: [
                  for (var id = 1; id <= 2; id++)
                    Expanded(
                      child: OverviewWindowCard(
                        key: ValueKey('card-$id'),
                        window: motionWindow(id),
                        cardSize: const Size(240, 320),
                        foreground: false,
                        onDismiss: (_) {},
                        onFocus: (_, _) {},
                        onMerge: shell.mergeMobileWorkspace,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        size: const Size(800, 600),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [shellControllerProvider.overrideWith(() => shell)],
          child: Consumer(
            builder: (_, ref, child) {
              ref.watch(shellControllerProvider);
              return child!;
            },
            child: scene,
          ),
        ),
      );
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('card-1'))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 30));
      expect(find.byType(OverviewWorkspaceDragFeedback), findsOneWidget);
      expect(find.text('App 1'), findsOneWidget);
      shell.lockForTest();
      await tester.pump();
      expect(find.text('App 1'), findsNothing);
      await pointer.moveTo(
        tester.getCenter(find.byKey(const ValueKey('card-2'))),
      );
      await pointer.up();
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OverviewWindowCard).first),
      );
      expect(container.read(shellControllerProvider).mobileWorkspaces, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  MobileWorkspaceStage stage(
    MobileWorkspace group, {
    void Function(int, double)? resize,
    void Function(bool)? resizeEnd,
    bool presented = true,
    Map<int, DenialWindow>? windows,
  }) => MobileWorkspaceStage(
    key: const ValueKey('workspace'),
    workspace: group,
    windows: windows ?? {1: motionWindow(1), 2: motionWindow(2)},
    focusedObjectId: 1,
    presented: presented,
    onFocus: (_) {},
    onClose: (_) {},
    onUngroup: () {},
    onMode: (_) {},
    onScroll: (_) {},
    onScrollEnd: () {},
    onResizeStart: () {},
    onResize: resize ?? (_, _) {},
    onResizeEnd: resizeEnd ?? (_) {},
  );

  testWidgets('scrolling retains the same pane elements and source sizes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final group = MobileWorkspace(
      id: 1,
      members: [1, 2],
      mode: MobileWorkspaceMode.scrolling,
    );
    Widget frame(MobileWorkspace model) => ProviderScope(
      child: mobileMotionHarness(stage(model), size: const Size(1024, 768)),
    );
    await tester.pumpWidget(frame(group));
    final pane = find.byKey(const ValueKey('workspace-content-1'));
    final element = pane.evaluate().single;
    final before = tester.getRect(pane);
    await tester.pumpWidget(frame(group.copyWith(scrollOffset: 100)));
    expect(pane.evaluate().single, same(element));
    expect(tester.getRect(pane).size, before.size);
    expect(tester.getRect(pane).left, closeTo(before.left - 100, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the pane divider accepts touch resize without stealing app gestures',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final moves = <(int, double)>[];
      final endings = <bool>[];
      await tester.pumpWidget(
        ProviderScope(
          child: mobileMotionHarness(
            stage(
              MobileWorkspace(id: 1, members: [1, 2]),
              resize: (index, delta) => moves.add((index, delta)),
              resizeEnd: endings.add,
            ),
            size: const Size(1024, 768),
          ),
        ),
      );
      await tester.drag(
        find.bySemanticsLabel('Drag to resize panes'),
        const Offset(60, 0),
      );
      await tester.pumpAndSettle();
      expect(moves, isNotEmpty);
      expect(moves.every((move) => move.$1 == 0 && move.$2 > 0), isTrue);
      expect(endings, [false]);
    },
  );

  testWidgets(
    'local app gets its real canvas size instead of full output metrics',
    (tester) async {
      Size? appSize;
      final registry = LocalFlutterApplicationRegistry([
        LocalFlutterApplication(
          id: 'metrics.test',
          title: 'Metrics',
          builder: (context, _) {
            appSize = MediaQuery.sizeOf(context);
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
            WindowContentRect(
              window: motionWindow(
                2,
                appId: 'metrics.test',
                contentKind: DenialWindowContentKind.localFlutter,
              ),
              fit: BoxFit.contain,
            ),
            size: const Size(1024, 768),
          ),
        ),
      );
      expect(appSize, const Size(400, 800));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'overview does not mount a local app twice behind a workspace preview',
    (tester) async {
      final local = motionWindow(
        2,
        contentKind: DenialWindowContentKind.localFlutter,
      );
      await tester.pumpWidget(
        ProviderScope(
          child: mobileMotionHarness(
            Stack(
              children: [
                Positioned.fill(
                  child: stage(
                    MobileWorkspace(id: 1, members: [1, 2]),
                    presented: false,
                    windows: {1: motionWindow(1), 2: local},
                  ),
                ),
                OverviewWorkspacePreview(
                  previewKey: const ValueKey('group-preview'),
                  windows: [motionWindow(1), local],
                  size: const Size(180, 240),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(LocalFlutterWindowHost), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
