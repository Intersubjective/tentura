import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura/domain/entity/quoted_fact.dart';
import 'package:tentura/domain/entity/room_message_mention_span.dart';

part 'realtime_room_message_paint.freezed.dart';

/// Optional plain-text room message paint on `room_message` insert invalidations.
@freezed
abstract class RealtimeRoomMessagePaint with _$RealtimeRoomMessagePaint {
  const factory RealtimeRoomMessagePaint({
    required String id,
    required String beaconId,
    required String authorId,
    required String body,
    required DateTime createdAt,
    DateTime? editedAt,
    @Default(<String>[]) List<String> mentions,
    @Default(<RoomMessageMentionSpan>[])
    List<RoomMessageMentionSpan> mentionSpans,
    String? threadItemId,
    String? replyToMessageId,
    String? replyToAuthorId,
    String? replyToAuthorTitle,
    String? replyToBodyExcerpt,
    @Default(false) bool replyToHasAttachments,
    int? semanticMarker,
    Map<String, dynamic>? systemPayload,
    QuotedFact? quotedFact,
  }) = _RealtimeRoomMessagePaint;
}
