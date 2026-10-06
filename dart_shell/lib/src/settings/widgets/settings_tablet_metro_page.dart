import 'package:flutter/material.dart';

import '../../localization/denial_localizations.dart';
import '../shell_settings.dart';
import 'settings_controls.dart';

class SettingsTabletMetroPage extends StatelessWidget {
  const SettingsTabletMetroPage({
    required this.settings,
    required this.onEnabledChanged,
    required this.onTileDensityChanged,
    required this.onTileOpacityChanged,
    required this.onAnimationStrengthChanged,
    required this.onShowStartHeaderChanged,
    required this.onShowSystemTilesChanged,
    required this.onShowQuickSettingsHintChanged,
    required this.onPortraitCompactChanged,
    required this.onNavigationModeChanged,
    required this.onResetStartLayout,
    required this.onReset,
    super.key,
  });

  final ShellTabletSettings settings;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<TabletTileDensity> onTileDensityChanged;
  final ValueChanged<double> onTileOpacityChanged;
  final ValueChanged<double> onAnimationStrengthChanged;
  final ValueChanged<bool> onShowStartHeaderChanged;
  final ValueChanged<bool> onShowSystemTilesChanged;
  final ValueChanged<bool> onShowQuickSettingsHintChanged;
  final ValueChanged<bool> onPortraitCompactChanged;
  final ValueChanged<TabletNavigationMode> onNavigationModeChanged;
  final VoidCallback onResetStartLayout;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return SettingsPageLayout(
      icon: Icons.tablet_android_rounded,
      eyebrow: context.l10n.settingsTabletMetroSection,
      title: context.l10n.settingsTabletMetroTitle,
      onReset: onReset,
      children: [
        SettingsCardGroup(
          children: [
            SettingsSection(
              title: context.l10n.settingsTabletMetroTitle,
              child: SettingsToggle(
                label: context.l10n.settingsTabletMetroEnable,
                description: context.l10n.settingsTabletMetroEnableDescription,
                value: settings.enabled,
                onChanged: onEnabledChanged,
              ),
            ),
            SettingsSection(
              title: context.l10n.settingsTabletMetroTileDensity,
              child: SettingsSegmentedControl<TabletTileDensity>(
                value: settings.tileDensity,
                choices: [
                  SettingsChoice(
                    TabletTileDensity.compact,
                    context.l10n.settingsTabletMetroDensityCompact,
                  ),
                  SettingsChoice(
                    TabletTileDensity.comfortable,
                    context.l10n.settingsTabletMetroDensityComfortable,
                  ),
                  SettingsChoice(
                    TabletTileDensity.spacious,
                    context.l10n.settingsTabletMetroDensitySpacious,
                  ),
                ],
                onChanged: onTileDensityChanged,
              ),
            ),
            SettingsSection(
              title: context.l10n.settingsTabletMetroTileAppearance,
              child: SettingsSlider(
                label: context.l10n.settingsTabletMetroTileOpacity,
                value: settings.tileOpacity,
                minimum: 0.55,
                maximum: 1,
                divisions: 18,
                valueLabel: '${(settings.tileOpacity * 100).round()}%',
                onChanged: onTileOpacityChanged,
              ),
            ),
          ],
        ),
        SettingsCardGroup(
          children: [
            SettingsSection(
              title: context.l10n.settingsTabletMetroStartScreen,
              child: Column(
                children: [
                  SettingsToggle(
                    label: context.l10n.settingsTabletMetroShowHeader,
                    description:
                        context.l10n.settingsTabletMetroShowHeaderDescription,
                    value: settings.showStartHeader,
                    onChanged: onShowStartHeaderChanged,
                  ),
                  const SizedBox(height: 14),
                  SettingsToggle(
                    label: context.l10n.settingsTabletMetroShowSystemTiles,
                    description: context
                        .l10n
                        .settingsTabletMetroShowSystemTilesDescription,
                    value: settings.showSystemTiles,
                    onChanged: onShowSystemTilesChanged,
                  ),
                  const SizedBox(height: 14),
                  SettingsToggle(
                    label: context.l10n.settingsTabletMetroQuickSettingsHint,
                    description: context
                        .l10n
                        .settingsTabletMetroQuickSettingsHintDescription,
                    value: settings.showQuickSettingsHint,
                    onChanged: onShowQuickSettingsHintChanged,
                  ),
                ],
              ),
            ),
            SettingsSection(
              title: context.l10n.settingsTabletMetroPortraitMode,
              child: SettingsToggle(
                label: context.l10n.settingsTabletMetroCompactPortrait,
                description:
                    context.l10n.settingsTabletMetroCompactPortraitDescription,
                value: settings.portraitCompact,
                onChanged: onPortraitCompactChanged,
              ),
            ),
          ],
        ),
        SettingsCardGroup(
          children: [
            SettingsSection(
              title: context.l10n.settingsTabletMetroStartLayout,
              trailing: SettingsTextButton(
                label: context.l10n.settingsTabletMetroResetStart,
                onPressed: onResetStartLayout,
              ),
              child: Text(
                context.l10n.settingsTabletMetroResetStartDescription,
              ),
            ),
            SettingsSection(
              title: context.l10n.settingsTabletMetroNavigation,
              child: SettingsSegmentedControl<TabletNavigationMode>(
                value: settings.navigationMode,
                choices: [
                  SettingsChoice(
                    TabletNavigationMode.gesture,
                    context.l10n.settingsTabletMetroGestures,
                  ),
                  SettingsChoice(
                    TabletNavigationMode.threeButton,
                    context.l10n.settingsTabletMetroThreeButton,
                  ),
                ],
                onChanged: onNavigationModeChanged,
              ),
            ),
            SettingsSection(
              title: context.l10n.settingsTabletMetroMotion,
              child: SettingsSlider(
                label: context.l10n.settingsTabletMetroLauncherAnimation,
                value: settings.animationStrength,
                minimum: 0,
                maximum: 1.5,
                divisions: 15,
                valueLabel: settings.animationStrength == 0
                    ? context.l10n.settingsTabletMetroAnimationOff
                    : '${(settings.animationStrength * 100).round()}%',
                onChanged: onAnimationStrengthChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
