import 'package:flutter/material.dart';

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
      eyebrow: 'TABLET SHELL',
      title: 'Tablet Metro',
      onReset: onReset,
      children: [
        SettingsCardGroup(
          children: [
            SettingsSection(
              title: 'Tablet desktop',
              child: SettingsToggle(
                label: 'Enable Metro tablet layout',
                description:
                    'Use the Square Home / Surface RT style Start screen on tablet-sized displays.',
                value: settings.enabled,
                onChanged: onEnabledChanged,
              ),
            ),
            SettingsSection(
              title: 'Tile density',
              child: SettingsSegmentedControl<TabletTileDensity>(
                value: settings.tileDensity,
                choices: const [
                  SettingsChoice(TabletTileDensity.compact, 'Compact'),
                  SettingsChoice(TabletTileDensity.comfortable, 'Comfort'),
                  SettingsChoice(TabletTileDensity.spacious, 'Spacious'),
                ],
                onChanged: onTileDensityChanged,
              ),
            ),
            SettingsSection(
              title: 'Tile appearance',
              child: SettingsSlider(
                label: 'Tile opacity',
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
              title: 'Start screen',
              child: Column(
                children: [
                  SettingsToggle(
                    label: 'Show Start header',
                    description:
                        'Show the Windows 8 style Start title and actions on wide displays.',
                    value: settings.showStartHeader,
                    onChanged: onShowStartHeaderChanged,
                  ),
                  const SizedBox(height: 14),
                  SettingsToggle(
                    label: 'Show system tiles',
                    description:
                        'Expose clock, date and battery live tiles in All apps.',
                    value: settings.showSystemTiles,
                    onChanged: onShowSystemTilesChanged,
                  ),
                  const SizedBox(height: 14),
                  SettingsToggle(
                    label: 'Quick Settings hint',
                    description:
                        'Show the swipe-down Quick Settings hint in the Start header.',
                    value: settings.showQuickSettingsHint,
                    onChanged: onShowQuickSettingsHintChanged,
                  ),
                ],
              ),
            ),
            SettingsSection(
              title: 'Portrait mode',
              child: SettingsToggle(
                label: 'Compact portrait layout',
                description:
                    'Use denser tiles and reduced Start chrome when the tablet is held vertically.',
                value: settings.portraitCompact,
                onChanged: onPortraitCompactChanged,
              ),
            ),
          ],
        ),
        SettingsCardGroup(
          children: [
            SettingsSection(
              title: 'Start layout',
              trailing: SettingsTextButton(
                label: 'Reset Start',
                onPressed: onResetStartLayout,
              ),
              child: const Text(
                'Restore the live system tiles and a small starter set of applications. All installed apps remain available in All apps.',
              ),
            ),
            SettingsSection(
              title: 'Navigation',
              child: SettingsSegmentedControl<TabletNavigationMode>(
                value: settings.navigationMode,
                choices: const [
                  SettingsChoice(TabletNavigationMode.gesture, 'Gestures'),
                  SettingsChoice(
                    TabletNavigationMode.threeButton,
                    'Back · Home · Overview',
                  ),
                ],
                onChanged: onNavigationModeChanged,
              ),
            ),
            SettingsSection(
              title: 'Motion',
              child: SettingsSlider(
                label: 'Launcher animation strength',
                value: settings.animationStrength,
                minimum: 0,
                maximum: 1.5,
                divisions: 15,
                valueLabel: settings.animationStrength == 0
                    ? 'Off'
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
