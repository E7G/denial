import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/settings/fingerprint/fingerprint_service.dart';
import 'package:denial_dart_shell/src/settings/settings_application.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_navigation.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Mi Pad 2 phone settings page is full bleed horizontally', (
    tester,
  ) async {
    const size = Size(768, 1024);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shellSettingsProvider.overrideWith(_SettingsMemory.new),
          fingerprintDeviceProvider.overrideWith(
            (_) => Stream<bool>.value(false),
          ),
        ],
        child: DenialLocalizationScope(
          locale: const Locale('zh'),
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: MediaQuery(
              data: const MediaQueryData(size: size),
              child: ShellTheme(
                data: const ShellThemeData(),
                child: const DenialSettingsApplication(
                  initialPage: SettingsPageId.language,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Phone mode first opens the category list. Select Language to enter the
    // detail page and exercise the application page canvas.
    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();

    final page = find.byKey(
      const ValueKey<String>('settings-phone-page-fullbleed'),
    );
    expect(page, findsOneWidget);
    final rect = tester.getRect(page);
    expect(rect.left, closeTo(0, 0.001));
    expect(rect.right, closeTo(size.width, 0.001));
    expect(rect.width, closeTo(size.width, 0.001));
    expect(tester.takeException(), isNull);
  });
}

class _SettingsMemory extends ShellSettingsController {
  @override
  ShellSettings build() => const ShellSettings();
}
