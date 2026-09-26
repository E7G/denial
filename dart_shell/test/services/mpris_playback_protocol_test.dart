import 'dart:math';

import 'package:dbus/dbus.dart';
import 'package:denial_dart_shell/src/models/mpris_playback.dart';
import 'package:denial_dart_shell/src/services/mpris_playback_protocol.dart';
import 'package:test/test.dart';

import '../support/legacy_mpris_protocol.dart';

void main() {
  final observed = DateTime(2026, 1, 1);
  final now = observed.add(const Duration(seconds: 2));
  final initial = parseMprisPlaybackState(
    'org.mpris.MediaPlayer2.player.instance',
    {
      'PlaybackStatus': const DBusString('Playing'),
      'Position': const DBusInt64(1000000),
      'CanPlay': const DBusBoolean(true),
      'CanPause': const DBusBoolean(true),
      'Metadata': _metadata(),
    },
    {'Identity': const DBusString('Player')},
    observed,
  )!;

  test('unrelated properties do not produce updates', () {
    expect(
      applyMprisPlayerProperties(initial, {'Volume': const DBusDouble(1)}, now),
      isNull,
    );
    expect(applyMprisPlayerProperties(initial, {}, now), isNull);
  });

  test('unchanged capabilities and status retain the playback clock', () {
    final next = applyMprisPlayerProperties(initial, {
      'CanPause': const DBusBoolean(true),
      'PlaybackStatus': const DBusString('Playing'),
    }, now);
    expect(next, same(initial));
    expect(next!.positionAt(now), const Duration(seconds: 3));
    expect(next.observedAt, observed);
  });

  test('changed capabilities retain metadata and advance the clock', () {
    final next = applyMprisPlayerProperties(initial, {
      'CanGoNext': const DBusBoolean(true),
    }, now)!;
    expect(next.canGoNext, isTrue);
    expect(next.artists, same(initial.artists));
    expect(next.length, same(initial.length));
    expect(next.position, const Duration(seconds: 3));
    expect(next.observedAt, now);
  });

  test('explicit position reports always establish a new anchor', () {
    final next = applyMprisPlayerProperties(initial, {
      'Position': const DBusInt64(1000000),
    }, now)!;
    expect(next, isNot(same(initial)));
    expect(next.observedAt, now);
    expect(next.position, const Duration(seconds: 1));
    expect(
      next.positionAt(now.add(const Duration(seconds: 1))),
      const Duration(seconds: 2),
    );
  });

  test('pause and resume freeze and restart the projected position', () {
    final paused = applyMprisPlayerProperties(initial, {
      'PlaybackStatus': const DBusString('Paused'),
    }, now)!;
    final later = now.add(const Duration(seconds: 10));
    expect(paused.positionAt(later), const Duration(seconds: 3));
    final resumed = applyMprisPlayerProperties(paused, {
      'PlaybackStatus': const DBusString('Playing'),
    }, later)!;
    expect(
      resumed.positionAt(later.add(const Duration(seconds: 1))),
      const Duration(seconds: 4),
    );
  });

  test(
    'duplicate metadata keeps the state and changed titles reuse artists',
    () {
      expect(
        applyMprisPlayerProperties(initial, {'Metadata': _metadata()}, now),
        same(initial),
      );
      final next = applyMprisPlayerProperties(initial, {
        'Metadata': _metadata(title: 'Next'),
      }, now)!;
      expect(next.title, 'Next');
      expect(next.artists, same(initial.artists));
      expect(() => next.artists.add('extra'), throwsUnsupportedError);
    },
  );

  test('shorter tracks and invalid positions retain clamping behavior', () {
    final short = applyMprisPlayerProperties(initial, {
      'Metadata': _metadata(length: 2000000),
    }, now)!;
    expect(short.position, const Duration(seconds: 2));
    expect(
      applyMprisPlayerProperties(initial, {
        'Position': const DBusInt64(-1),
      }, now)!.position,
      Duration.zero,
    );
    expect(
      applyMprisPlayerProperties(initial, {
        'Position': const DBusString('bad'),
      }, now)!.position,
      Duration.zero,
    );
  });

  test(
    'full reads preserve service identity fallback and ignore stopped players',
    () {
      final fallback = parseMprisPlaybackState(
        'org.mpris.MediaPlayer2.player.instance',
        {'PlaybackStatus': const DBusString('Paused')},
        {},
        now,
      )!;
      expect(fallback.identity, 'player');
      expect(fallback.title, 'player');
      expect(fallback.position, Duration.zero);
      expect(fallback.artists, isEmpty);
      expect(
        parseMprisPlaybackState('org.mpris.MediaPlayer2.player', {}, {}, now),
        isNull,
      );
    },
  );

  test('malformed metadata clears fields and unsafe artwork URLs', () {
    final next = applyMprisPlayerProperties(initial, {
      'Metadata': const DBusString('not a dictionary'),
    }, now)!;
    expect(next.title, 'Player');
    expect(next.artists, isEmpty);
    expect(next.length, Duration.zero);
    expect(next.album, '');
    expect(next.artUrl, '');
    final unsafe = applyMprisPlayerProperties(initial, {
      'Metadata': _metadata(artUrl: 'javascript:alert(1)'),
    }, now)!;
    expect(unsafe.artUrl, '');
  });

  test('Unicode normalization and truncation match the previous parser', () {
    final random = Random(985);
    const characters = [
      'a',
      'B',
      ' ',
      '\t',
      '\r',
      '\n',
      '\u0000',
      '\u007f',
      '\u0085',
      '\u00a0',
      '\u1680',
      '\u2003',
      '\u2028',
      '\u2029',
      '\u202f',
      '\u205f',
      '\u3000',
      '\ufeff',
      '😀',
      '中',
      'é',
      '\ud800',
      '\udfff',
    ];
    for (var i = 0; i < 1000; i++) {
      final text = List.generate(
        random.nextInt(600),
        (_) => characters[random.nextInt(characters.length)],
      ).join();
      final properties = {
        'Metadata': _metadata(title: text, artist: text, album: text),
      };
      final actual = applyMprisPlayerProperties(initial, properties, now)!;
      final expected = legacyApplyMprisPlayerProperties(
        initial,
        properties,
        now,
      )!;
      expect(
        _contents(actual, now),
        _contents(expected, now),
        reason: 'case $i',
      );
    }
  });

  test('mixed property sequences preserve playback behavior', () {
    final random = Random(185);
    var actual = initial;
    var expected = initial;
    for (var i = 0; i < 1000; i++) {
      final time = now.add(Duration(milliseconds: i * 175));
      final properties = switch (random.nextInt(6)) {
        0 => {'CanGoNext': DBusBoolean(random.nextBool())},
        1 => {'CanPause': DBusBoolean(random.nextBool())},
        2 => {'Position': DBusInt64(random.nextInt(12000000))},
        3 => {
          'PlaybackStatus': DBusString(
            random.nextBool() ? 'Playing' : 'Paused',
          ),
        },
        4 => {'Metadata': _metadata(title: 'Track ${random.nextInt(5)}')},
        _ => <String, DBusValue>{'Rate': const DBusDouble(1)},
      };
      actual = applyMprisPlayerProperties(actual, properties, time) ?? actual;
      expected =
          legacyApplyMprisPlayerProperties(expected, properties, time) ??
          expected;
      expect(
        _contents(actual, time),
        _contents(expected, time),
        reason: 'event $i',
      );
    }
  });
}

DBusDict _metadata({
  String title = 'Track',
  String artist = 'Artist',
  String album = 'Album',
  int length = 10000000,
  String artUrl = 'file:///art.png',
}) => DBusDict.stringVariant({
  'xesam:title': DBusString(title),
  'xesam:artist': DBusArray.string([artist]),
  'xesam:album': DBusString(album),
  'mpris:length': DBusInt64(length),
  'mpris:artUrl': DBusString(artUrl),
});

List<Object?> _contents(MprisPlaybackState state, DateTime at) => [
  state.serviceName,
  state.identity,
  state.title,
  state.artists,
  state.album,
  state.artUrl,
  state.length,
  state.positionAt(at),
  state.status,
  state.canGoNext,
  state.canGoPrevious,
  state.canPlay,
  state.canPause,
  state.positionAt(at.add(const Duration(seconds: 1))),
];
