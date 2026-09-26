import 'dart:convert';
import 'dart:math';

import 'package:denial_dart_shell/src/core/utf8_size.dart';
import 'package:test/test.dart';

void main() {
  test('empty and negative limits match the encoder', () {
    expect(fitsUtf8ByteLimit('', -1), isFalse);
    expect(fitsUtf8ByteLimit('', 0), isTrue);
    expect(fitsUtf8ByteLimit('a', 0), isFalse);
    expect(fitsUtf8ByteLimit('a', 1), isTrue);
  });

  test('exact boundaries include multibyte and unpaired surrogates', () {
    for (final text in [
      'ASCII',
      'é',
      '界',
      '😀',
      'aé界😀',
      String.fromCharCodes([0xd800]),
      String.fromCharCodes([0xdc00]),
      String.fromCharCodes([0xd800, 0xd800, 0xdc00, 0xdc00]),
      'x' * 262144,
      '界' * 87381,
      '😀' * 65536,
    ]) {
      final size = utf8.encode(text).length;
      expect(fitsUtf8ByteLimit(text, size - 1), isFalse);
      expect(fitsUtf8ByteLimit(text, size), isTrue);
      expect(fitsUtf8ByteLimit(text, size + 1), isTrue);
      expect(fitsUtf8ByteLimit(text, text.length * 3), isTrue);
    }
  });

  test('every individual UTF-16 code unit matches the encoder', () {
    for (var unit = 0; unit <= 0xffff; unit++) {
      final text = String.fromCharCode(unit);
      final size = utf8.encode(text).length;
      for (var limit = 0; limit <= 3; limit++) {
        if (fitsUtf8ByteLimit(text, limit) != (size <= limit)) {
          fail('U+${unit.toRadixString(16)} at $limit bytes');
        }
      }
    }
  });

  test('mixed valid and malformed strings match the encoder', () {
    final random = Random(2914);
    for (var sample = 0; sample < 10000; sample++) {
      final text = String.fromCharCodes([
        for (var i = random.nextInt(128); i > 0; i--)
          switch (random.nextInt(5)) {
            0 => random.nextInt(0x80),
            1 => random.nextInt(0x800),
            2 => 0xd800 + random.nextInt(0x800),
            _ => random.nextInt(0x110000),
          },
      ]);
      final size = utf8.encode(text).length;
      for (final limit in [
        -1,
        0,
        text.length,
        size - 1,
        size,
        size + 1,
        text.length * 3,
        random.nextInt(512),
      ]) {
        if (fitsUtf8ByteLimit(text, limit) != (size <= limit)) {
          fail('Sample $sample: $size bytes, limit $limit');
        }
      }
    }
  });
}
