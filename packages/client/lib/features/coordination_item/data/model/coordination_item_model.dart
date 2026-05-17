import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_item_message.dart';

import '../gql/_g/coordination_item_list.data.gql.dart';
import '../gql/_g/coordination_item_mark_blocker.data.gql.dart';
import '../gql/_g/coordination_item_resolve_blocker.data.gql.dart';
import '../gql/_g/coordination_item_cancel_blocker.data.gql.dart';
import '../gql/_g/coordination_item_mark_ask.data.gql.dart';
import '../gql/_g/coordination_item_create_self_ask.data.gql.dart';
import '../gql/_g/coordination_item_accept_ask.data.gql.dart';
import '../gql/_g/coordination_item_resolve_ask.data.gql.dart';
import '../gql/_g/coordination_item_cancel_ask.data.gql.dart';
import '../gql/_g/coordination_item_redirect_ask.data.gql.dart';
import '../gql/_g/coordination_item_messages.data.gql.dart';
import '../gql/_g/coordination_item_append_message.data.gql.dart';
import '../gql/_g/coordination_item_update_plan.data.gql.dart';
import '../gql/_g/coordination_item_add_plan_step.data.gql.dart';
import '../gql/_g/coordination_item_resolve_plan_step.data.gql.dart';
import '../gql/_g/coordination_item_create_resolution.data.gql.dart';
import '../gql/_g/coordination_item_accept_resolution.data.gql.dart';
import '../gql/_g/coordination_item_reject_resolution.data.gql.dart';
import '../gql/_g/coordination_item_create_draft_ask.data.gql.dart';
import '../gql/_g/coordination_item_publish_ask.data.gql.dart';
import '../gql/_g/coordination_item_update_draft_ask.data.gql.dart';
import '../gql/_g/coordination_item_create_draft_blocker.data.gql.dart';
import '../gql/_g/coordination_item_publish_blocker.data.gql.dart';
import '../gql/_g/coordination_item_update_draft_blocker.data.gql.dart';
import '../gql/_g/coordination_item_update.data.gql.dart';

extension type const CoordinationItemListModel(GCoordinationItemListData_coordinationItemsByBeacon i) implements GCoordinationItemListData_coordinationItemsByBeacon {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
        messageCount: i.messageCount,
        unreadCount: i.unreadCount,
        lastSeenAt:
            i.lastSeenAt == null ? null : DateTime.parse(i.lastSeenAt!),
      );
}

extension type const CoordinationItemMarkBlockerModel(GCoordinationItemMarkBlockerData_markBlocker i) implements GCoordinationItemMarkBlockerData_markBlocker {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemResolveBlockerModel(GCoordinationItemResolveBlockerData_resolveBlocker i) implements GCoordinationItemResolveBlockerData_resolveBlocker {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemCancelBlockerModel(GCoordinationItemCancelBlockerData_cancelBlocker i) implements GCoordinationItemCancelBlockerData_cancelBlocker {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemMarkAskModel(GCoordinationItemMarkAskData_markAsk i) implements GCoordinationItemMarkAskData_markAsk {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemCreateSelfAskModel(
    GCoordinationItemCreateSelfAskData_createSelfAsk i)
    implements GCoordinationItemCreateSelfAskData_createSelfAsk {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemAcceptAskModel(GCoordinationItemAcceptAskData_acceptAsk i) implements GCoordinationItemAcceptAskData_acceptAsk {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemResolveAskModel(GCoordinationItemResolveAskData_resolveAsk i) implements GCoordinationItemResolveAskData_resolveAsk {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemCancelAskModel(GCoordinationItemCancelAskData_cancelAsk i) implements GCoordinationItemCancelAskData_cancelAsk {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemRedirectAskModel(GCoordinationItemRedirectAskData_redirectAsk i) implements GCoordinationItemRedirectAskData_redirectAsk {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemMessageListModel(GCoordinationItemMessagesData_coordinationItemMessages i) implements GCoordinationItemMessagesData_coordinationItemMessages {
  CoordinationItemMessage toEntity() => CoordinationItemMessage(
        id: i.id,
        itemId: i.itemId,
        beaconId: i.beaconId,
        senderId: i.senderId,
        body: i.body,
        createdAt: DateTime.parse(i.createdAt),
        editedAt: i.editedAt == null ? null : DateTime.parse(i.editedAt!),
      );
}

extension type const CoordinationItemAppendMessageModel(GCoordinationItemAppendMessageData_appendCoordinationItemMessage i) implements GCoordinationItemAppendMessageData_appendCoordinationItemMessage {
  CoordinationItemMessage toEntity() => CoordinationItemMessage(
        id: i.id,
        itemId: i.itemId,
        beaconId: i.beaconId,
        senderId: i.senderId,
        body: i.body,
        createdAt: DateTime.parse(i.createdAt),
        editedAt: i.editedAt == null ? null : DateTime.parse(i.editedAt!),
      );
}

extension type const CoordinationItemUpdateModel(GCoordinationItemUpdateData_updateCoordinationItem i) implements GCoordinationItemUpdateData_updateCoordinationItem {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemUpdatePlanModel(GCoordinationItemUpdatePlanData_updateCoordinationPlan i) implements GCoordinationItemUpdatePlanData_updateCoordinationPlan {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemAddPlanStepModel(GCoordinationItemAddPlanStepData_addPlanStep i) implements GCoordinationItemAddPlanStepData_addPlanStep {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemResolvePlanStepModel(GCoordinationItemResolvePlanStepData_resolvePlanStep i) implements GCoordinationItemResolvePlanStepData_resolvePlanStep {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemCreateResolutionModel(GCoordinationItemCreateResolutionData_createResolution i) implements GCoordinationItemCreateResolutionData_createResolution {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemAcceptResolutionModel(GCoordinationItemAcceptResolutionData_acceptResolution i) implements GCoordinationItemAcceptResolutionData_acceptResolution {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemRejectResolutionModel(GCoordinationItemRejectResolutionData_rejectResolution i) implements GCoordinationItemRejectResolutionData_rejectResolution {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemCreateDraftAskModel(
    GCoordinationItemCreateDraftAskData_createDraftAsk i)
    implements GCoordinationItemCreateDraftAskData_createDraftAsk {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemPublishAskModel(
    GCoordinationItemPublishAskData_publishAsk i)
    implements GCoordinationItemPublishAskData_publishAsk {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemUpdateDraftAskModel(
    GCoordinationItemUpdateDraftAskData_updateDraftAsk i)
    implements GCoordinationItemUpdateDraftAskData_updateDraftAsk {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemCreateDraftBlockerModel(
    GCoordinationItemCreateDraftBlockerData_createDraftBlocker i)
    implements GCoordinationItemCreateDraftBlockerData_createDraftBlocker {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemPublishBlockerModel(
    GCoordinationItemPublishBlockerData_publishBlocker i)
    implements GCoordinationItemPublishBlockerData_publishBlocker {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}

extension type const CoordinationItemUpdateDraftBlockerModel(
    GCoordinationItemUpdateDraftBlockerData_updateDraftBlocker i)
    implements GCoordinationItemUpdateDraftBlockerData_updateDraftBlocker {
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
        resolvedAt: i.resolvedAt == null ? null : DateTime.parse(i.resolvedAt!),
        cancelledAt:
            i.cancelledAt == null ? null : DateTime.parse(i.cancelledAt!),
        staleAt: i.staleAt == null ? null : DateTime.parse(i.staleAt!),
      );
}
