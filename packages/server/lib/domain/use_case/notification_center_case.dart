import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/coordination/filter_beacon_notifications.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_outbox_item_entity.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/attention_ack_port.dart';
import 'package:tentura_server/domain/port/attention_query_port.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';

/// Read/mark operations for the in-app Notification Center.
@injectable
class NotificationCenterCase {
  NotificationCenterCase(
    this._outbox,
    this._guard, {
    AttentionQueryPort? attentionQuery,
    AttentionAckPort? attentionAck,
  }) : _attentionQuery = attentionQuery,
       _attentionAck = attentionAck;

  final NotificationOutboxRepositoryPort _outbox;
  final BeaconAccessGuard _guard;
  final AttentionQueryPort? _attentionQuery;
  final AttentionAckPort? _attentionAck;

  Future<List<NotificationOutboxItemEntity>> feed({
    required String accountId,
    int limit = 50,
    DateTime? before,
  }) async {
    final attentionQuery = _attentionQuery;
    if (attentionQuery != null) {
      final feed = await attentionQuery.attentionFeed(
        accountId: accountId,
        view: AttentionFeedView.all,
        // Legacy pagination exposes only a timestamp. The V2 cursor remains
        // composite; this compatibility path preserves its existing shape.
        cursor: before == null
            ? null
            : AttentionCursor(createdAt: before, id: '\uffff'),
        limit: limit.clamp(1, 100),
      );
      return [for (final receipt in feed.page.items) _fromAttention(receipt)];
    }
    final rows = await _outbox.feedForAccount(
      accountId: accountId,
      limit: limit.clamp(1, 100),
      before: before,
    );
    return filterBeaconNotifications(
      guard: _guard,
      viewerId: accountId,
      items: rows,
    );
  }

  Future<int> unreadActionableCount(String accountId) async {
    final attentionQuery = _attentionQuery;
    if (attentionQuery != null) {
      return (await attentionQuery.attentionFeed(
        accountId: accountId,
        view: AttentionFeedView.unread,
        limit: 1,
      )).summary.unreadTotal;
    }
    return _outbox.unreadActionableCount(accountId);
  }

  Future<int> markRead({
    required String accountId,
    required List<String> ids,
  }) =>
      _attentionAck?.markSeen(accountId: accountId, ids: ids) ??
      _outbox.markRead(accountId: accountId, ids: ids);

  Future<int> markAllRead(String accountId) =>
      _attentionAck?.markAllSeen(accountId) ?? _outbox.markAllRead(accountId);

  NotificationOutboxItemEntity _fromAttention(AttentionReceipt receipt) =>
      NotificationOutboxItemEntity(
        id: receipt.id,
        accountId: receipt.accountId,
        category: receipt.category,
        kind: receipt.kind,
        priority: receipt.priority,
        title: receipt.title,
        body: receipt.body,
        actionUrl: receipt.actionUrl,
        createdAt: receipt.createdAt,
        collapsedCount: receipt.collapsedCount,
        beaconId: receipt.beaconId,
        coordinationItemId: receipt.coordinationItemId,
        actorUserId: receipt.actorUserId,
        readAt: receipt.seenAt,
        seenAt: receipt.seenAt,
        sourceEventKey: receipt.sourceEventKey,
        destinationKind: receipt.destinationKind?.wireName,
        targetEntityId: receipt.targetEntityId,
        presentationKey: receipt.presentationKey,
        inAppPreferenceClass: receipt.inAppPreferenceClass?.wireName,
        presentationPayload: receipt.presentationPayload,
        suppressionClass: receipt.suppressionClass.name,
        accessPolicy: receipt.accessPolicy.wireName,
      );
}
