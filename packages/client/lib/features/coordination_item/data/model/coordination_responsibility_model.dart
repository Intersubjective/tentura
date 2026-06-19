import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';

import '../gql/_g/coordination_my_responsibility_items.data.gql.dart';
import '../gql/_g/coordination_responsibility_batch.data.gql.dart';

extension type const CoordinationResponsibilityBatchRowModel(
  GCoordinationResponsibilityBatchData_coordinationResponsibilityBatch i)
    implements
        GCoordinationResponsibilityBatchData_coordinationResponsibilityBatch {
  CoordinationResponsibility toEntity() => CoordinationResponsibility(
        beaconId: i.beaconId,
        askOpen: i.askOpen,
        askNew: i.askNew,
        promiseOpen: i.promiseOpen,
        promiseNew: i.promiseNew,
        blockerOpen: i.blockerOpen,
        blockerNew: i.blockerNew,
        reviewOpen: i.reviewOpen,
        reviewNew: i.reviewNew,
        othersOpenCount: i.othersOpenCount,
      );
}

extension type const CoordinationMyResponsibilityItemModel(
  GCoordinationMyResponsibilityItemsData_coordinationMyResponsibilityItems i)
    implements
        GCoordinationMyResponsibilityItemsData_coordinationMyResponsibilityItems {
  CoordinationItem toEntity() => CoordinationItem(
        id: i.id,
        beaconId: i.beaconId,
        kind: CoordinationItemKind.fromInt(i.kind),
        status: CoordinationItemStatus.fromInt(i.status),
        source: i.source,
        published: i.published,
        title: i.title,
        body: i.body,
        creatorId: i.creatorId,
        targetPersonId: i.targetPersonId,
        acceptedById: i.acceptedById,
        targetItemId: i.targetItemId,
        targetMessageId: i.targetMessageId,
        linkedMessageId: i.linkedMessageId,
        linkedParentItemId: i.linkedParentItemId,
        createdAt: DateTime.parse(i.createdAt),
        updatedAt: DateTime.parse(i.updatedAt),
        resolvedAt:
            i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
        lastRemindedAt: i.lastRemindedAt == null
            ? null
            : DateTime.parse(i.lastRemindedAt!),
        staleAfterDays: i.staleAfterDays,
        messageCount: i.messageCount,
        unreadCount: i.unreadCount,
        lastSeenAt:
            i.lastSeenAt == null ? null : DateTime.parse(i.lastSeenAt!),
      );
}
