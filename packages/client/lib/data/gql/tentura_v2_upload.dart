import 'dart:typed_data';
import 'package:tentura/domain/entity/room_pending_upload.dart';

/// Outbound-only model for the GraphQL `v2_Upload` input object.
///
/// Ferry maps `v2_Upload` to this type (see build.yaml). The actual multipart
/// encoding happens in `V2UploadMultipartLink`: the link sends
/// `{ filename, type }` as the GraphQL variable and the raw [bytes] as
/// multipart part `0`.
class TenturaV2Upload {
  const TenturaV2Upload({
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });

  factory TenturaV2Upload.fromPending(RoomPendingUpload upload) =>
      switch (upload) {
        PickedRoomUpload(:final bytes, :final fileName, :final mimeType) =>
          TenturaV2Upload(filename: fileName, mimeType: mimeType, bytes: bytes),
        SavedRoomUpload() => throw ArgumentError(
          'A saved attachment cannot be uploaded again',
        ),
      };

  final String filename;
  final String mimeType;
  final Uint8List bytes;
}
