import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/shell_surface_host.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FullscreenSurfaceHarness extends ConsumerStatefulWidget {
  const _FullscreenSurfaceHarness();

  @override
  ConsumerState<_FullscreenSurfaceHarness> createState() =>
      _FullscreenSurfaceHarnessState();
}

class _FullscreenSurfaceHarnessState
    extends ConsumerState<_FullscreenSurfaceHarness> {
  var _opened = false;

  @override
  Widget build(BuildContext context) {
    if (!_opened) {
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(shellSurfaceControllerProvider.notifier)
            .show(
              debugLabel: 'fullscreen-test',
              presentation: ShellSurfacePresentation.fullscreen,
              transitionDuration: Duration.zero,
              builder: (_, _) => const ColoredBox(
                key: ValueKey('fullscreen-content'),
                color: Color(0xFF101010),
              ),
            );
      });
    }
    return const ShellSurfaceHost(
      child: ColoredBox(
        key: ValueKey('scene-content'),
        color: Color(0xFF202020),
      ),
    );
  }
}

Widget _host(Widget child) {
  return ProviderScope(
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(768, 1024)),
        child: ShellTheme(
          data: const ShellThemeData(),
          child: Center(
            child: SizedBox(
              key: const ValueKey('viewport'),
              width: 768,
              height: 1024,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'fullscreen shell surface fills viewport without modal scale gap',
    (tester) async {
      await tester.pumpWidget(_host(const _FullscreenSurfaceHarness()));
      await tester.pump();
      await tester.pump();

      final viewport = tester.getRect(find.byKey(const ValueKey('viewport')));
      final content = tester.getRect(
        find.byKey(const ValueKey('fullscreen-content')),
      );

      expect(content, viewport);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('fullscreen-content')),
          matching: find.byType(ScaleTransition),
        ),
        findsNothing,
      );
    },
  );
}
