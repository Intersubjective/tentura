import 'dart:typed_data';

Future<Uint8List> readBodyAsBytes(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final part in stream) {
    builder.add(part);
  }
  return builder.takeBytes();
}
