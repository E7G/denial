import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../local_apps/local_flutter_application.dart';
import '../localization/denial_localizations.dart';
import '../state/shell_controller.dart';
import '../theme/shell_theme.dart';
import 'settings_application.dart';
import 'widgets/settings_navigation.dart';

const denialSettingsLocalApplicationId = 'dev.denial.settings.local';

final denialSettingsLocalApplication = LocalFlutterApplication(
  id: denialSettingsLocalApplicationId,
  title: 'Settings',
  defaultSize: const Size(768, 1024),
  minimumSize: const Size(320, 480),
  singleInstance: true,
  showInLauncher: false,
  icon: Icons.settings_rounded,
  categories: const <String>['Settings', 'System'],
  localizedTitle: (context) => context.l10n.settingsNavigationSection,
  builder: (context, window) => const SettingsApplicationSurface(),
);

/// Opens Settings as a real Denial local application.
///
/// Every shell entry point routes through this function. Settings therefore
/// participates in the normal application stack, overview, switching and
/// single-instance lifecycle instead of living in ShellSurfaceHost as an
/// overlay.
void showSettingsApplication(
  BuildContext context,
  WidgetRef ref, {
  SettingsPageId page = SettingsPageId.appearance,
}) {
  ref.read(shellControllerProvider.notifier).closeQuickSettings();
  ref.read(settingsPageOpenRequestProvider.notifier).request(page);

  // Mobile local Flutter applications own the complete current Flutter view.
  // Their content receives the status-bar/safe-area inset through
  // WindowContentRect, so no extra work-area margin belongs in native window
  // geometry. Using MediaQuery also avoids coupling application launch to the
  // asynchronous display-layout service.
  final bounds = Offset.zero & MediaQuery.sizeOf(context);
  ref
      .read(localFlutterApplicationLauncherProvider)
      .launch(
        denialSettingsLocalApplicationId,
        availableBounds: bounds,
        geometry: bounds,
        title: 'Settings',
      );
}

class SettingsApplicationSurface extends ConsumerWidget {
  const SettingsApplicationSurface({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shellTheme = context.shellTheme;
    final materialTheme = shellTheme.toMaterialTheme();
    final locale = Localizations.maybeLocaleOf(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Denial Settings',
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: materialTheme,
      darkTheme: materialTheme,
      themeMode: shellTheme.brightness == Brightness.light
          ? ThemeMode.light
          : ThemeMode.dark,
      home: const DenialSettingsApplication(),
    );
  }
}
