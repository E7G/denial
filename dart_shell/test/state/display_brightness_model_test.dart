import 'package:denial_dart_shell/src/state/display_brightness_model.dart';
import 'package:test/test.dart';

void main() {
  test(
    'initial state owns immutable collections and deduplicates monitors',
    () {
      final ids = [1, 2, 1];
      final model = DisplayBrightnessModel(ids);
      ids.clear();
      expect(model.state.levels, {1: 0.72, 2: 0.72});
      expect(model.state.loading, {1, 2});
      expect(() => model.state.levels[1] = 0.5, throwsUnsupportedError);
      expect(() => model.state.loading.clear(), throwsUnsupportedError);
    },
  );

  test(
    'native event and matching read completion publish just one snapshot',
    () {
      final model = DisplayBrightnessModel([1]);
      final read = model.beginRead(1)!;
      final event = model.nativeLevel(1, 0.4, completesRead: true);
      expect(event.levels[1], 0.4);
      expect(event.loading, isEmpty);
      expect(identical(model.completeRead(1, read, 0.4), event), isTrue);
      expect(
        identical(model.nativeLevel(1, 0.4, completesRead: false), event),
        isTrue,
      );
    },
  );

  test('read event and future cannot undo a newer local edit', () {
    final model = DisplayBrightnessModel([1]);
    final read = model.beginRead(1)!;
    final edited = model.setLevel(1, 0.9);
    final event = model.nativeLevel(1, 0.3, completesRead: true);
    expect(event.levels[1], 0.9);
    expect(identical(event.levels, edited.levels), isTrue);
    expect(event.loading, isEmpty);
    expect(identical(model.completeRead(1, read, 0.3), event), isTrue);
  });

  test('editing the displayed default also invalidates a pending read', () {
    final model = DisplayBrightnessModel([1]);
    final initial = model.state;
    final read = model.beginRead(1)!;
    expect(identical(model.setLevel(1, 0.72), initial), isTrue);
    expect(model.completeRead(1, read, 0.2).levels[1], 0.72);
    expect(model.state.loading, isEmpty);
  });

  test('late read completion cannot undo a newer hardware event', () {
    final model = DisplayBrightnessModel([1]);
    final read = model.beginRead(1)!;
    final event = model.nativeLevel(1, 0.8, completesRead: false);
    expect(identical(model.completeRead(1, read, 0.2), event), isTrue);
  });

  test(
    'a later read event remains authoritative after the initial read event',
    () {
      final model = DisplayBrightnessModel([1]);
      final read = model.beginRead(1)!;
      model.nativeLevel(1, 0.3, completesRead: true);
      final next = model.nativeLevel(1, 0.6, completesRead: true);
      expect(next.levels[1], 0.6);
      expect(identical(model.completeRead(1, read, 0.3), next), isTrue);
    },
  );

  test('a replaced read cannot finish loading or overwrite the newer read', () {
    final model = DisplayBrightnessModel([1]);
    final first = model.beginRead(1)!;
    final second = model.beginRead(1)!;
    final initial = model.state;
    expect(identical(model.completeRead(1, first, 0.2), initial), isTrue);
    expect(model.state.loading, {1});
    expect(model.completeRead(1, second, 0.6).levels[1], 0.6);
    expect(model.state.loading, isEmpty);
  });

  test('freshness is independent for each monitor', () {
    final model = DisplayBrightnessModel([1, 2]);
    final first = model.beginRead(1)!;
    final second = model.beginRead(2)!;
    model.setLevel(1, 0.9);
    model.completeRead(2, second, 0.4);
    model.completeRead(1, first, 0.2);
    expect(model.state.levels, {1: 0.9, 2: 0.4});
    expect(model.state.loading, isEmpty);
  });

  test('failed reads clear loading while retaining the levels map', () {
    final model = DisplayBrightnessModel([1, 2]);
    final initial = model.state;
    final read = model.beginRead(1)!;
    final failed = model.completeRead(1, read, null);
    expect(identical(failed.levels, initial.levels), isTrue);
    expect(failed.loading, {2});
    expect(initial.loading, {1, 2});
  });

  test(
    'changed values share loading and repeated values retain the snapshot',
    () {
      final model = DisplayBrightnessModel([1, 2]);
      final initial = model.state;
      final changed = model.setLevel(1, 0.8);
      expect(identical(changed.loading, initial.loading), isTrue);
      expect(initial.levels[1], 0.72);
      expect(changed.levels[1], 0.8);
      expect(identical(model.setLevel(1, 0.8), changed), isTrue);
      expect(() => changed.levels.remove(1), throwsUnsupportedError);
    },
  );

  test('unknown monitors do not change state or create read tokens', () {
    final model = DisplayBrightnessModel([1]);
    final initial = model.state;
    expect(model.beginRead(99), isNull);
    expect(identical(model.setLevel(99, 0.5), initial), isTrue);
    expect(
      identical(model.nativeLevel(99, 0.5, completesRead: true), initial),
      isTrue,
    );
    expect(identical(model.completeRead(99, 1, 0.5), initial), isTrue);
  });

  test('levels retain the hardware control clamp', () {
    final model = DisplayBrightnessModel([1]);
    expect(model.setLevel(1, -1).levels[1], 0.01);
    expect(model.nativeLevel(1, 2, completesRead: false).levels[1], 1.0);
    final read = model.beginRead(1)!;
    expect(model.completeRead(1, read, 0).levels[1], 0.01);
  });

  test(
    'copyWith owns supplied collections and preserves omitted collections',
    () {
      final model = DisplayBrightnessModel([1]);
      final levels = {1: 0.6};
      final copied = model.state.copyWith(levels: levels);
      levels[1] = 0.3;
      expect(copied.levels[1], 0.6);
      expect(identical(copied.loading, model.state.loading), isTrue);
      expect(() => copied.levels.clear(), throwsUnsupportedError);
    },
  );
}
