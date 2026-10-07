import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/services/fcitx_kimpanel_service.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/osk/shell_osk_panel.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
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

  testWidgets(
    'Windows OSK paints structured Fcitx candidates as native toolbar controls',
    (tester) async {
      final selected = <int>[];
      var previousPages = 0;
      var nextPages = 0;
      const snapshot = FcitxCandidateSnapshot(
        available: true,
        visible: true,
        items: <FcitxCandidateItem>[
          FcitxCandidateItem(index: 0, label: '1', text: '你好'),
          FcitxCandidateItem(index: 1, label: '2', text: '你'),
          FcitxCandidateItem(index: 2, label: '3', text: '拟好'),
        ],
        cursor: 0,
        hasPrevious: true,
        hasNext: true,
        layoutHint: 2,
      );

      final candidateListenable = ValueNotifier(snapshot);
      addTearDown(candidateListenable.dispose);

      await tester.pumpWidget(
        _host(
          ShellOskPanel(
            candidateListenable: candidateListenable,
            onCandidateSelected: selected.add,
            onCandidatePreviousPage: () => previousPages += 1,
            onCandidateNextPage: () => nextPages += 1,
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('osk-candidates-visible')),
        findsOneWidget,
      );
      expect(find.text('你好'), findsOneWidget);
      expect(find.text('你'), findsOneWidget);

      final candidateTop = tester.getTopLeft(
        find.byKey(const ValueKey('osk-candidate-list')),
      );
      final qTop = tester.getTopLeft(find.text('q'));
      expect(candidateTop.dy, lessThan(qTop.dy));

      await tester.tap(find.byKey(const ValueKey('osk-candidate-1')));
      expect(selected, <int>[1]);

      await tester.tap(find.byKey(const ValueKey('osk-candidate-page-up')));
      await tester.tap(find.byKey(const ValueKey('osk-candidate-page-down')));
      expect(previousPages, 1);
      expect(nextPages, 1);
    },
  );

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
