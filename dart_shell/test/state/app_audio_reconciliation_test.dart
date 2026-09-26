import 'dart:math';

import 'package:denial_dart_shell/src/models/audio.dart';
import 'package:denial_dart_shell/src/state/app_audio_reconciliation.dart';
import 'package:test/test.dart';

void main() {
  test(
    'native acknowledgement clears intent within one percent, unless muted',
    () {
      final desired = {1: 50, 2: 50, 3: 50, 4: 50};
      final streams = [
        _stream(1, level: 0.49),
        _stream(2, level: 0.51),
        _stream(3, level: 0.48),
        _stream(4, level: 0.5, muted: true),
      ];
      final result = reconcileAppAudioStreams(
        streams,
        desiredVolumes: desired,
        pendingVolumes: {},
      );
      expect(desired, {3: 50, 4: 50});
      expect(identical(result[0], streams[0]), isTrue);
      expect(identical(result[1], streams[1]), isTrue);
      expect(result.map((s) => (s.level, s.muted)), [
        (0.49, false),
        (0.51, false),
        (0.5, false),
        (0.5, false),
      ]);
      expect(streams[3].muted, isTrue);
    },
  );

  test(
    'disappearing streams discard both unsent commands and desired state',
    () {
      final desired = {1: 80, 2: 40};
      final pending = {1: 80, 2: 40, 3: 60};
      reconcileAppAudioStreams(
        [_stream(1)],
        desiredVolumes: desired,
        pendingVolumes: pending,
      );
      expect(desired, {1: 80});
      expect(pending, {1: 80});
      expect(
        reconcileAppAudioStreams(
          [],
          desiredVolumes: desired,
          pendingVolumes: pending,
        ),
        isEmpty,
      );
      expect(desired, isEmpty);
      expect(pending, isEmpty);
    },
  );

  test('sorting is case insensitive and preserves Unicode name semantics', () {
    final streams = [
      _stream(1, name: '日本語'),
      _stream(2, name: 'Steam'),
      _stream(3, name: 'browser'),
      _stream(4, name: 'Äpp'),
      _stream(5, name: 'Audio'),
    ];
    final result = reconcileAppAudioStreams(
      streams,
      desiredVolumes: {},
      pendingVolumes: {},
    );
    expect(result.map((s) => s.name), [
      'Audio',
      'browser',
      'Steam',
      'Äpp',
      '日本語',
    ]);
    expect(streams.first.id, 1);
    expect(result.every((stream) => streams.contains(stream)), isTrue);
    expect(() => result.clear(), throwsUnsupportedError);
  });

  test('repeated slider values retain the snapshot and stream objects', () {
    final streams = List<AppAudioStream>.unmodifiable([_stream(1), _stream(2)]);
    expect(
      identical(updateAppAudioStreamVolume(streams, 1, 0.25), streams),
      isTrue,
    );
    expect(
      identical(updateAppAudioStreamVolume(streams, 99, 0.75), streams),
      isTrue,
    );
    final updated = updateAppAudioStreamVolume(streams, 1, 0.75);
    expect(updated.first.level, 0.75);
    expect(streams.first.level, 0.25);
    expect(identical(updated.last, streams.last), isTrue);
    expect(
      identical(updateAppAudioStreamVolume(updated, 1, 0.75), updated),
      isTrue,
    );
    expect(() => updated[0] = streams.first, throwsUnsupportedError);
  });

  test('same-volume edits still unmute a stream', () {
    final streams = [_stream(1, muted: true)];
    final updated = updateAppAudioStreamVolume(streams, 1, 0.25);
    expect(updated.single.muted, isFalse);
    expect(streams.single.muted, isTrue);
  });

  test('random snapshots and intents match the previous reconciliation', () {
    final random = Random(0x415544);
    for (var sample = 0; sample < 1000; sample++) {
      final streams = List.generate(
        random.nextInt(70),
        (id) => _stream(
          id,
          name: '${id.isEven ? 'App' : 'PLAYER'} $id',
          level: random.nextInt(101) / 100,
          muted: random.nextBool(),
        ),
      )..shuffle(random);
      final desired = {
        for (var id = 0; id < 80; id++)
          if (random.nextBool()) id: random.nextInt(101),
      };
      final pending = Map<int, int>.of(desired);
      final oldDesired = Map<int, int>.of(desired);
      final oldPending = Map<int, int>.of(pending);
      final before = _previous(streams, oldDesired, oldPending);
      final after = reconcileAppAudioStreams(
        streams,
        desiredVolumes: desired,
        pendingVolumes: pending,
      );
      expect(after.map(_fields), before.map(_fields), reason: 'sample $sample');
      expect(desired, oldDesired);
      expect(pending, oldPending);
    }
  });
}

AppAudioStream _stream(
  int id, {
  String? name,
  double level = 0.25,
  bool muted = false,
}) =>
    AppAudioStream(id: id, name: name ?? 'App $id', level: level, muted: muted);
(int, String, double, bool) _fields(AppAudioStream stream) =>
    (stream.id, stream.name, stream.level, stream.muted);

List<AppAudioStream> _previous(
  List<AppAudioStream> streams,
  Map<int, int> desired,
  Map<int, int> pending,
) {
  final ids = streams.map((stream) => stream.id).toSet();
  desired.removeWhere((id, _) => !ids.contains(id));
  pending.removeWhere((id, _) => !ids.contains(id));
  final result =
      streams
          .map((stream) {
            final percent = desired[stream.id];
            if (percent == null) return stream;
            final observed = (stream.level * 100).round().clamp(0, 100);
            if ((observed - percent).abs() <= 1 && !stream.muted) {
              desired.remove(stream.id);
              return stream;
            }
            return stream.copyWith(level: percent / 100.0, muted: false);
          })
          .toList(growable: false)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return List<AppAudioStream>.unmodifiable(result);
}
