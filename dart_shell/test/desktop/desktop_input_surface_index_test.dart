import 'package:denial_dart_shell/src/desktop/desktop_input_surface_index.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'layer partitions retain source order and include only positioned roots',
    () {
      final background = _Layer(DenialWindowContentKind.layerShellBackground);
      final top = _Layer(DenialWindowContentKind.layerShellTop);
      final bottom = _Layer(DenialWindowContentKind.layerShellBottom);
      final overlay = _Layer(DenialWindowContentKind.layerShellOverlay);
      final unpositioned = _Layer(
        DenialWindowContentKind.layerShellTop,
        positioned: false,
      );
      final other = _Layer(DenialWindowContentKind.localFlutter);
      final source = List<DenialWindow>.unmodifiable([
        top,
        background,
        unpositioned,
        overlay,
        bottom,
        other,
      ]);
      final index = DesktopInputSurfaceIndex(source);
      expect(index.source, same(source));
      expect(index.positioned, [top, background, overlay, bottom, other]);
      expect(index.background, [background, bottom]);
      expect(index.foreground, [top, overlay]);
      expect(
        [
          top,
          background,
          unpositioned,
          overlay,
          bottom,
          other,
        ].every((surface) => surface.geometryReads == 1),
        isTrue,
      );
      expect(() => index.positioned.clear(), throwsUnsupportedError);
      expect(() => index.background.clear(), throwsUnsupportedError);
      expect(() => index.foreground.clear(), throwsUnsupportedError);
    },
  );

  test('a replacement layer snapshot gets independent partitions', () {
    final old = DesktopInputSurfaceIndex([
      _Layer(DenialWindowContentKind.layerShellTop),
    ]);
    final next = DesktopInputSurfaceIndex(const []);
    expect(next.positioned, isEmpty);
    expect(next.foreground, isEmpty);
    expect(old.foreground, hasLength(1));
  });
}

class _Layer implements DenialWindow {
  _Layer(this.contentKind, {this.positioned = true});
  @override
  final DenialWindowContentKind contentKind;
  final bool positioned;
  int geometryReads = 0;
  @override
  Rect? get geometry {
    geometryReads++;
    return positioned ? const Rect.fromLTWH(0, 0, 100, 100) : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
