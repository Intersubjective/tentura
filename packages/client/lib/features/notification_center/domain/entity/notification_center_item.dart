/// Purpose-based grouping mirrored from the server (`NotificationCategory`).
enum NotificationCenterCategory {
  asksOfMe,
  unblocksMe,
  coordination,
  connections,
  ambient,
  unknown;

  static NotificationCenterCategory parse(String? name) {
    for (final c in NotificationCenterCategory.values) {
      if (c.name == name) {
        return c;
      }
    }
    return NotificationCenterCategory.unknown;
  }

  /// Whether items in this category count toward the actionable badge.
  bool get isActionable => this == NotificationCenterCategory.asksOfMe;
}

/// One durable Notification Center row (projection of `NotificationItem`).
class NotificationCenterItem {
  const NotificationCenterItem({
    required this.id,
    required this.category,
    required this.kind,
    required this.title,
    required this.body,
    required this.actionUrl,
    required this.createdAt,
    required this.collapsedCount,
    this.readAt,
    this.beaconId,
    this.coordinationItemId,
    this.actorUserId,
  });

  final String id;
  final NotificationCenterCategory category;
  final String kind;
  final String title;
  final String body;
  final String actionUrl;
  final DateTime createdAt;
  final int collapsedCount;
  final DateTime? readAt;
  final String? beaconId;
  final String? coordinationItemId;
  final String? actorUserId;

  bool get isRead => readAt != null;
}
