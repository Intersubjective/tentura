import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_item_message.dart';

import '../gql/_g/coordination_item_list.data.gql.dart';
import '../gql/_g/coordination_item_mark_blocker.data.gql.dart';
import '../gql/_g/coordination_item_resolve_blocker.data.gql.dart';
import '../gql/_g/coordination_item_cancel_blocker.data.gql.dart';
import '../gql/_g/coordination_item_mark_ask.data.gql.dart';
import '../gql/_g/coordination_item_accept_ask.data.gql.dart';
import '../gql/_g/coordination_item_resolve_ask.data.gql.dart';
import '../gql/_g/coordination_item_cancel_ask.data.gql.dart';
import '../gql/_g/coordination_item_redirect_ask.data.gql.dart';
import '../gql/_g/coordination_item_messages.data.gql.dart';
import '../gql/_g/coordination_item_append_message.data.gql.dart';

extension type const CoordinationItemListModel(GCoordinationItemListData_coordinationItemsByBeacon i) implements GCoordinationItemListData_coordinationItemsByBeacon {
  CoordinationItem toEntity() => CoordinationItem(
        id: i.id,
        beaconId: i.beaconId,
        kind: CoordinationItemKind.fromInt(i.kind),
        status: CoordinationItemStatus.fromInt(i.status),
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
      );
}

extension type const CoordinationItemMarkBlockerModel(GCoordinationItemMarkBlockerData_markBlocker i) implements GCoordinationItemMarkBlockerData_markBlocker {
  CoordinationItem toEntity() => CoordinationItem(
        id: i.id,
        beaconId: i.beaconId,
        kind: CoordinationItemKind.fromInt(i.kind),
        status: CoordinationItemStatus.fromInt(i.status),
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
      );
}

extension type const CoordinationItemResolveBlockerModel(GCoordinationItemResolveBlockerData_resolveBlocker i) implements GCoordinationItemResolveBlockerData_resolveBlocker {
  CoordinationItem toEntity() => CoordinationItem(
        id: i.id,
        beaconId: i.beaconId,
        kind: CoordinationItemKind.fromInt(i.kind),
        status: CoordinationItemStatus.fromInt(i.status),
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
      );
}

extension type const CoordinationItemCancelBlockerModel(GCoordinationItemCancelBlockerData_cancelBlocker i) implements GCoordinationItemCancelBlockerData_cancelBlocker {
  CoordinationItem toEntity() => CoordinationItem(
        id: i.id,
        beaconId: i.beaconId,
        kind: CoordinationItemKind.fromInt(i.kind),
        status: CoordinationItemStatus.fromInt(i.status),
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
      );
}

extension type const CoordinationItemMarkAskModel(GCoordinationItemMarkAskData_markAsk i) implements GCoordinationItemMarkAskData_markAsk {
  CoordinationItem toEntity() => CoordinationItem(
        id: i.id,
        beaconId: i.beaconId,
        kind: CoordinationItemKind.fromInt(i.kind),
        status: CoordinationItemStatus.fromInt(i.status),
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
      );
}

extension type const CoordinationItemAcceptAskModel(GCoordinationItemAcceptAskData_acceptAsk i) implements GCoordinationItemAcceptAskData_acceptAsk {
  CoordinationItem toEntity() => CoordinationItem(
        id: i.id,
        beaconId: i.beaconId,
        kind: CoordinationItemKind.fromInt(i.kind),
        status: CoordinationItemStatus.fromInt(i.status),
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
      );
}

extension type const CoordinationItemResolveAskModel(GCoordinationItemResolveAskData_resolveAsk i) implements GCoordinationItemResolveAskData_resolveAsk {
  CoordinationItem toEntity() => CoordinationItem(
        id: i.id,
        beaconId: i.beaconId,
        kind: CoordinationItemKind.fromInt(i.kind),
        status: CoordinationItemStatus.fromInt(i.status),
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
      );
}

extension type const CoordinationItemCancelAskModel(GCoordinationItemCancelAskData_cancelAsk i) implements GCoordinationItemCancelAskData_cancelAsk {
  CoordinationItem toEntity() => CoordinationItem(
        id: i.id,
        beaconId: i.beaconId,
        kind: CoordinationItemKind.fromInt(i.kind),
        status: CoordinationItemStatus.fromInt(i.status),
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
      );
}

extension type const CoordinationItemRedirectAskModel(GCoordinationItemRedirectAskData_redirectAsk i) implements GCoordinationItemRedirectAskData_redirectAsk {
  CoordinationItem toEntity() => CoordinationItem(
        id: i.id,
        beaconId: i.beaconId,
        kind: CoordinationItemKind.fromInt(i.kind),
        status: CoordinationItemStatus.fromInt(i.status),
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
