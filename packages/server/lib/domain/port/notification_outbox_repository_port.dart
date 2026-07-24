import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_outbox_item_entity.dart';

/// Durable per-recipient notification store (Notification Center + digest).
abstract interface class NotificationOutboxRepositoryPort {
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
