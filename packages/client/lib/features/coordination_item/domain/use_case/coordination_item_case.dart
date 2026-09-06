import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import '../../data/repository/coordination_item_repository.dart';

Never _retiredCoordinationMutation() =>
    throw UnsupportedError('Retired coordination mutation');

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

  Future<CoordinationItem> remindItem({required String itemId}) =>
      _repository.remindItem(itemId: itemId);

  Future<CoordinationItem> markBlocker({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  }) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> resolveBlocker({required String itemId}) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> cancelBlocker({required String itemId}) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> markAsk({
    required String beaconId,
    required String title,
    required String targetPersonId,
    String? body,
    String? linkedMessageId,
    int? staleAfterDays,
  }) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> createPromise({
    required String beaconId,
    required String title,
    required String targetPersonId,
    String? body,
    String? linkedMessageId,
    int? staleAfterDays,
  }) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> createDraftPromise({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  }) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> publishDraftPromise({
    required String itemId,
    required String targetPersonId,
    int? staleAfterDays,
  }) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> updateDraftPromise({
    required String itemId,
    required String title,
    String body = '',
    String? targetPersonId,
    bool omitTargetPersonId = false,
    int? staleAfterDays,
  }) =>
      _retiredCoordinationMutation();

  Future<void> deleteDraftPromise({required String itemId}) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> acceptPromise({required String itemId}) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> resolvePromise({required String itemId, String? note}) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> cancelPromise({required String itemId, String? reason}) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> redirectPromise({
    required String itemId,
    required String newTargetPersonId,
  }) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> createDraftAsk({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  }) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> publishDraftAsk({
    required String itemId,
    required String targetPersonId,
    int? staleAfterDays,
  }) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> updateDraftAsk({
    required String itemId,
    required String title,
    String body = '',
    String? targetPersonId,
    bool omitTargetPersonId = false,
    int? staleAfterDays,
  }) =>
      _retiredCoordinationMutation();

  Future<void> deleteDraftAsk({required String itemId}) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> createDraftBlocker({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    int? staleAfterDays,
  }) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> publishDraftBlocker({
    required String itemId,
    int? staleAfterDays,
  }) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> updateDraftBlocker({
    required String itemId,
    required String title,
    String body = '',
    String? targetPersonId,
    bool omitTargetPersonId = false,
    int? staleAfterDays,
  }) =>
      _retiredCoordinationMutation();

  Future<void> deleteDraftBlocker({required String itemId}) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> acceptAsk({required String itemId}) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> resolveAsk({required String itemId, String? note}) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> cancelAsk({required String itemId, String? reason}) =>
      _retiredCoordinationMutation();

  Future<CoordinationItem> redirectAsk({
    required String itemId,
    required String newTargetPersonId,
  }) =>
      _retiredCoordinationMutation();

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
    String? targetPersonId,
    String? linkedMessageId,
  }) =>
      _repository.updatePlan(
        beaconId: beaconId,
        title: title,
        body: body,
        targetPersonId: targetPersonId,
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

  Future<Map<String, CoordinationResponsibility>> fetchResponsibilityBatch(
    List<String> beaconIds,
  ) =>
      _repository.fetchResponsibilityBatch(beaconIds);

  Future<CoordinationResponsibility> fetchResponsibility(String beaconId) =>
      _repository.fetchResponsibility(beaconId);

  Future<List<CoordinationItem>> fetchMyResponsibilityItems(String beaconId) =>
      _repository.fetchMyResponsibilityItems(beaconId);

  Future<void> markItemsSeen(String beaconId) =>
      _repository.markItemsSeen(beaconId);
}
