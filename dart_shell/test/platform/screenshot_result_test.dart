import 'dart:convert';
import 'dart:typed_data';

import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const commandChannel = 'denial/system_command';
  const resultChannel = 'denial/screenshot_result';

  ByteData result(int id, List<int> bytes) {
    final buffer = Uint8List(8 + bytes.length);
    final packet = ByteData.sublistView(buffer)
      ..setUint64(0, id, Endian.little);
    buffer.setAll(8, bytes);
    return packet;
  }

  test(
    'screenshot feedback accepts only the matching native save result',
    () async {
      final bridge = DenialBridge();
      addTearDown(bridge.dispose);
      final requests = <ByteData>[];
      messenger.setMockMessageHandler(commandChannel, (packet) async {
        requests.add(packet!);
        return null;
      });
      addTearDown(() => messenger.setMockMessageHandler(commandChannel, null));
      final future = bridge.takeScreenshotWithResult();
      expect(await bridge.takeScreenshotWithResult(), isNull);
      expect(requests, hasLength(1));
      expect(requests.single.getUint8(0), 6);
      expect(requests.single.getUint32(9, Endian.little), 0);
      final id = requests.single.getUint64(1, Endian.little);
      expect(id, isPositive);
      await messenger.handlePlatformMessage(
        resultChannel,
        result(id + 1, utf8.encode('/tmp/stale.png')),
        (_) {},
      );
      await messenger.handlePlatformMessage(
        resultChannel,
        result(id, utf8.encode('/tmp/synthetic.png')),
        (_) {},
      );
      expect(await future, '/tmp/synthetic.png');

      final failed = bridge.takeScreenshotWithResult();
      await messenger.handlePlatformMessage(
        resultChannel,
        result(requests.last.getUint64(1, Endian.little), []),
        (_) {},
      );
      expect(await failed, isNull);
    },
  );

  test('relative or malformed results are not opened as files', () async {
    final bridge = DenialBridge();
    addTearDown(bridge.dispose);
    var id = 0;
    messenger.setMockMessageHandler(commandChannel, (packet) async {
      id = packet!.getUint64(1, Endian.little);
      return null;
    });
    addTearDown(() => messenger.setMockMessageHandler(commandChannel, null));
    for (final bytes in [
      utf8.encode('relative.png'),
      [0xFF],
      utf8.encode('/tmp/a.jpg'),
    ]) {
      final failed = bridge.takeScreenshotWithResult();
      await messenger.handlePlatformMessage(
        resultChannel,
        result(id, bytes),
        (_) {},
      );
      expect(await failed, isNull);
    }
  });
}
