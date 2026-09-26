import 'dart:math';
import 'dart:typed_data';

import 'package:denial_dart_shell/src/models/ui_development.dart';
import 'package:denial_dart_shell/src/platform/ui_development_protocol.dart';
import 'package:test/test.dart';

import '../support/legacy_ui_development_protocol.dart';
import '../support/ui_development_packet.dart';

void main() {
  final codec = DenialUiDevelopmentProtocol();
  final before = LegacyUiDevelopmentProtocol();

  test('all command combinations retain identical bytes and validation', () {
    for (final command in DenialUiDevelopmentCommand.values) {
      for (final requestId in [-1, 0, 1, 0xffffffff, 0x100000000]) {
        for (final workspace in [
          '',
          '/workspace/界',
          'a\u0000b',
          'x' * 4096,
          '界' * 1366,
          String.fromCharCode(0xd800),
        ]) {
          for (final auto in [false, true]) {
            expect(
              codec.encodeCommand(
                command: command,
                requestId: requestId,
                workspace: workspace,
                autoReload: auto,
              ),
              before.encodeCommand(
                command: command,
                requestId: requestId,
                workspace: workspace,
                autoReload: auto,
              ),
            );
          }
        }
      }
    }
  });

  test('maximum diagnostic report decodes every field and owns its list', () {
    final packet = uiDevelopmentPacket(diagnostics: 64);
    final state = codec.decodeState(packet)!;
    expect(_fields(state), _fields(before.decodeState(packet)));
    expect(state.diagnostics, hasLength(64));
    expect(state.workspace, '/home/developer/界');
    expect(state.progress, 0.8765);
    expect(() => state.diagnostics.clear(), throwsUnsupportedError);
    packet.buffer.asUint8List().fillRange(0, packet.lengthInBytes, 0);
    expect(state.diagnostics.last.message, contains('😀'));
  });

  test(
    'sliced packets decode relative to the view and preserve BOM behavior',
    () {
      final packet = uiDevelopmentPacket(
        diagnostics: 3,
        workspace: '\ufeff/workspace/界',
        status: '\ufeffReady',
      );
      final wrapped = Uint8List(packet.lengthInBytes + 17)
        ..fillRange(0, 17, 255);
      wrapped.setRange(
        7,
        7 + packet.lengthInBytes,
        packet.buffer.asUint8List(),
      );
      final view = ByteData.sublistView(wrapped, 7, 7 + packet.lengthInBytes);
      expect(
        _fields(codec.decodeState(view)),
        _fields(before.decodeState(packet)),
      );
    },
  );

  test('empty strings and absent progress retain their sentinel semantics', () {
    final packet = uiDevelopmentPacket(workspace: '', uri: '', status: '')
      ..setUint16(6, 0xffff, Endian.little);
    final state = codec.decodeState(packet)!;
    expect(state.progress, isNull);
    expect(state.vmServiceAvailable, isFalse);
    expect(state.workspace, isEmpty);
    expect(state.diagnostics, isEmpty);
  });

  test('every truncated prefix and extra trailing bytes are rejected', () {
    final packet = uiDevelopmentPacket(diagnostics: 2);
    final bytes = packet.buffer.asUint8List();
    for (var length = 0; length < bytes.length; length++) {
      expect(codec.decodeState(ByteData.sublistView(bytes, 0, length)), isNull);
    }
    final extra = Uint8List(bytes.length + 1)..setRange(0, bytes.length, bytes);
    expect(codec.decodeState(ByteData.sublistView(extra)), isNull);
    expect(codec.decodeState(null), isNull);
  });

  test('oversized workspace and impossible diagnostic count are rejected', () {
    expect(
      codec.decodeState(uiDevelopmentPacket(workspace: 'a' * 4097)),
      isNull,
    );
    final packet = uiDevelopmentPacket()..setUint16(36, 64, Endian.little);
    expect(codec.decodeState(packet), isNull);
    expect(codec.decodeState(ByteData(65537)), isNull);
  });

  test('random malformed packets agree with the previous decoder', () {
    final random = Random(5361);
    final original = uiDevelopmentPacket(diagnostics: 8).buffer.asUint8List();
    for (var sample = 0; sample < 10000; sample++) {
      final bytes = Uint8List.fromList(original);
      for (var change = 0; change < 1 + sample % 4; change++) {
        bytes[random.nextInt(bytes.length)] = random.nextInt(256);
      }
      final packet = ByteData.sublistView(bytes);
      expect(
        _fields(codec.decodeState(packet)),
        _fields(before.decodeState(packet)),
        reason: 'sample $sample',
      );
    }
  });
}

List<Object?>? _fields(DenialUiDevelopmentState? state) => state == null
    ? null
    : [
        state.activeMode,
        state.desiredMode,
        state.operation,
        state.developerComponentsAvailable,
        state.workspaceValid,
        state.autoReload,
        state.autoReloadSupported,
        state.canHotReload,
        state.canHotRestart,
        state.canBuildOptimized,
        state.canRevert,
        state.vmServiceAvailable,
        state.generation,
        state.revision,
        state.acknowledgedRequestId,
        state.workspace,
        state.vmServiceUri,
        state.status,
        state.error,
        state.progress,
        for (final diagnostic in state.diagnostics)
          [
            diagnostic.severity,
            diagnostic.message,
            diagnostic.path,
            diagnostic.line,
            diagnostic.column,
          ],
      ];
