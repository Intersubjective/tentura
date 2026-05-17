import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_item_message.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';

/// Test double for room cubit tests (coordination list returns empty).
class FakeCoordinationItemCaseForRoom implements CoordinationItemCase {
  const FakeCoordinationItemCaseForRoom();

  @override
  Future<List<CoordinationItem>> listByBeacon(
    String beaconId, {
    int? status,
    int? kind,
    String? acceptedById,
    String? targetPersonId,
    String? linkedParentItemId,
    bool? rootOnly,
  }) async =>
      const [];

  @override
  Future<CoordinationItem?> fetchCurrentRootPlan(String beaconId) async => null;

  @override
  Future<CoordinationItem> updateItem({
    required String itemId,
    required String title,
    String? body,
  }) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> updatePlan({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    String? linkedMessageId,
  }) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> addPlanStep({
    required String parentItemId,
    required String title,
    String? body,
  }) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> resolvePlanStep({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItemMessage> appendMessage({
    required String itemId,
    required String body,
  }) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> acceptAsk({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> cancelAsk({required String itemId, String? reason}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> cancelBlocker({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> markAsk({
    required String beaconId,
    required String title,
    required String targetPersonId,
    String? body,
    String? linkedMessageId,
  }) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> createSelfAsk({
    required String beaconId,
    required String title,
    String? body,
    String? linkedMessageId,
  }) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> markBlocker({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    String? linkedMessageId,
  }) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> createDraftAsk({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    String? linkedMessageId,
  }) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> publishDraftAsk({
    required String itemId,
    required String targetPersonId,
  }) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> updateDraftAsk({
    required String itemId,
    required String title,
    String body = '',
    String? targetPersonId,
    bool omitTargetPersonId = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteDraftAsk({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> createDraftBlocker({
    required String beaconId,
    required String title,
    String? body,
  }) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> publishDraftBlocker({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> updateDraftBlocker({
    required String itemId,
    required String title,
    String body = '',
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteDraftBlocker({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<List<CoordinationItemMessage>> listMessages(
    String itemId, {
    int? limit,
    String? before,
  }) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> redirectAsk({
    required String itemId,
    required String newTargetPersonId,
  }) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> resolveAsk({required String itemId, String? note}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> resolveBlocker({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem?> fetchOpenBlocker(String beaconId) async => null;

  @override
  Future<CoordinationItem> createResolution({
    required String beaconId,
    required String title,
    String? body,
    String? targetItemId,
    String? targetMessageId,
    String? linkedMessageId,
  }) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> acceptResolution({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> rejectResolution({
    required String itemId,
    String? reason,
  }) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem?> fetchPendingResolutionForItem({
    required String beaconId,
    required String targetItemId,
  }) async =>
      null;

  @override
  Future<void> deleteMessage({
    required String itemId,
    required String messageId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> markItemSeenIfAllowed(String itemId) async {}
}
