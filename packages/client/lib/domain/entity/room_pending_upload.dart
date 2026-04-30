import 'dart:typed_data';

/// Pending Room message attachment before multipart upload (composer).
final class RoomPendingUpload {
  const RoomPendingUpload({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;

  final String fileName;

  final String mimeType;
}
