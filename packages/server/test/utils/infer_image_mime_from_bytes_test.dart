import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:tentura_root/utils/infer_image_mime_from_bytes.dart';

void main() {
  test('detects JPEG signature', () {
    expect(
      inferImageMimeFromLeadingBytes(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])),
      'image/jpeg',
    );
  });

  test('detects PNG signature', () {
    final png = Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0,
      0,
      0,
      0,
    ]);
    expect(inferImageMimeFromLeadingBytes(png), 'image/png');
  });

  test('returns null for non-image data', () {
    expect(inferImageMimeFromLeadingBytes(Uint8List(32)), isNull);
  });
}
