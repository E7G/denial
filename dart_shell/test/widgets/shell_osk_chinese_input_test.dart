import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/osk/shell_osk_panel.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return ProviderScope(
    child: DenialLocalizationScope(
      locale: const Locale('zh'),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: ShellTheme(
            data: const ShellThemeData(),
            child: SizedBox(width: 768, height: 360, child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'Windows OSK toggles the external Fcitx input method and shows its mode',
    (tester) async {
      final intents = <ShellOskKeyIntent>[];

      await tester.pumpWidget(_host(ShellOskPanel(onKey: intents.add)));

      expect(find.text('ENG'), findsWidgets);
      expect(find.text('中'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('osk-language-toggle')));
      await tester.pump(const Duration(milliseconds: 120));

      expect(intents, hasLength(1));
      expect(intents.single.action, ShellOskKeyAction.key);
      expect(intents.single.key, 'space');
      expect(intents.single.ctrl, isTrue);
      expect(find.text('中'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('osk-language-toggle')));
      await tester.pump(const Duration(milliseconds: 120));

      expect(intents, hasLength(2));
      expect(intents.last.action, ShellOskKeyAction.key);
      expect(intents.last.key, 'space');
      expect(intents.last.ctrl, isTrue);
      expect(find.text('ENG'), findsWidgets);
    },
  );

  testWidgets('Windows OSK hosts IME candidates in its top toolbar row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ShellOskPanel(
          candidateBar: ColoredBox(
            color: Color(0xFF202020),
            child: Center(child: Text('候选词')),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('osk-candidate-strip')), findsOneWidget);
    expect(find.text('候选词'), findsOneWidget);
    final candidateTop = tester.getTopLeft(
      find.byKey(const ValueKey('osk-candidate-strip')),
    );
    final qTop = tester.getTopLeft(find.text('q'));
    expect(candidateTop.dy, lessThan(qTop.dy));
  });

  testWidgets(
    'Windows OSK exposes emoji, layout chooser, traditional keys and hide action',
    (tester) async {
      final intents = <ShellOskKeyIntent>[];
      var dismissed = false;

      await tester.pumpWidget(
        _host(
          ShellOskPanel(onKey: intents.add, onDismiss: () => dismissed = true),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('osk-emoji-pane')));
      await tester.pump();
      expect(find.text('😀'), findsOneWidget);
      await tester.tap(find.text('😀'));
      await tester.pump();
      expect(intents.last.action, ShellOskKeyAction.text);
      expect(intents.last.text, '😀');

      await tester.tap(find.byKey(const ValueKey('osk-layout-pane')));
      await tester.pump();
      expect(find.text('默认'), findsOneWidget);
      expect(find.text('拆分'), findsOneWidget);
      expect(find.text('传统'), findsOneWidget);

      await tester.tap(find.text('传统'));
      await tester.pump();
      expect(find.text('Esc'), findsOneWidget);
      expect(find.text('Tab'), findsOneWidget);
      expect(find.text('Ctrl'), findsOneWidget);
      expect(find.text('Del'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('osk-hide-keyboard')));
      expect(dismissed, isTrue);
    },
  );
}
