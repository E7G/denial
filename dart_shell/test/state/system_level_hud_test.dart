import 'dart:async';

import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/state/system_level_hud.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presents a mute change even when the output level is unchanged', () {
    final harness = _HudHarness();

    harness.audio.add(
      const DenialAudioState(
        level: 0.65,
        requestSerial: 0,
        completesRead: true,
      ),
    );
    harness.audio.add(
      const DenialAudioState(level: 0.65, requestSerial: 0, muted: true),
    );

    final hud = harness.container.read(systemLevelHudProvider);
    expect(hud?.kind, SystemLevelHudKind.audio);
    expect(hud?.level, 0.65);
    expect(hud?.muted, isTrue);
    expect(hud?.limitReached, isFalse);
  });

  test('ignores unchanged background audio publications', () {
    final harness = _HudHarness();

    harness.audio.add(const DenialAudioState(level: 0.55, requestSerial: 0));
    final revision = harness.container.read(systemLevelHudProvider)?.revision;
    harness.audio.add(const DenialAudioState(level: 0.55, requestSerial: 0));

    expect(harness.container.read(systemLevelHudProvider)?.revision, revision);
  });

  test('restarts limit feedback for repeated adjustments at the boundary', () {
    final harness = _HudHarness();

    harness.audio.add(
      const DenialAudioState(
        level: 0.95,
        requestSerial: 0,
        completesRead: true,
      ),
    );
    harness.audio.add(
      const DenialAudioState(level: 1, requestSerial: 0, limitReached: true),
    );
    final first = harness.container.read(systemLevelHudProvider);
    harness.audio.add(
      const DenialAudioState(level: 1, requestSerial: 0, limitReached: true),
    );
    final second = harness.container.read(systemLevelHudProvider);

    expect(first?.limitReached, isTrue);
    expect(second?.revision, (first?.revision ?? 0) + 1);
  });
}

class _HudHarness {
  _HudHarness() {
    container = ProviderContainer(
      overrides: [
        systemLevelHudSignalsProvider.overrideWithValue((
          audio: audio.stream,
          brightness: brightness.stream,
        )),
        systemLevelHudVisibleDurationProvider.overrideWithValue(
          const Duration(days: 1),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await audio.close();
      await brightness.close();
    });
    container.read(systemLevelHudProvider);
  }

  final StreamController<DenialAudioState> audio =
      StreamController<DenialAudioState>.broadcast(sync: true);
  final StreamController<DenialBrightnessState> brightness =
      StreamController<DenialBrightnessState>.broadcast(sync: true);

  late final ProviderContainer container;
}
