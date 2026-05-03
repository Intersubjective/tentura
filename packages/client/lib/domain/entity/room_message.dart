import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';

part 'room_message.freezed.dart';

@freezed
abstract class RoomMessage with _$RoomMessage {
  const factory RoomMessage({
    required String id,
    required String beaconId,
    required String authorId,
    required String body,
    required DateTime createdAt,
    DateTime? editedAt,
    @Default(Profile()) Profile author,
    @Default(<String, int>{}) Map<String, int> reactionCounts,
    String? myReaction,
    int? semanticMarker,
    String? linkedBlockerId,
    String? linkedFactCardId,
    String? systemPayloadJson,
    @Default(<RoomMessageAttachment>[]) List<RoomMessageAttachment> attachments,
  }) = _RoomMessage;
}
