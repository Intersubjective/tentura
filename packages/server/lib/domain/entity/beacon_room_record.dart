import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/beacon_kind.dart';

/// Domain projection of [`beacon_room_message`].
final class BeaconRoomMessageRecord {
  const BeaconRoomMessageRecord({
    required this.id,
    required this.beaconId,
    required this.authorId,
    this.body = '',
    this.replyToMessageId,
    this.threadItemId,
    this.linkedPollingId,
    this.semanticMarker,
    this.systemMessageKind,
    this.systemPayload,
    required this.createdAt,
    this.editedAt,
    this.mentions = const [],
    this.mentionSpans = const [],
    this.quotedFactCardId,
    this.quotedFactRevisionSeq,
  });

  final String id;
  final String beaconId;
  final String? authorId;
  final String body;
  final String? replyToMessageId;
  // DORMANT(item-threads): always null in production; General is thread_item_id IS NULL.
  // Rooms are General-only (guard: beacon_room_message_general_only_guard, DiscussionScopeDisabledException); thread_item_id is always NULL for new rows. Do not design for this path. See #192.
  final String? threadItemId;
  final String? linkedPollingId;
  final int? semanticMarker;
  final int? systemMessageKind;
  final Map<String, Object?>? systemPayload;
  final DateTime createdAt;
  final DateTime? editedAt;
  final List<String> mentions;
  final List<Map<String, Object?>> mentionSpans;

  /// Quoted fact revision snapshot; both set or both null.
  final String? quotedFactCardId;
  final int? quotedFactRevisionSeq;
}

/// An admitted room participant's display identity for mention validation.
final class AdmittedRoomMentionParticipant {
  const AdmittedRoomMentionParticipant({
    required this.userId,
    required this.displayName,
    required this.handle,
  });

  final String userId;
  final String displayName;
  final String handle;
}

/// Domain projection of [`beacon_room_state`].
final class BeaconRoomStateRecord {
  const BeaconRoomStateRecord({
    required this.beaconId,
    this.currentLine = '',
    this.openBlockerId,
    this.lastRoomMeaningfulChange,
    required this.updatedAt,
    this.updatedBy,
    this.currentLineRevision = 0,
  });

  final String beaconId;
  final String currentLine;
  final String? openBlockerId;
  final String? lastRoomMeaningfulChange;
  final DateTime updatedAt;
  final String? updatedBy;

  /// Counts changes of [currentLine]; the base a next-step save sends back
  /// (#517). 0 when the Request has no row yet.
  final int currentLineRevision;
}

/// Domain projection of [`beacon_participant`].
final class BeaconParticipantRecord {
  const BeaconParticipantRecord({
    required this.id,
    required this.beaconId,
    required this.userId,
    required this.role,
    required this.status,
    required this.roomAccess,
    this.nextMoveText,
    this.nextMoveStatus,
    this.nextMoveSource,
    this.linkedMessageId,
    this.offerNote,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String beaconId;
  final String userId;
  final int role;
  final int status;
  final int roomAccess;
  final String? nextMoveText;
  final int? nextMoveStatus;
  final int? nextMoveSource;
  final String? linkedMessageId;
  final String? offerNote;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// Domain projection of [`beacon_room_message_attachment`].
final class BeaconRoomMessageAttachmentRecord {
  const BeaconRoomMessageAttachmentRecord({
    required this.id,
    required this.messageId,
    required this.kind,
    this.imageId,
    this.fileUrl,
    this.fileName = '',
    this.mime = 'application/octet-stream',
    this.sizeBytes = 0,
    this.width,
    this.height,
    this.position = 0,
  });

  final String id;
  final String messageId;
  final int kind;
  final String? imageId;
  final String? fileUrl;
  final String fileName;
  final String mime;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int position;
}

/// Minimal polling fields for vote validation in [PollingCase].
final class PollingVotePolicy {
  const PollingVotePolicy({
    required this.pollType,
    required this.allowRevote,
  });

  final String pollType;
  final bool allowRevote;
}

/// One Request and its room as one viewer sees them: what the Requests list
/// reads for every card, in one batch over many Requests (#747).
final class RoomViewerFacts {
  const RoomViewerFacts({
    required this.beaconId,
    required this.authorId,
    required this.kind,
    required this.status,
    required this.updatedAt,
    required this.isSteward,
    this.participantRoomAccess,
    this.nextMoveText,
    this.currentLine,
    this.lastRoomMeaningfulChange,
    this.lastSeenAt,
  });

  final String beaconId;
  final String? authorId;
  final BeaconKind kind;
  final BeaconStatus status;
  final DateTime updatedAt;
  final bool isSteward;

  /// The viewer's `beacon_participant.room_access`; null when they have no
  /// participant row.
  final int? participantRoomAccess;
  final String? nextMoveText;

  /// From `beacon_room_state`; null when the room has no state row.
  final String? currentLine;
  final String? lastRoomMeaningfulChange;

  /// The viewer's main-room watermark.
  final DateTime? lastSeenAt;

  bool get isParticipant => participantRoomAccess != null;
}
