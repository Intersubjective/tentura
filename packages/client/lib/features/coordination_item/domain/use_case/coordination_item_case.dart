import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_item_message.dart';

import '../../data/repository/coordination_item_repository.dart';

@singleton
class CoordinationItemCase {
  const CoordinationItemCase(this._repository);

  final CoordinationItemRepository _repository;

  Future<List<CoordinationItem>> listByBeacon(
    String beaconId, {
    int? status,
    int? kind,
    String? acceptedById,
    String? targetPersonId,
    String? linkedParentItemId,
    bool? rootOnly,
  }) =>
      _repository.listByBeacon(
        beaconId,
        status: status,
        kind: kind,
        acceptedById: acceptedById,
        targetPersonId: targetPersonId,
        linkedParentItemId: linkedParentItemId,
        rootOnly: rootOnly,
      );

  Future<CoordinationItem> markBlocker({
    required String beaconId,
    required String title,
    String? body,
    String? linkedMessageId,
  }) =>
      _repository.markBlocker(
        beaconId: beaconId,
        title: title,
        body: body,
        linkedMessageId: linkedMessageId,
      );

  Future<CoordinationItem> resolveBlocker({required String itemId}) =>
      _repository.resolveBlocker(itemId: itemId);

  Future<CoordinationItem> cancelBlocker({required String itemId}) =>
      _repository.cancelBlocker(itemId: itemId);

  Future<CoordinationItem> markAsk({
    required String beaconId,
    required String title,
    required String targetPersonId,
    String? body,
    String? linkedMessageId,
  }) =>
      _repository.markAsk(
        beaconId: beaconId,
        title: title,
        targetPersonId: targetPersonId,
        body: body,
        linkedMessageId: linkedMessageId,
      );

  Future<CoordinationItem> createSelfAsk({
    required String beaconId,
    required String title,
    String? body,
    String? linkedMessageId,
  }) =>
      _repository.createSelfAsk(
        beaconId: beaconId,
        title: title,
        body: body,
        linkedMessageId: linkedMessageId,
      );

  Future<CoordinationItem> createDraftAsk({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
  }) =>
      _repository.createDraftAsk(
        beaconId: beaconId,
        title: title,
        body: body,
        targetPersonId: targetPersonId,
      );

  Future<CoordinationItem> publishDraftAsk({
    required String itemId,
    required String targetPersonId,
  }) =>
      _repository.publishDraftAsk(
        itemId: itemId,
        targetPersonId: targetPersonId,
      );

  Future<CoordinationItem> updateDraftAsk({
    required String itemId,
    required String title,
    String body = '',
    String? targetPersonId,
    bool omitTargetPersonId = false,
  }) =>
      _repository.updateDraftAsk(
        itemId: itemId,
        title: title,
        body: body,
        targetPersonId: targetPersonId,
        omitTargetPersonId: omitTargetPersonId,
      );

  Future<void> deleteDraftAsk({required String itemId}) =>
      _repository.deleteDraftAsk(itemId: itemId);

  Future<CoordinationItem> acceptAsk({required String itemId}) =>
      _repository.acceptAsk(itemId: itemId);

  Future<CoordinationItem> resolveAsk({required String itemId, String? note}) =>
      _repository.resolveAsk(itemId: itemId, note: note);

  Future<CoordinationItem> cancelAsk({required String itemId, String? reason}) =>
      _repository.cancelAsk(itemId: itemId, reason: reason);

  Future<CoordinationItem> redirectAsk({
    required String itemId,
    required String newTargetPersonId,
  }) =>
      _repository.redirectAsk(
        itemId: itemId,
        newTargetPersonId: newTargetPersonId,
      );

  Future<CoordinationItem> updateItem({
    required String itemId,
    required String title,
    String? body,
  }) =>
      _repository.updateItem(
        itemId: itemId,
        title: title,
        body: body,
      );

  Future<CoordinationItem> updatePlan({
    required String beaconId,
    required String title,
    String? body,
    String? linkedMessageId,
  }) =>
      _repository.updatePlan(
        beaconId: beaconId,
        title: title,
        body: body,
        linkedMessageId: linkedMessageId,
      );

  Future<CoordinationItem> addPlanStep({
    required String parentItemId,
    required String title,
    String? body,
  }) =>
      _repository.addPlanStep(
        parentItemId: parentItemId,
        title: title,
        body: body,
      );

  Future<CoordinationItem> resolvePlanStep({required String itemId}) =>
      _repository.resolvePlanStep(itemId: itemId);

  Future<CoordinationItem?> fetchOpenBlocker(String beaconId) async {
    final items = await listByBeacon(
      beaconId,
      status: CoordinationItemStatus.open.value,
      kind: CoordinationItemKind.blocker.value,
    );
    return items.firstOrNull;
  }

  Future<CoordinationItem> createResolution({
    required String beaconId,
    required String title,
    String? body,
    String? targetItemId,
    String? targetMessageId,
    String? linkedMessageId,
  }) =>
      _repository.createResolution(
        beaconId: beaconId,
        title: title,
        body: body,
        targetItemId: targetItemId,
        targetMessageId: targetMessageId,
        linkedMessageId: linkedMessageId,
      );

  Future<CoordinationItem> acceptResolution({required String itemId}) =>
      _repository.acceptResolution(itemId: itemId);

  Future<CoordinationItem> rejectResolution({
    required String itemId,
    String? reason,
  }) =>
      _repository.rejectResolution(itemId: itemId, reason: reason);

  Future<CoordinationItem?> fetchCurrentRootPlan(String beaconId) async {
    final open = await listByBeacon(
      beaconId,
      kind: CoordinationItemKind.plan.value,
      status: CoordinationItemStatus.open.value,
      rootOnly: true,
    );
    if (open.isEmpty) return null;
    open.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return open.first;
  }

  Future<List<CoordinationItemMessage>> listMessages(
    String itemId, {
    int? limit,
    String? before,
  }) =>
      _repository.listMessages(itemId, limit: limit, before: before);

  Future<CoordinationItemMessage> appendMessage({
    required String itemId,
    required String body,
  }) =>
      _repository.appendMessage(itemId: itemId, body: body);

  Future<void> markItemSeenIfAllowed(String itemId) async {
    try {
      await _repository.markSeen(itemId: itemId);
    } on Object catch (_) {}
  }
}
