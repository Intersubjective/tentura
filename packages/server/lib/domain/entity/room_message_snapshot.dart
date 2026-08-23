import 'package:freezed_annotation/freezed_annotation.dart';

part 'room_message_snapshot.freezed.dart';

/// Viewer-neutral plain-text room message fields for realtime WS paint.
@freezed
abstract class RoomMessageSnapshot with _$RoomMessageSnapshot {
  const factory RoomMessageSnapshot({
    required String id,
    required String beaconId,
    required String authorId,
    required String body,
    required DateTime createdAt,
    DateTime? editedAt,
    @Default(<String>[]) List<String> mentions,
    @Default(<Map<String, Object?>>[]) List<Map<String, Object?>> mentionSpans,
    String? threadItemId,
    String? replyToMessageId,
    String? replyToAuthorId,
    String? replyToAuthorTitle,
    String? replyToBodyExcerpt,
    @Default(false) bool replyToHasAttachments,
  }) = _RoomMessageSnapshot;
}
