import 'dart:collection';

import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_motion_harness.dart';

void main() {
  test('desktop projections are reused through 1200 gesture updates', () {
    final windows = [
      for (var id = 0; id < 1000; id++)
        _ClassifiedWindow(
          id,
          userApp: id % 10 != 0,
          popup: id % 10 == 0,
          positioned: true,
        ),
    ];
    var state = ShellState.initial().copyWith(windows: windows);
    final byId = state.openAppWindowsByObjectId;
    final popups = state.positionedPopupSurfaces;
    expect(byId, hasLength(900));
    expect(popups, hasLength(100));
    for (var tick = 0; tick < 1200; tick++) {
      state = state.copyWith(gestureDrag: Offset(tick.toDouble(), 0));
      expect(state.openAppWindowsByObjectId, same(byId));
      expect(state.positionedPopupSurfaces, same(popups));
    }
    expect(windows.fold<int>(0, (sum, window) => sum + window.appReads), 1000);
    expect(
      windows.fold<int>(0, (sum, window) => sum + window.popupReads),
      1000,
    );
    expect(
      windows.fold<int>(0, (sum, window) => sum + window.geometryReads),
      100,
    );
    final next = state.copyWith(windows: windows.skip(2).toList());
    expect(next.openAppWindowsByObjectId.containsKey(1), isFalse);
    expect(next.positionedPopupSurfaces, hasLength(99));
    expect(byId.containsKey(1), isTrue);
    expect(popups, hasLength(100));
  });

  test(
    'desktop projections preserve app-only duplicate and popup filtering',
    () {
      final first = _ClassifiedWindow(1, userApp: true);
      final last = _ClassifiedWindow(1, userApp: true);
      final nonApp = _ClassifiedWindow(1);
      final popup = _ClassifiedWindow(2, popup: true, positioned: true);
      final unpositioned = _ClassifiedWindow(3, popup: true);
      final state = ShellState.initial().copyWith(
        windows: [first, last, nonApp, popup, unpositioned],
      );
      expect(state.windowByObjectId(1), same(nonApp));
      expect(state.openAppWindowsByObjectId, {1: last});
      expect(state.positionedPopupSurfaces, [popup]);
      expect(
        () => state.openAppWindowsByObjectId.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => state.positionedPopupSurfaces.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('native event lookup reads IDs only when the snapshot changes', () {
    final windows = [
      for (var id = 0; id < 1000; id++) _CountingNativeWindow(id, id + 10000),
    ];
    var state = ShellState.initial().copyWith(windows: windows);
    for (final window in windows) {
      expect(window.nativeIdReads, 1);
      window.nativeIdReads = 0;
    }
    for (var tick = 0; tick < 1200; tick++) {
      state = state.copyWith(gestureDrag: Offset(tick.toDouble(), 0));
      expect(state.windowByWindowId(10999), same(windows.last));
      expect(state.windowByWindowId(20000), isNull);
    }
    expect(windows.every((window) => window.nativeIdReads == 0), isTrue);
  });

  test(
    'snapshots own their lists and preserve native-ID first-match behavior',
    () {
      final first = _CountingNativeWindow(1, 10);
      final second = _CountingNativeWindow(2, 10);
      final source = <DenialWindow>[first, second];
      final layers = <DenialWindow>[motionWindow(20)];
      final state = ShellState.initial().copyWith(
        windows: source,
        layerSurfaces: layers,
      );
      source.clear();
      layers.clear();
      expect(state.windows, [first, second]);
      expect(state.layerSurfaces, hasLength(1));
      expect(state.windowByWindowId(10), same(first));
      expect(state.windowByObjectId(2), same(second));
      expect(() => state.windows.clear(), throwsUnsupportedError);
      expect(() => state.layerSurfaces.clear(), throwsUnsupportedError);
      final gesture = state.copyWith(gestureDrag: const Offset(1, 0));
      expect(gesture.windows, same(state.windows));
      expect(gesture.openAppWindows, same(state.openAppWindows));
      final changed = gesture.copyWith(windows: [second]);
      expect(changed.windowByWindowId(10), same(second));
      expect(changed.windowByObjectId(1), isNull);
      expect(state.windowByWindowId(10), same(first));
    },
  );

  test('1200 drag updates do not scan a 1000-window snapshot', () {
    final windows = _CountingWindows([
      for (var id = 0; id < 1000; id++) motionWindow(id),
    ]);
    var state = ShellState.initial().copyWith(
      windows: windows,
      foregroundObjectId: 500,
    );
    final apps = state.openAppWindows;
    windows.reads = 0;
    for (var tick = 1; tick <= 1200; tick++) {
      state = state.copyWith(gestureDrag: Offset(tick.toDouble(), 0));
      expect(state.appSwitchTargetWindow?.objectId, 499);
      expect(state.adjacentOpenAppWindow(1)?.objectId, 501);
      expect(state.openAppWindows, same(apps));
    }
    expect(windows.reads, 0);
  });

  test(
    'adjacency follows app order after filtering, removal and reordering',
    () {
      final apps = [motionWindow(1), motionWindow(2), motionWindow(3)];
      var state = ShellState.initial().copyWith(
        windows: [
          motionWindow(90, appId: 'denia-home'),
          apps[0],
          motionWindow(91, appId: 'denia-systemui-helper'),
          apps[1],
          apps[2],
        ],
        foregroundObjectId: 2,
      );
      expect(state.adjacentOpenAppWindow(-1), same(apps[0]));
      expect(state.adjacentOpenAppWindow(1), same(apps[2]));
      expect(state.adjacentOpenAppWindow(0), isNull);
      state = state.copyWith(windows: [apps[2], apps[1], apps[0]]);
      expect(state.adjacentOpenAppWindow(-1), same(apps[2]));
      expect(state.adjacentOpenAppWindow(1), same(apps[0]));
      state = state.copyWith(windows: [apps[2], apps[0]]);
      expect(state.adjacentOpenAppWindow(-1), same(apps[2]));
      expect(state.adjacentOpenAppWindow(1), isNull);
      state = state.copyWith(foregroundObjectId: 3);
      expect(state.adjacentOpenAppWindow(-1), isNull);
      expect(state.adjacentOpenAppWindow(1), same(apps[0]));
      state = state.copyWith(windows: [apps[0]]);
      expect(state.adjacentOpenAppWindow(-1), isNull);
      expect(state.adjacentOpenAppWindow(1), isNull);
    },
  );
}

class _ClassifiedWindow implements DenialWindow {
  _ClassifiedWindow(
    this.objectId, {
    this.userApp = false,
    this.popup = false,
    this.positioned = false,
  });
  @override
  final int objectId;
  final bool userApp;
  final bool popup;
  final bool positioned;
  int appReads = 0;
  int popupReads = 0;
  int geometryReads = 0;
  @override
  int get windowId => objectId;
  @override
  bool get isUserApp {
    appReads++;
    return userApp;
  }

  @override
  bool get isPopupSurface {
    popupReads++;
    return popup;
  }

  @override
  Rect? get geometry {
    geometryReads++;
    return positioned ? const Rect.fromLTWH(0, 0, 100, 100) : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingNativeWindow implements DenialWindow {
  _CountingNativeWindow(this.objectId, this._nativeId);

  @override
  final int objectId;
  final int _nativeId;
  int nativeIdReads = 0;

  @override
  bool get isUserApp => true;

  @override
  int get windowId {
    nativeIdReads++;
    return _nativeId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingWindows extends ListBase<DenialWindow> {
  _CountingWindows(this._values);
  final List<DenialWindow> _values;
  int reads = 0;
  @override
  int get length => _values.length;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  DenialWindow operator [](int index) {
    reads++;
    return _values[index];
  }

  @override
  void operator []=(int index, DenialWindow value) =>
      throw UnsupportedError('read only');
}
