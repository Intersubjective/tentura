import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/room_message_attachment.dart';

part 'beacon_fact_card.freezed.dart';

@freezed
abstract class BeaconFactCard with _$BeaconFactCard {
  const factory BeaconFactCard({
    required String id,
    required String beaconId,
    required String factText,
    required int visibility,
    required String pinnedBy,
    required DateTime createdAt,
    required int status,
    String? sourceMessageId,
    DateTime? updatedAt,
    @Default('') String pinnedByTitle,
    @Default(<RoomMessageAttachment>[])
    List<RoomMessageAttachment> attachments,
  }) = _BeaconFactCard;
}
