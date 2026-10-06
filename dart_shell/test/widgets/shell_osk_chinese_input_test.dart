import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/osk/shell_osk_panel.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'OSK toggles the external Fcitx input method and shows its mode',
    (tester) async {
      final intents = <ShellOskKeyIntent>[];

      await tester.pumpWidget(
        DenialLocalizationScope(
          locale: const Locale('zh'),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(),
              child: ShellTheme(
                data: const ShellThemeData(),
                child: SizedBox(
                  width: 768,
                  height: 360,
                  child: ShellOskPanel(onKey: intents.add),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('英'), findsOneWidget);
      expect(find.text('中'), findsNothing);

      await tester.tap(find.text('英'));
      await tester.pump(const Duration(milliseconds: 700));

      expect(intents, hasLength(1));
      expect(intents.single.action, ShellOskKeyAction.key);
      expect(intents.single.key, 'space');
      expect(intents.single.ctrl, isTrue);
      expect(find.text('中'), findsOneWidget);
      expect(find.text('英'), findsNothing);

      await tester.tap(find.text('中'));
      await tester.pump(const Duration(milliseconds: 700));

      expect(intents, hasLength(2));
      expect(intents.last.action, ShellOskKeyAction.key);
      expect(intents.last.key, 'space');
      expect(intents.last.ctrl, isTrue);
      expect(find.text('英'), findsOneWidget);
    },
  );
}
