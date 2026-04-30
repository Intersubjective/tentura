import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/utils/read_uint8_stream_with_limit.dart';

void main() {
  test('readUint8StreamWithLimit rejects streams over limit', () async {
    final stream = Stream<Uint8List>.fromIterable([
      Uint8List(900),
      Uint8List(900),
    ]);
    expect(
      () => readUint8StreamWithLimit(stream, 1500),
      throwsA(isA<BeaconCreateException>()),
    );
  });

  test('readUint8StreamWithLimit returns concatenated bytes', () async {
    final stream = Stream<Uint8List>.fromIterable([
      Uint8List.fromList([1, 2]),
      Uint8List.fromList([3]),
    ]);
    final out = await readUint8StreamWithLimit(stream, 10);
    expect(out, Uint8List.fromList([1, 2, 3]));
  });
}
