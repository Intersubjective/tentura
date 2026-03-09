import 'dart:typed_data';

Future<Uint8List> readBodyAsBytes(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await stream.forEach(builder.add);
  return builder.takeBytes();
}
