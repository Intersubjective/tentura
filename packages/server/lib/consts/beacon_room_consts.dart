/// Role on `beacon_participant.role`.
abstract final class BeaconParticipantRoleBits {
  static const author = 0;
  static const steward = 1;
  static const helper = 2;
  static const candidate = 3;
  static const watcher = 4;
  static const forwarder = 5;
}

/// `beacon_room_message.semantic_marker` — sparse system semantics.
abstract final class BeaconRoomSemanticMarker {
  /// System line emitted when coordinated plan text changes (`beacon_room_state`).
  static const updatePlan = 1;

  /// Pinned fact with `BeaconFactCardVisibilityBits.public`.
  static const pinFactPublic = 2;

  /// Pinned fact visible to Room members only.
  static const pinFactPrivate = 3;

  /// Participant next-move / cue line (participant row updated).
  static const participantStatusChanged = 4;

  /// Message linked to a new `beacon_blocker`.
  static const blocker = 5;

  /// Need-info request attached to a message / participant cue.
  static const needInfo = 6;

  /// Explicit "mark done" on a message (no inference from chat text).
  static const done = 7;

  /// Inline poll message — body is empty; poll data is in `linkedPollingId`.
  static const poll = 8;
}

/// `beacon_participant.next_move_status` (sparse UX enum).
abstract final class BeaconNextMoveStatusBits {
  static const active = 0;
  static const requested = 1;
  static const done = 2;
  static const declined = 3;
  static const obsolete = 4;
}

/// `beacon_participant.next_move_source` hint for UX.
abstract final class BeaconNextMoveSourceBits {
  static const unspecified = 0;
  static const self = 1;
  static const stewardOrAuthor = 2;
}

/// `beacon_room_message_attachment.kind`
abstract final class BeaconRoomMessageAttachmentKind {
  static const image = 1;
  static const file = 2;
}

/// Max attachments per room message (images + files).
const kMaxRoomMessageAttachments = 10;

/// Max upload size per attachment (bytes).
const kMaxRoomMessageAttachmentBytes = 10 * 1024 * 1024;

/// `beacon_participant.room_access`.
abstract final class RoomAccessBits {
  static const none = 0;
  static const requested = 1;
  static const invited = 2;
  static const admitted = 3;
  static const muted = 4;
  static const left = 5;
}
