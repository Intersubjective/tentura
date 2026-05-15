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
}
