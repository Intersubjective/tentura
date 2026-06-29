import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';

/// Test double for room cubit tests (coordination list returns [items]).
class FakeCoordinationItemCaseForRoom implements CoordinationItemCase {
  const FakeCoordinationItemCaseForRoom({
    this.items = const [],
    this.markItemsSeenException,
  });

  /// Items returned by [listByBeacon] when no kind/status filter is applied.
  final List<CoordinationItem> items;
  final Exception? markItemsSeenException;

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
      // Filtered calls (e.g. open blocker) keep the legacy empty behaviour;
      // the unfiltered room-load call returns the configured [items].
      (status == null && kind == null) ? items : const [];

  @override
  Future<CoordinationItem?> fetchCurrentRootPlan(String beaconId) async => null;

  @override
  Future<CoordinationItem> updateItem({
    required String itemId,
    required String title,
    String? body,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> updatePlan({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    String? linkedMessageId,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> addPlanStep({
    required String parentItemId,
    required String title,
    String? body,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> resolvePlanStep({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> acceptAsk({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> cancelAsk({
    required String itemId,
    String? reason,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> cancelBlocker({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> remindItem({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> markAsk({
    required String beaconId,
    required String title,
    required String targetPersonId,
    String? body,
    String? linkedMessageId,
    int? staleAfterDays,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> createPromise({
    required String beaconId,
    required String title,
    required String targetPersonId,
    String? body,
    String? linkedMessageId,
    int? staleAfterDays,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> createDraftPromise({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> publishDraftPromise({
    required String itemId,
    required String targetPersonId,
    int? staleAfterDays,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> updateDraftPromise({
    required String itemId,
    required String title,
    String body = '',
    String? targetPersonId,
    bool omitTargetPersonId = false,
    int? staleAfterDays,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteDraftPromise({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> acceptPromise({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> resolvePromise({
    required String itemId,
    String? note,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> cancelPromise({
    required String itemId,
    String? reason,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> redirectPromise({
    required String itemId,
    required String newTargetPersonId,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> markBlocker({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> createDraftAsk({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> publishDraftAsk({
    required String itemId,
    required String targetPersonId,
    int? staleAfterDays,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> updateDraftAsk({
    required String itemId,
    required String title,
    String body = '',
    String? targetPersonId,
    bool omitTargetPersonId = false,
    int? staleAfterDays,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteDraftAsk({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> createDraftBlocker({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    int? staleAfterDays,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> publishDraftBlocker({
    required String itemId,
    int? staleAfterDays,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> updateDraftBlocker({
    required String itemId,
    required String title,
    String body = '',
    String? targetPersonId,
    bool omitTargetPersonId = false,
    int? staleAfterDays,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteDraftBlocker({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> redirectAsk({
    required String itemId,
    required String newTargetPersonId,
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem> acceptResolution({required String itemId}) =>
      throw UnimplementedError();

  @override
  Future<CoordinationItem> rejectResolution({
    required String itemId,
    String? reason,
  }) => throw UnimplementedError();

  @override
  Future<CoordinationItem?> fetchPendingResolutionForItem({
    required String beaconId,
    required String targetItemId,
  }) async => null;

  @override
  Future<Map<String, CoordinationResponsibility>> fetchResponsibilityBatch(
    List<String> beaconIds,
  ) async => {};

  @override
  Future<CoordinationResponsibility> fetchResponsibility(
    String beaconId,
  ) async => CoordinationResponsibility(beaconId: beaconId);

  @override
  Future<List<CoordinationItem>> fetchMyResponsibilityItems(
    String beaconId,
  ) async => const [];

  @override
  Future<void> markItemsSeen(String beaconId) async {
    if (markItemsSeenException != null) throw markItemsSeenException!;
  }
}
