import 'package:tentura_server/domain/entity/coordination_item_with_counts.dart';

Map<String, Object?> coordinationItemWithCountsToMap(
  CoordinationItemWithCounts row,
) {
  final item = row.item;
  return {
    'id': item.id,
    'beaconId': item.beaconId,
    'kind': item.kind,
    'status': item.status,
    'title': item.title,
    'body': item.body,
    'creatorId': item.creatorId,
    'targetPersonId': item.targetPersonId,
    'acceptedById': item.acceptedById,
    'targetItemId': item.targetItemId,
    'targetMessageId': item.targetMessageId,
    'linkedMessageId': item.linkedMessageId,
    'linkedParentItemId': item.linkedParentItemId,
    'ordering': item.ordering,
    'createdAt': item.createdAt.toIso8601String(),
    'updatedAt': item.updatedAt.toIso8601String(),
    'resolvedAt': item.resolvedAt?.toIso8601String(),
    'cancelledAt': item.cancelledAt?.toIso8601String(),
    'staleAt': item.staleAt?.toIso8601String(),
    'lastRemindedAt': item.lastRemindedAt?.toIso8601String(),
    'staleAfterDays': item.staleAfterDays,
    'source': item.source,
    'published': item.published,
    'messageCount': row.messageCount,
    'unreadCount': row.unreadCount,
    'lastSeenAt': row.lastSeenAt?.toUtc().toIso8601String(),
  };
}
