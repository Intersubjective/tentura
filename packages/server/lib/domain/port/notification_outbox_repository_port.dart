import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_outbox_item_entity.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';

/// Durable per-recipient notification store (Notification Center + digest).
abstract interface class NotificationOutboxRepositoryPort {
  /// Persists one record for a recipient. Unread duplicates (same [dedupKey])
  /// are collapsed: the existing row's timestamp is bumped and its
  /// collapsed_count incremented instead of inserting a new row.
  Future<void> enqueue({
    required String accountId,
    required NotificationCategory category,
    required NotificationKind kind,
    required NotificationPriority priority,
    required String title,
    required String body,
    required String actionUrl,
    required String dedupKey,
    String? beaconId,
    String? coordinationItemId,
    String? actorUserId,
  });

  /// Newest-first feed for the Notification Center, paginated by [before].
  Future<List<NotificationOutboxItemEntity>> feedForAccount({
    required String accountId,
    int limit,
    DateTime? before,
  });

  /// Count of unread actionable items (drives the badge).
  Future<int> unreadActionableCount(String accountId);

  /// Marks the given ids read for the account; returns the number updated.
  Future<int> markRead({
    required String accountId,
    required List<String> ids,
  });

  /// Marks every unread item for the account as read.
  Future<int> markAllRead(String accountId);
}
