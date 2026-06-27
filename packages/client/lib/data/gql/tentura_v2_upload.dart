import 'dart:typed_data';

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

  final String filename;
  final String mimeType;
  final Uint8List bytes;
}
