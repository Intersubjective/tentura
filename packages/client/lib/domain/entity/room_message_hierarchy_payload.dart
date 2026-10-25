/// Typed `beacon_room_message.system_payload` for hierarchy notices (v1).
sealed class RoomMessageHierarchyPayload {
  const RoomMessageHierarchyPayload();
}

final class RoomMessageHierarchyChildCreated
    extends RoomMessageHierarchyPayload {
  const RoomMessageHierarchyChildCreated({
    required this.childBeaconId,
    this.sourceMessageId,
    this.title,
    this.invitedCount,
  });

  final String childBeaconId;
  final String? sourceMessageId;

  /// Title snapshot of the child, set only when the parent is a Post (a bud):
  /// Post members who are not observers of the child cannot read it, so the
  /// notice carries its own title (plan D2).
  final String? title;

  /// How many members the budder invited; set only for a Post parent.
  final int? invitedCount;

  /// A Request budded from a Post: the notice renders from the payload and is
  /// never folded into the source-message footer.
  bool get isPostBud => title != null && invitedCount != null;
}

/// Typed payload of a `postClosed` (kind 5) notice: the Post was closed by
/// budding the Request [childBeaconId] titled [title].
final class RoomMessagePostClosed {
  const RoomMessagePostClosed({
    required this.childBeaconId,
    required this.title,
  });

  final String childBeaconId;
  final String title;
}

final class RoomMessageHierarchyLifecycle extends RoomMessageHierarchyPayload {
  const RoomMessageHierarchyLifecycle({
    required this.eventId,
    required this.targetBeaconId,
    required this.direction,
    required this.toStatus,
    required this.occurredAt,
    required this.sourceDeleted,
    this.sourceTitle,
  });

  final String eventId;
  final String targetBeaconId;
  final String direction;
  final String toStatus;
  final DateTime occurredAt;
  final bool sourceDeleted;

  /// Title snapshot of the request whose status changed (#450b). Set by the
  /// server only for a Post destination whose source is not deleted.
  final String? sourceTitle;
}
