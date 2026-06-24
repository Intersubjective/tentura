import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/utils/read_uint8_stream_with_limit.dart';

Stream<Uint8List> _chunks(List<int> sizes) async* {
  for (final n in sizes) {
    yield Uint8List(n);
  }
}

void main() {
  test('readUint8StreamCapped returns full payload when within the cap',
      () async {
    final bytes = await readUint8StreamCapped(_chunks([100, 100, 56]), 256);
    expect(bytes.length, 256);
  });

  test('readUint8StreamCapped throws PayloadTooLargeException over the cap',
      () async {
    await expectLater(
      readUint8StreamCapped(_chunks([100, 100, 100]), 256),
      throwsA(isA<PayloadTooLargeException>()),
    );
  });
}
