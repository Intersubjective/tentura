import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/features/coordination_item/data/repository/coordination_item_repository.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';

void main() {
  late FakeCoordinationItemRepository repository;
  late CoordinationItemCase case_;

  const beaconId = 'B1';

  setUp(() {
    repository = FakeCoordinationItemRepository();
    case_ = CoordinationItemCase(repository);
  });

  group('fetchPendingResolutionForItem', () {
    test('returns open resolution matching targetItemId', () async {
      final match = _item(
        id: 'res-1',
        kind: CoordinationItemKind.resolution,
        targetItemId: 'ask-1',
      );
      repository.listByBeaconResult = [
        _item(
          id: 'res-other',
          kind: CoordinationItemKind.resolution,
          targetItemId: 'ask-2',
        ),
        match,
      ];

      final result = await case_.fetchPendingResolutionForItem(
        beaconId: beaconId,
        targetItemId: 'ask-1',
      );

      expect(result, match);
      expect(repository.lastListBeaconId, beaconId);
      expect(repository.lastListStatus, CoordinationItemStatus.open.value);
      expect(repository.lastListKind, CoordinationItemKind.resolution.value);
    });

    test('returns null when no resolution targets the item', () async {
      repository.listByBeaconResult = [
        _item(
          id: 'res-other',
          kind: CoordinationItemKind.resolution,
          targetItemId: 'ask-2',
        ),
      ];

      final result = await case_.fetchPendingResolutionForItem(
        beaconId: beaconId,
        targetItemId: 'ask-1',
      );

      expect(result, isNull);
    });
  });

  group('fetchOpenBlocker', () {
    test('returns first open blocker from repository list', () async {
      final blocker = _item(id: 'block-1', kind: CoordinationItemKind.blocker);
      repository.listByBeaconResult = [blocker];

      final result = await case_.fetchOpenBlocker(beaconId);

      expect(result, blocker);
      expect(repository.lastListStatus, CoordinationItemStatus.open.value);
      expect(repository.lastListKind, CoordinationItemKind.blocker.value);
    });

    test('returns null when no open blockers', () async {
      repository.listByBeaconResult = const [];

      final result = await case_.fetchOpenBlocker(beaconId);

      expect(result, isNull);
    });
  });

  group('fetchCurrentRootPlan', () {
    test('returns newest open root plan by createdAt', () async {
      final older = _item(
        id: 'plan-old',
        kind: CoordinationItemKind.plan,
        createdAt: DateTime.utc(2026, 6, 1),
      );
      final newer = _item(
        id: 'plan-new',
        kind: CoordinationItemKind.plan,
        createdAt: DateTime.utc(2026, 6, 10),
      );
      repository.listByBeaconResult = [older, newer];

      final result = await case_.fetchCurrentRootPlan(beaconId);

      expect(result, newer);
      expect(repository.lastListKind, CoordinationItemKind.plan.value);
      expect(repository.lastListStatus, CoordinationItemStatus.open.value);
      expect(repository.lastListRootOnly, isTrue);
    });

    test('returns null when no open root plans', () async {
      repository.listByBeaconResult = const [];

      final result = await case_.fetchCurrentRootPlan(beaconId);

      expect(result, isNull);
    });
  });

  group('repository delegation', () {
    test('listByBeacon forwards filter arguments', () async {
      repository.listByBeaconResult = const [];

      await case_.listByBeacon(
        beaconId,
        status: CoordinationItemStatus.accepted.value,
        kind: CoordinationItemKind.ask.value,
        acceptedById: 'user-a',
        targetPersonId: 'user-b',
        linkedParentItemId: 'parent-1',
        rootOnly: false,
      );

      expect(repository.lastListBeaconId, beaconId);
      expect(repository.lastListStatus, CoordinationItemStatus.accepted.value);
      expect(repository.lastListKind, CoordinationItemKind.ask.value);
      expect(repository.lastAcceptedById, 'user-a');
      expect(repository.lastTargetPersonId, 'user-b');
      expect(repository.lastLinkedParentItemId, 'parent-1');
      expect(repository.lastListRootOnly, isFalse);
    });

    test('markBlocker forwards mutation args and returns item', () async {
      final created = _item(id: 'block-new', kind: CoordinationItemKind.blocker);
      repository.markBlockerResult = created;

      final result = await case_.markBlocker(
        beaconId: beaconId,
        title: 'Blocked',
        body: 'Details',
        targetPersonId: 'user-t',
        linkedMessageId: 'msg-1',
        staleAfterDays: 5,
      );

      expect(result, created);
      expect(repository.markBlockerCalls, 1);
      expect(repository.lastMarkBlocker?.beaconId, beaconId);
      expect(repository.lastMarkBlocker?.title, 'Blocked');
      expect(repository.lastMarkBlocker?.body, 'Details');
      expect(repository.lastMarkBlocker?.targetPersonId, 'user-t');
      expect(repository.lastMarkBlocker?.linkedMessageId, 'msg-1');
      expect(repository.lastMarkBlocker?.staleAfterDays, 5);
    });

    test('resolvePromise forwards note to repository', () async {
      final resolved = _item(id: 'promise-1', kind: CoordinationItemKind.promise);
      repository.resolvePromiseResult = resolved;

      final result = await case_.resolvePromise(
        itemId: 'promise-1',
        note: 'Done',
      );

      expect(result, resolved);
      expect(repository.lastResolvePromise?.itemId, 'promise-1');
      expect(repository.lastResolvePromise?.note, 'Done');
    });

    test('fetchResponsibilityBatch returns repository map', () async {
      final responsibility = CoordinationResponsibility(
        beaconId: beaconId,
        askOpen: 2,
      );
      repository.responsibilityBatchResult = {beaconId: responsibility};

      final result = await case_.fetchResponsibilityBatch([beaconId]);

      expect(result, {beaconId: responsibility});
      expect(repository.lastResponsibilityBatchBeaconIds, [beaconId]);
    });

    test('markItemsSeen delegates to repository', () async {
      await case_.markItemsSeen(beaconId);

      expect(repository.markItemsSeenCalls, 1);
      expect(repository.lastMarkItemsSeenBeaconId, beaconId);
    });
  });
}

CoordinationItem _item({
  required String id,
  required CoordinationItemKind kind,
  CoordinationItemStatus status = CoordinationItemStatus.open,
  String? targetItemId,
  String? linkedParentItemId,
  DateTime? createdAt,
}) =>
    CoordinationItem(
      id: id,
      beaconId: 'B1',
      kind: kind,
      status: status,
      creatorId: 'user-creator',
      createdAt: createdAt ?? DateTime.utc(2026, 6, 5),
      updatedAt: DateTime.utc(2026, 6, 5),
      targetItemId: targetItemId,
      linkedParentItemId: linkedParentItemId,
    );

class FakeCoordinationItemRepository implements CoordinationItemRepository {
  List<CoordinationItem> listByBeaconResult = const [];

  String? lastListBeaconId;
  int? lastListStatus;
  int? lastListKind;
  String? lastAcceptedById;
  String? lastTargetPersonId;
  String? lastLinkedParentItemId;
  bool? lastListRootOnly;

  int markBlockerCalls = 0;
  ({
    String beaconId,
    String title,
    String? body,
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  })? lastMarkBlocker;
  CoordinationItem? markBlockerResult;

  ({String itemId, String? note})? lastResolvePromise;
  CoordinationItem? resolvePromiseResult;

  List<String>? lastResponsibilityBatchBeaconIds;
  Map<String, CoordinationResponsibility> responsibilityBatchResult = const {};

  int markItemsSeenCalls = 0;
  String? lastMarkItemsSeenBeaconId;

  @override
  Future<List<CoordinationItem>> listByBeacon(
    String beaconId, {
    int? status,
    int? kind,
    String? acceptedById,
    String? targetPersonId,
    String? linkedParentItemId,
    bool? rootOnly,
  }) async {
    lastListBeaconId = beaconId;
    lastListStatus = status;
    lastListKind = kind;
    lastAcceptedById = acceptedById;
    lastTargetPersonId = targetPersonId;
    lastLinkedParentItemId = linkedParentItemId;
    lastListRootOnly = rootOnly;
    return listByBeaconResult;
  }

  @override
  Future<CoordinationItem> markBlocker({
    required String beaconId,
    required String title,
    String? body,
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  }) async {
    markBlockerCalls++;
    lastMarkBlocker = (
      beaconId: beaconId,
      title: title,
      body: body,
      targetPersonId: targetPersonId,
      linkedMessageId: linkedMessageId,
      staleAfterDays: staleAfterDays,
    );
    return markBlockerResult!;
  }

  @override
  Future<CoordinationItem> resolvePromise({
    required String itemId,
    String? note,
  }) async {
    lastResolvePromise = (itemId: itemId, note: note);
    return resolvePromiseResult!;
  }

  @override
  Future<Map<String, CoordinationResponsibility>> fetchResponsibilityBatch(
    List<String> beaconIds,
  ) async {
    lastResponsibilityBatchBeaconIds = List<String>.from(beaconIds);
    return responsibilityBatchResult;
  }

  @override
  Future<void> markItemsSeen(String beaconId) async {
    markItemsSeenCalls++;
    lastMarkItemsSeenBeaconId = beaconId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
