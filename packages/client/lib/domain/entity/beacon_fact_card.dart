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

    /// Current text revision; 1 means never edited.
    @Default(1) int revisionSeq,
    String? lastEditedBy,
    @Default('') String lastEditedByTitle,
    DateTime? lastEditedAt,

    /// Distinct editors other than the pinner.
    @Default(0) int otherEditorCount,

    /// Older revisions were pruned; the fact was edited even if
    /// [lastEditedAt] is unknown.
    @Default(false) bool historyTruncated,
    @Default(<RoomMessageAttachment>[])
    List<RoomMessageAttachment> attachments,
  }) = _BeaconFactCard;
}
