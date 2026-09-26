import 'dart:async';

import 'package:denial_dart_shell/src/models/clipboard_history.dart';
import 'package:denial_dart_shell/src/state/clipboard_history_loader.dart';
import 'package:test/test.dart';

void main() {
  test('a burst of 100 events makes only one follow-up request', () async {
    final harness = _Harness();
    final done = harness.loader.refresh('query');
    for (var i = 0; i < 100; i++) {
      expect(identical(harness.loader.refresh('query'), done), isTrue);
    }
    expect(harness.queries, ['query']);
    harness.requests[0].complete(_snapshot(1));
    await _flush();
    expect(harness.queries, ['query', 'query']);
    expect(harness.snapshots, isEmpty);
    harness.requests[1].complete(_snapshot(101));
    await done;
    expect(harness.snapshots.single.revision, 101);
  });

  test('only the latest query is loaded after an in-flight request', () async {
    final harness = _Harness();
    final done = harness.loader.refresh('a');
    harness.loader.refresh('ab');
    harness.loader.refresh('abc');
    harness.requests[0].complete(_snapshot(1));
    await _flush();
    expect(harness.queries, ['a', 'abc']);
    harness.requests[1].complete(_snapshot(2));
    await done;
    expect(harness.snapshots.single.revision, 2);
  });

  test('invalidation discards queued work and an obsolete error', () async {
    final harness = _Harness();
    final done = harness.loader.refresh('a');
    harness.loader.refresh('b');
    harness.loader.invalidate();
    harness.requests[0].completeError(StateError('old query'));
    await done;
    expect(harness.queries, ['a']);
    expect(harness.errors, isEmpty);
    expect(harness.snapshots, isEmpty);
  });

  test('a pushed snapshot can supersede an outstanding read', () async {
    final harness = _Harness();
    final done = harness.loader.refresh('');
    harness.loader.invalidate();
    harness.requests[0].complete(_snapshot(1));
    await done;
    expect(harness.snapshots, isEmpty);
  });

  test('failed obsolete reads still advance to the latest query', () async {
    final harness = _Harness();
    final done = harness.loader.refresh('a');
    harness.loader.refresh('b');
    harness.requests[0].completeError(StateError('obsolete'));
    await _flush();
    expect(harness.queries, ['a', 'b']);
    expect(harness.errors, isEmpty);
    harness.requests[1].complete(_snapshot(2));
    await done;
    expect(harness.snapshots.single.revision, 2);
  });

  test('current errors are reported and a later request can recover', () async {
    final harness = _Harness();
    final done = harness.loader.refresh('a');
    final error = StateError('unavailable');
    harness.requests[0].completeError(error);
    await done;
    expect(harness.errors, [error]);
    final recovered = harness.loader.refresh('b');
    harness.requests[1].complete(_snapshot(2));
    await recovered;
    expect(harness.snapshots.single.revision, 2);
  });

  test('synchronous read failures also release the request slot', () async {
    var attempts = 0;
    final errors = <Object>[];
    final loader = ClipboardHistoryLoader(
      load: (_) {
        attempts++;
        throw StateError('sync');
      },
      onSnapshot: (_) => fail('unexpected snapshot'),
      onError: errors.add,
    );
    await loader.refresh('a');
    await loader.refresh('b');
    expect(attempts, 2);
    expect(errors, hasLength(2));
  });

  test('disposal suppresses callbacks and queued or later requests', () async {
    final harness = _Harness();
    final done = harness.loader.refresh('a');
    harness.loader.refresh('b');
    harness.loader.dispose();
    await harness.loader.refresh('c');
    harness.requests[0].completeError(StateError('disposed'));
    await done;
    expect(harness.queries, ['a']);
    expect(harness.errors, isEmpty);
    expect(harness.snapshots, isEmpty);
  });

  test('a callback can queue another read without losing it', () async {
    final requests = <Completer<ClipboardHistorySnapshot>>[];
    final revisions = <int>[];
    late ClipboardHistoryLoader loader;
    loader = ClipboardHistoryLoader(
      load: (_) {
        final request = Completer<ClipboardHistorySnapshot>();
        requests.add(request);
        return request.future;
      },
      onSnapshot: (snapshot) {
        revisions.add(snapshot.revision);
        if (snapshot.revision == 1) unawaited(loader.refresh('updated'));
      },
      onError: (_) => fail('unexpected error'),
    );
    final done = loader.refresh('initial');
    requests[0].complete(_snapshot(1));
    await _flush();
    requests[1].complete(_snapshot(2));
    await done;
    expect(revisions, [1, 2]);
  });
}

class _Harness {
  _Harness() {
    loader = ClipboardHistoryLoader(
      load: (query) {
        queries.add(query);
        final request = Completer<ClipboardHistorySnapshot>();
        requests.add(request);
        return request.future;
      },
      onSnapshot: snapshots.add,
      onError: errors.add,
    );
  }
  late final ClipboardHistoryLoader loader;
  final queries = <String>[];
  final requests = <Completer<ClipboardHistorySnapshot>>[];
  final snapshots = <ClipboardHistorySnapshot>[];
  final errors = <Object>[];
}

ClipboardHistorySnapshot _snapshot(int revision) => ClipboardHistorySnapshot(
  revision: revision,
  totalBytes: 0,
  activeId: null,
  paused: false,
  locked: false,
  entries: const [],
);

Future<void> _flush() => Future<void>.delayed(Duration.zero);
