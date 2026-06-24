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
    this.systemPayload,
    required this.createdAt,
    this.editedAt,
    this.mentions = const [],
  });

  final String id;
  final String beaconId;
  final String authorId;
  final String body;
  final String? replyToMessageId;
  final String? threadItemId;
  final String? linkedPollingId;
  final int? semanticMarker;
  final Map<String, Object?>? systemPayload;
  final DateTime createdAt;
  final DateTime? editedAt;
  final List<String> mentions;
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
  });

  final String beaconId;
  final String currentLine;
  final String? openBlockerId;
  final String? lastRoomMeaningfulChange;
  final DateTime updatedAt;
  final String? updatedBy;
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
