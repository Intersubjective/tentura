import 'dart:typed_data';

import 'package:tentura_server/domain/exception.dart';

/// Reads [stream] fully into a single buffer, failing if total length exceeds [maxBytes].
Future<Uint8List> readUint8StreamWithLimit(
  Stream<Uint8List> stream,
  int maxBytes,
) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
    if (builder.length > maxBytes) {
      throw const BeaconCreateException(
        description: 'Attachment exceeds maximum size',
      );
    }
  }
  return builder.takeBytes();
}
