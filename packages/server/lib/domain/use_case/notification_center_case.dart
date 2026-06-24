import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/notification_outbox_item_entity.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';

/// Read/mark operations for the in-app Notification Center.
@injectable
class NotificationCenterCase {
  const NotificationCenterCase(this._outbox);

  final NotificationOutboxRepositoryPort _outbox;

  Future<List<NotificationOutboxItemEntity>> feed({
    required String accountId,
    int limit = 50,
    DateTime? before,
  }) =>
      _outbox.feedForAccount(
        accountId: accountId,
        limit: limit.clamp(1, 100),
        before: before,
      );

  Future<int> unreadActionableCount(String accountId) =>
      _outbox.unreadActionableCount(accountId);

  Future<int> markRead({
    required String accountId,
    required List<String> ids,
  }) =>
      _outbox.markRead(accountId: accountId, ids: ids);

  Future<int> markAllRead(String accountId) => _outbox.markAllRead(accountId);
}
