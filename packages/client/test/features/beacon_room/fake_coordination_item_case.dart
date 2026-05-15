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
  Future<CoordinationItem> updatePlan({
    required String beaconId,
    required String title,
    String? body,
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
  Future<CoordinationItem> markBlocker({
    required String beaconId,
    required String title,
    String? body,
    String? linkedMessageId,
  }) =>
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
}
