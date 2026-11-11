import 'dart:typed_data';

/// A composer attachment is either picked bytes or a saved server attachment.
sealed class RoomPendingUpload {
  const factory RoomPendingUpload({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? attachmentId,
  }) = PickedRoomUpload;

  const factory RoomPendingUpload.saved({
    required String attachmentId,
    required String fileName,
    required String mimeType,
    String? imageUrl,
  }) = SavedRoomUpload;

  const RoomPendingUpload._();

  Uint8List? get bytes;
  String get fileName;
  String get mimeType;
  String? get attachmentId;
  String? get imageUrl;

  RoomPendingUpload identified(String id) => switch (this) {
    PickedRoomUpload(:final bytes, :final fileName, :final mimeType) =>
      RoomPendingUpload(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        attachmentId: id,
      ),
    SavedRoomUpload() => this,
  };
}

final class PickedRoomUpload extends RoomPendingUpload {
  const PickedRoomUpload({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    this.attachmentId,
  }) : super._();
  @override
  final Uint8List bytes;
  @override
  final String fileName;
  @override
  final String mimeType;
  @override
  final String? attachmentId;
  @override
  String? get imageUrl => null;
}

final class SavedRoomUpload extends RoomPendingUpload {
  const SavedRoomUpload({
    required this.attachmentId,
    required this.fileName,
    required this.mimeType,
    this.imageUrl,
  }) : super._();
  @override
  final String attachmentId;
  @override
  final String fileName;
  @override
  final String mimeType;
  @override
  final String? imageUrl;
  @override
  Uint8List? get bytes => null;
}
