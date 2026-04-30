import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'beacon_room_consts.dart';

part 'room_message_attachment.freezed.dart';

@freezed
abstract class RoomMessageAttachment with _$RoomMessageAttachment {
  const factory RoomMessageAttachment({
    required String id,
    required int kind,
    required int position,
    required String mime,
    required int sizeBytes,
    @Default('') String fileName,
    @Default('') String imageId,
    @Default('') String imageAuthorId,
    @Default('') String blurHash,
    @Default(0) int width,
    @Default(0) int height,
  }) = _RoomMessageAttachment;

  const RoomMessageAttachment._();

  bool get isImage => kind == BeaconRoomMessageAttachmentKind.image;

  bool get isFile => kind == BeaconRoomMessageAttachmentKind.file;
}

/// Parses [RoomMessageRow.attachmentsJson] from the server (ordered list).
List<RoomMessageAttachment> parseRoomMessageAttachmentsJson(String raw) {
  if (raw.trim().isEmpty) {
    return const [];
  }
  final decoded = jsonDecode(raw);
  if (decoded is! List<dynamic>) {
    return const [];
  }
  final out = <RoomMessageAttachment>[];
  for (final item in decoded) {
    if (item is! Map<String, dynamic>) {
      continue;
    }
    final id = item['id'];
    final kind = item['kind'];
    final position = item['position'];
    final mime = item['mime'];
    final sizeBytes = item['sizeBytes'];
    if (id is! String ||
        kind is! num ||
        position is! num ||
        mime is! String ||
        sizeBytes is! num) {
      continue;
    }
    final fn = item['fileName'];
    out.add(
      RoomMessageAttachment(
        id: id,
        kind: kind.toInt(),
        position: position.toInt(),
        mime: mime,
        sizeBytes: sizeBytes.toInt(),
        fileName: fn is String ? fn : '',
        imageId: item['imageId'] is String ? item['imageId'] as String : '',
        imageAuthorId: item['imageAuthorId'] is String
            ? item['imageAuthorId'] as String
            : '',
        blurHash: item['blurHash'] is String ? item['blurHash'] as String : '',
        width: item['width'] is num ? (item['width'] as num).toInt() : 0,
        height: item['height'] is num ? (item['height'] as num).toInt() : 0,
      ),
    );
  }
  out.sort((a, b) => a.position.compareTo(b.position));
  return out;
}
