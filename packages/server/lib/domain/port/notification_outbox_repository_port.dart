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

  /// Marks the matching unread row emailed (so the digest skips it).
  Future<int> markEmailedByDedupKey(String dedupKey);

  /// Marks the given outbox ids emailed.
  Future<int> markEmailed(List<String> ids);

  /// Distinct account ids that have at least one not-yet-emailed row.
  Future<List<String>> accountsWithPendingEmail();

  /// Most recent emailed_at across the account's rows (digest cadence
  /// watermark), or null when no email has ever been sent.
  Future<DateTime?> lastEmailedAt(String accountId);

  /// Not-yet-emailed rows for an account (for the digest).
  Future<List<NotificationOutboxItemEntity>> pendingForAccount(
    String accountId,
  );

  /// How many emails were sent to [accountId] for [category] within [window]
  /// (cooldown / anti-flood).
  Future<int> countRecentEmailsByCategory({
    required String accountId,
    required NotificationCategory category,
    required Duration window,
  });

  /// Retention: deletes seen+emailed rows older than [age]. Returns the count.
  Future<int> deleteSettledOlderThan(Duration age);
}
