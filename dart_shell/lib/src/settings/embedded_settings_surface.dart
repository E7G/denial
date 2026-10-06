import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../state/shell_controller.dart';
import '../theme/shell_theme.dart';
import '../widgets/shell_surface_host.dart';
import 'settings_application.dart';
import 'widgets/settings_navigation.dart';

const _embeddedSettingsSurfaceKey = 'embedded-settings';

void showEmbeddedSettingsSurface(
  WidgetRef ref, {
  SettingsPageId page = SettingsPageId.appearance,
}) {
  ref.read(shellControllerProvider.notifier).closeQuickSettings();
  ref.read(settingsPageOpenRequestProvider.notifier).request(page);
  ref
      .read(shellSurfaceControllerProvider.notifier)
      .show(
        keyName: _embeddedSettingsSurfaceKey,
        debugLabel: 'Embedded Settings',
        dismissPolicy: ShellDismissPolicy.outsideTapAndEscape,
        builder: (_, handle) => EmbeddedSettingsSurface(
          initialPage: page,
          onClose: handle.close,
        ),
      );
}

/// Settings hosted directly inside Denial's primary Flutter scene.
///
/// Mobile/tablet uses this instead of launching the standalone Wayland
/// Settings client. Keeping Settings in the primary scene avoids an additional
/// client surface/backing-store allocation and shares the already-synchronized
/// settings providers with the shell.
class EmbeddedSettingsSurface extends ConsumerWidget {
  const EmbeddedSettingsSurface({
    required this.initialPage,
    required this.onClose,
    super.key,
  });

  final SettingsPageId initialPage;
  final VoidCallback onClose;

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
      home: Stack(
        fit: StackFit.expand,
        children: [
          DenialSettingsApplication(initialPage: initialPage),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              minimum: const EdgeInsets.all(4),
              child: _EmbeddedSettingsCloseButton(onPressed: onClose),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmbeddedSettingsCloseButton extends StatelessWidget {
  const _EmbeddedSettingsCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      elevation: 2,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.close_rounded),
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
      ),
    );
  }
}
