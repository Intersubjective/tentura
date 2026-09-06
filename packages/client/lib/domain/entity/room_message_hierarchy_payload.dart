/// Typed `beacon_room_message.system_payload` for hierarchy notices (v1).
sealed class RoomMessageHierarchyPayload {
  const RoomMessageHierarchyPayload();
}

final class RoomMessageHierarchyChildCreated extends RoomMessageHierarchyPayload {
  const RoomMessageHierarchyChildCreated({
    required this.childBeaconId,
    this.sourceMessageId,
  });

  final String childBeaconId;
  final String? sourceMessageId;
}

final class RoomMessageHierarchyLifecycle extends RoomMessageHierarchyPayload {
  const RoomMessageHierarchyLifecycle({
    required this.eventId,
    required this.targetBeaconId,
    required this.direction,
    required this.toStatus,
    required this.occurredAt,
    required this.sourceDeleted,
  });

  final String eventId;
  final String targetBeaconId;
  final String direction;
  final String toStatus;
  final DateTime occurredAt;
  final bool sourceDeleted;
}
