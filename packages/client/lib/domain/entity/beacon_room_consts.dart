/// Mirrors `packages/server/lib/consts/beacon_room_consts.dart`.
abstract final class BeaconParticipantRoleBits {
  static const author = 0;
  static const steward = 1;
  static const helper = 2;
  static const candidate = 3;
  static const watcher = 4;
  static const forwarder = 5;
}

abstract final class RoomAccessBits {
  static const none = 0;
  static const requested = 1;
  static const invited = 2;
  static const admitted = 3;
  static const muted = 4;
  static const left = 5;
}

/// Mirrors `packages/server/lib/consts/beacon_participant_status_bits.dart`.
/// Mirrors server [BeaconNextMoveSourceBits].
abstract final class BeaconNextMoveSourceBits {
  static const unspecified = 0;
  static const self = 1;
  static const stewardOrAuthor = 2;
}

/// Mirrors server [BeaconRoomSemanticMarker].
abstract final class BeaconRoomSemanticMarker {
  static const updatePlan = 1;
  static const pinFactPublic = 2;
  static const pinFactPrivate = 3;
  static const participantStatusChanged = 4;
  static const blocker = 5;
  static const needInfo = 6;
  static const done = 7;
}

/// Default emoji for room message reactions (toggle via `RoomMessageReactionToggle`).
abstract final class BeaconRoomMessageReaction {
  static const defaultEmoji = '👍';
}

/// Mirrors server [BeaconRoomMessageAttachmentKind].
abstract final class BeaconRoomMessageAttachmentKind {
  static const image = 1;
  static const file = 2;
}

/// Mirrors server [kMaxRoomMessageAttachments].
const kMaxRoomMessageAttachments = 10;

/// Mirrors server [kMaxRoomMessageAttachmentBytes] (10 MiB).
const kMaxRoomMessageAttachmentBytes = 10 * 1024 * 1024;

abstract final class BeaconParticipantStatusBits {
  static const watching = 0;
  static const offeredHelp = 1;
  static const candidate = 2;
  static const admitted = 3;
  static const checking = 4;
  static const committed = 5;
  static const needsInfo = 6;
  static const blocked = 7;
  static const done = 8;
  static const withdrawn = 9;
}
