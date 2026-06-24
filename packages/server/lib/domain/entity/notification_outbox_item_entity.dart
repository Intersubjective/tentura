import 'package:freezed_annotation/freezed_annotation.dart';

import 'notification_category.dart';
import 'notification_kind.dart';
import 'notification_priority.dart';

part 'notification_outbox_item_entity.freezed.dart';

/// One durable notification record for a single recipient — the row behind the
/// Notification Center feed and the email digest.
@freezed
abstract class NotificationOutboxItemEntity with _$NotificationOutboxItemEntity {
  const factory NotificationOutboxItemEntity({
    required String id,
    required String accountId,
    required NotificationCategory category,
    required NotificationKind kind,
    required NotificationPriority priority,
    required String title,
    required String body,
    required String actionUrl,
    required DateTime createdAt,
    required int collapsedCount,
    String? beaconId,
    String? coordinationItemId,
    String? actorUserId,
    DateTime? readAt,
  }) = _NotificationOutboxItemEntity;

  const NotificationOutboxItemEntity._();

  bool get isRead => readAt != null;

  /// Whether this item counts toward the actionable badge.
  bool get isActionable => category == NotificationCategory.asksOfMe;
}
