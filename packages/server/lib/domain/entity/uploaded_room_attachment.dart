/// Metadata of an upload completed before message persistence begins: an
/// image (by `imageId`) or a file (by `storagePath`).
typedef UploadedRoomAttachment = ({
  String? imageId,
  String? storagePath,
  String mime,
  int sizeBytes,
  String displayName,
});
