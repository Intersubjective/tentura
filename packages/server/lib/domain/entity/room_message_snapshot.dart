import 'package:freezed_annotation/freezed_annotation.dart';

import 'quoted_fact_entity.dart';

part 'room_message_snapshot.freezed.dart';

/// Viewer-neutral room message fields for realtime WS paint: plain text,
/// fact system lines (markers 10/11) and quoted messages.
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
    // DORMANT(item-threads): always null in production; General is thread_item_id IS NULL.
    // Rooms are General-only (guard: beacon_room_message_general_only_guard, DiscussionScopeDisabledException); thread_item_id is always NULL for new rows. Do not design for this path. See #192.
    String? threadItemId,
    String? replyToMessageId,
    String? replyToAuthorId,
    String? replyToAuthorTitle,
    String? replyToBodyExcerpt,
    @Default(false) bool replyToHasAttachments,
    int? semanticMarker,
    Map<String, Object?>? systemPayload,

    /// `system_message_kind` of a system line (Request plan lines are 5).
    int? systemMessageKind,
    QuotedFactEntity? quotedFact,
  }) = _RoomMessageSnapshot;
}
