/// Server-reported unread count plus the seen watermark it was based on.
class RoomUnreadSnapshot {
  const RoomUnreadSnapshot({
    required this.count,
    this.serverSeenAt,
  });

  final int count;
  final DateTime? serverSeenAt;
}
