import 'package:tentura/domain/entity/coordination_item.dart';

import '../gql/_g/coordination_item_list.data.gql.dart';
import '../gql/_g/coordination_item_update_plan.data.gql.dart';
import '../gql/_g/coordination_item_add_plan_step.data.gql.dart';
import '../gql/_g/coordination_item_resolve_plan_step.data.gql.dart';
import '../gql/_g/coordination_item_update.data.gql.dart';
import '../gql/_g/coordination_item_remind.data.gql.dart';

CoordinationItem coordinationItemFromFields({
  required String id,
  required String beaconId,
  required int kind,
  required int status,
  required int source,
  required bool published,
  required String title,
  required String body,
  required String creatorId,
  String? targetPersonId,
  String? acceptedById,
  String? targetItemId,
  String? targetMessageId,
  String? linkedMessageId,
  String? linkedParentItemId,
  required String createdAt,
  required String updatedAt,
  String? resolvedAt,
  String? cancelledAt,
  String? staleAt,
  String? lastRemindedAt,
  int? staleAfterDays,
  int messageCount = 0,
  int unreadCount = 0,
  String? lastSeenAt,
}) =>
    CoordinationItem(
      id: id,
      beaconId: beaconId,
      kind: CoordinationItemKind.fromInt(kind),
      status: CoordinationItemStatus.fromInt(status),
      source: source,
      published: published,
      title: title,
      body: body,
      creatorId: creatorId,
      targetPersonId: targetPersonId,
      acceptedById: acceptedById,
      targetItemId: targetItemId,
      targetMessageId: targetMessageId,
      linkedMessageId: linkedMessageId,
      linkedParentItemId: linkedParentItemId,
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
      resolvedAt: resolvedAt == null ? null : DateTime.parse(resolvedAt),
      cancelledAt: cancelledAt == null ? null : DateTime.parse(cancelledAt),
      staleAt: staleAt == null ? null : DateTime.parse(staleAt),
      lastRemindedAt:
          lastRemindedAt == null ? null : DateTime.parse(lastRemindedAt),
      staleAfterDays: staleAfterDays,
      messageCount: messageCount,
      unreadCount: unreadCount,
      lastSeenAt: lastSeenAt == null ? null : DateTime.parse(lastSeenAt),
    );

CoordinationItem _coordinationItemFromMutationRow({
  required String id,
  required String beaconId,
  required int kind,
  required int status,
  required int source,
  required bool published,
  required String title,
  required String body,
  required String creatorId,
  String? targetPersonId,
  String? acceptedById,
  String? targetItemId,
  String? targetMessageId,
  String? linkedMessageId,
  String? linkedParentItemId,
  required String createdAt,
  required String updatedAt,
  String? resolvedAt,
  String? cancelledAt,
  String? staleAt,
  String? lastRemindedAt,
  int? staleAfterDays,
  int messageCount = 0,
  int unreadCount = 0,
  String? lastSeenAt,
}) =>
    CoordinationItem(
      id: id,
      beaconId: beaconId,
      kind: CoordinationItemKind.fromInt(kind),
      status: CoordinationItemStatus.fromInt(status),
      source: source,
      published: published,
      title: title,
      body: body,
      creatorId: creatorId,
      targetPersonId: targetPersonId,
      acceptedById: acceptedById,
      targetItemId: targetItemId,
      targetMessageId: targetMessageId,
      linkedMessageId: linkedMessageId,
      linkedParentItemId: linkedParentItemId,
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
      resolvedAt: resolvedAt == null ? null : DateTime.parse(resolvedAt),
      cancelledAt: cancelledAt == null ? null : DateTime.parse(cancelledAt),
      staleAt: staleAt == null ? null : DateTime.parse(staleAt),
      lastRemindedAt:
          lastRemindedAt == null ? null : DateTime.parse(lastRemindedAt),
      staleAfterDays: staleAfterDays,
      messageCount: messageCount,
      unreadCount: unreadCount,
      lastSeenAt: lastSeenAt == null ? null : DateTime.parse(lastSeenAt),
    );

extension type const CoordinationItemListModel(
    GCoordinationItemListData_coordinationItemsByBeacon i)
    implements GCoordinationItemListData_coordinationItemsByBeacon {
  CoordinationItem toEntity() => coordinationItemFromFields(
        id: i.id,
        beaconId: i.beaconId,
        kind: i.kind,
        status: i.status,
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
        createdAt: i.createdAt,
        updatedAt: i.updatedAt,
        resolvedAt: i.resolvedAt,
        cancelledAt: i.cancelledAt,
        staleAt: i.staleAt,
        lastRemindedAt: i.lastRemindedAt,
        staleAfterDays: i.staleAfterDays,
        messageCount: i.messageCount,
        unreadCount: i.unreadCount,
        lastSeenAt: i.lastSeenAt,
      );
}

extension type const CoordinationItemUpdateModel(
    GCoordinationItemUpdateData_updateCoordinationItem i)
    implements GCoordinationItemUpdateData_updateCoordinationItem {
  CoordinationItem toEntity() => _coordinationItemFromMutationRow(
        id: i.id,
        beaconId: i.beaconId,
        kind: i.kind,
        status: i.status,
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
        createdAt: i.createdAt,
        updatedAt: i.updatedAt,
        resolvedAt: i.resolvedAt,
        cancelledAt: i.cancelledAt,
        staleAt: i.staleAt,
        lastRemindedAt: i.lastRemindedAt,
        staleAfterDays: i.staleAfterDays,
      );
}

extension type const CoordinationItemUpdatePlanModel(
    GCoordinationItemUpdatePlanData_updateCoordinationPlan i)
    implements GCoordinationItemUpdatePlanData_updateCoordinationPlan {
  CoordinationItem toEntity() => _coordinationItemFromMutationRow(
        id: i.id,
        beaconId: i.beaconId,
        kind: i.kind,
        status: i.status,
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
        createdAt: i.createdAt,
        updatedAt: i.updatedAt,
        resolvedAt: i.resolvedAt,
        cancelledAt: i.cancelledAt,
        staleAt: i.staleAt,
        lastRemindedAt: i.lastRemindedAt,
        staleAfterDays: i.staleAfterDays,
      );
}

extension type const CoordinationItemAddPlanStepModel(
    GCoordinationItemAddPlanStepData_addPlanStep i)
    implements GCoordinationItemAddPlanStepData_addPlanStep {
  CoordinationItem toEntity() => _coordinationItemFromMutationRow(
        id: i.id,
        beaconId: i.beaconId,
        kind: i.kind,
        status: i.status,
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
        createdAt: i.createdAt,
        updatedAt: i.updatedAt,
        resolvedAt: i.resolvedAt,
        cancelledAt: i.cancelledAt,
        staleAt: i.staleAt,
        lastRemindedAt: i.lastRemindedAt,
        staleAfterDays: i.staleAfterDays,
      );
}

extension type const CoordinationItemResolvePlanStepModel(
    GCoordinationItemResolvePlanStepData_resolvePlanStep i)
    implements GCoordinationItemResolvePlanStepData_resolvePlanStep {
  CoordinationItem toEntity() => _coordinationItemFromMutationRow(
        id: i.id,
        beaconId: i.beaconId,
        kind: i.kind,
        status: i.status,
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
        createdAt: i.createdAt,
        updatedAt: i.updatedAt,
        resolvedAt: i.resolvedAt,
        cancelledAt: i.cancelledAt,
        staleAt: i.staleAt,
        lastRemindedAt: i.lastRemindedAt,
        staleAfterDays: i.staleAfterDays,
      );
}

extension type const CoordinationItemRemindModel(
    GCoordinationItemRemindData_remindCoordinationItem i)
    implements GCoordinationItemRemindData_remindCoordinationItem {
  CoordinationItem toEntity() => _coordinationItemFromMutationRow(
        id: i.id,
        beaconId: i.beaconId,
        kind: i.kind,
        status: i.status,
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
        createdAt: i.createdAt,
        updatedAt: i.updatedAt,
        resolvedAt: i.resolvedAt,
        cancelledAt: i.cancelledAt,
        staleAt: i.staleAt,
        lastRemindedAt: i.lastRemindedAt,
        staleAfterDays: i.staleAfterDays,
        messageCount: i.messageCount,
        unreadCount: i.unreadCount,
        lastSeenAt: i.lastSeenAt,
      );
}
