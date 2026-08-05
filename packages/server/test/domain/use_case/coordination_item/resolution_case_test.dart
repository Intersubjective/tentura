import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/accept_resolution_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/create_resolution_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/reject_resolution_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/coordination_item_record_fixtures.dart';
import '../../../support/test_attention_harness.dart';

class _StubBeacons extends Fake implements BeaconRepositoryPort {
  _StubBeacons(this.entity);

  BeaconEntity entity;

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async {
    if (entity.id != beaconId) {
      throw StateError('missing beacon');
    }
    return entity;
  }
}

class _StatusUpdate {
  const _StatusUpdate({
    required this.id,
    required this.newStatus,
    required this.actorId,
  });

  final String id;
  final int newStatus;
  final String actorId;
}

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  final Map<String, CoordinationItemRecord> itemsById = {};
  final List<_StatusUpdate> statusUpdates = [];
  int? lastCreateKind;
  String? lastCreateTitle;
  String? lastCreateBody;
  String? lastTargetItemId;
  CoordinationItemRecord? nextReturnOnCreate;
  DateTime? nextUpdatedAt;

  @override
  Future<CoordinationItemRecord?> getById(String id) async => itemsById[id];

  @override
  Future<CoordinationItemRecord> create({
    required String beaconId,
    required int kind,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
    String? targetItemId,
    String? targetMessageId,
    String? linkedMessageId,
    String? linkedParentItemId,
    int ordering = 0,
    int? staleAfterDays,
  }) async {
    lastCreateKind = kind;
    lastCreateTitle = title;
    lastCreateBody = body;
    lastTargetItemId = targetItemId;
    if (nextReturnOnCreate != null) {
      return nextReturnOnCreate!;
    }
    final now = DateTime.utc(2024);
    return testCoordinationItem(
      id: 'Riiiiiiiiiiii',
      beaconId: beaconId,
      kind: kind,
      status: coordinationItemStatusOpen,
      title: title,
      body: body,
      creatorId: creatorId,
      published: true,
      source: coordinationItemSourceDefault,
      createdAt: now,
      updatedAt: now,
      ordering: ordering,
    ).copyWith(
      targetItemId: targetItemId,
      targetMessageId: targetMessageId,
      linkedMessageId: linkedMessageId,
    );
  }

  @override
  Future<CoordinationItemRecord> updateStatus({
    required String id,
    required int newStatus,
    required String actorId,
  }) async {
    statusUpdates.add(
      _StatusUpdate(id: id, newStatus: newStatus, actorId: actorId),
    );
    final existing = itemsById[id];
    if (existing == null) {
      throw StateError('missing item $id');
    }
    final updatedAt = nextUpdatedAt ?? existing.updatedAt;
    final updated = existing.copyWith(status: newStatus, updatedAt: updatedAt);
    itemsById[id] = updated;
    return updated;
  }
}

final class _RecordingDispatch extends Fake implements AttentionDispatchPort {
  final List<AttentionDispatchIntent> recorded = [];

  @override
  Future<void> record(AttentionDispatchIntent intent) async {
    recorded.add(intent);
  }
}

BeaconEntity _openBeacon(String id) => BeaconEntity(
      id: id,
      title: 'Beacon',
      author: const UserEntity(id: 'Uauthor000001'),
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );

CoordinationItemRecord _sampleResolution({
  required String id,
  required String beaconId,
  required String creatorId,
  String? targetItemId,
  int status = coordinationItemStatusOpen,
}) {
  final now = DateTime.utc(2024);
  return testCoordinationItem(
    id: id,
    beaconId: beaconId,
    kind: coordinationItemKindResolution,
    status: status,
    title: 'Resolution',
    body: 'Body',
    creatorId: creatorId,
    published: true,
    source: coordinationItemSourceDefault,
    createdAt: now,
    updatedAt: now,
    ordering: 0,
  ).copyWith(targetItemId: targetItemId);
}

final class _SnapshotUnitOfWork implements MutatingUnitOfWorkPort {
  _SnapshotUnitOfWork(this._items);

  final _StubItems _items;

  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) async {
    final snapshot = Map<String, CoordinationItemRecord>.from(_items.itemsById);
    try {
      return await action();
    } on Object catch (error, stackTrace) {
      _items.itemsById
        ..clear()
        ..addAll(snapshot);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

final class _FailingOnSecondUpdateItems extends _StubItems {
  int updateCalls = 0;

  @override
  Future<CoordinationItemRecord> updateStatus({
    required String id,
    required int newStatus,
    required String actorId,
  }) async {
    updateCalls++;
    if (updateCalls == 2) {
      throw StateError('simulated failure');
    }
    return super.updateStatus(id: id, newStatus: newStatus, actorId: actorId);
  }
}

void main() {
  const creatorId = 'Ucreator00001';
  const actorId = 'Uactor0000001';
  const beaconAuthorId = 'Uauthor000001';
  const beaconId = 'Bbbbbbbbbbbbb';
  const resolutionId = 'Riiiiiiiiiiii';
  const targetItemId = 'Tiiiiiiiiiiii';

  group('CreateResolutionCase', () {
    late _StubBeacons beacons;
    late _StubItems items;
    late TestAttentionHarness attention;
    late CreateResolutionCase sut;

    setUp(() {
      beacons = _StubBeacons(_openBeacon(beaconId));
      items = _StubItems();
      attention = TestAttentionHarness(
        context: BeaconNotificationContext(beaconAuthorId: beaconAuthorId),
      );
      sut = CreateResolutionCase(
        beacons,
        items,
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('creates resolution with trimmed title and body', () async {
      final out = await sut.call(
        userId: creatorId,
        beaconId: beaconId,
        title: '  Close blocker  ',
        body: '  details  ',
        targetItemId: targetItemId,
      );
      expect(out.kind, coordinationItemKindResolution);
      expect(items.lastCreateKind, coordinationItemKindResolution);
      expect(items.lastCreateTitle, 'Close blocker');
      expect(items.lastCreateBody, 'details');
      expect(items.lastTargetItemId, targetItemId);
    });

    test('rejects empty title', () async {
      await expectLater(
        () => sut.call(
          userId: creatorId,
          beaconId: beaconId,
          title: '  ',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastCreateKind, isNull);
    });

    test('rejects inactive beacon', () async {
      beacons.entity = _openBeacon(beaconId).copyWith(status: BeaconStatus.cancelled);
      await expectLater(
        () => sut.call(
          userId: creatorId,
          beaconId: beaconId,
          title: 'Resolve',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastCreateKind, isNull);
    });

    test('records needsMe for target item owner', () async {
      items.itemsById[targetItemId] = testCoordinationItem(
        id: targetItemId,
        beaconId: beaconId,
        kind: coordinationItemKindBlocker,
        status: coordinationItemStatusOpen,
        title: 'Blocker',
        creatorId: actorId,
        published: true,
        source: coordinationItemSourceDefault,
        createdAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024),
      );
      final createdAt = DateTime.utc(2024, 7, 1, 12, 0, 0, 123, 456);
      items.nextReturnOnCreate = testCoordinationItem(
        id: resolutionId,
        beaconId: beaconId,
        kind: coordinationItemKindResolution,
        status: coordinationItemStatusOpen,
        title: 'Close blocker',
        body: '',
        creatorId: creatorId,
        published: true,
        source: coordinationItemSourceDefault,
        createdAt: createdAt,
        updatedAt: createdAt,
      ).copyWith(targetItemId: targetItemId);

      await sut.call(
        userId: creatorId,
        beaconId: beaconId,
        title: 'Close blocker',
        targetItemId: targetItemId,
      );

      expect(attention.recorded, hasLength(1));
      final intent = attention.recorded.single;
      expect(intent.eventType, AttentionEventType.needsMe);
      expect(intent.kind, NotificationKind.needsMe);
      expect(
        intent.sourceEventKey,
        'coordination_item:$resolutionId:resolution_created:'
        '${createdAt.microsecondsSinceEpoch}',
      );
      expect(
        intent.recipients.map((recipient) => recipient.recipientId),
        contains(actorId),
      );
    });
  });

  group('AcceptResolutionCase', () {
    late _StubItems items;
    late TestAttentionHarness attention;
    late AcceptResolutionCase sut;

    setUp(() {
      items = _StubItems();
      attention = TestAttentionHarness(
        context: BeaconNotificationContext(beaconAuthorId: beaconAuthorId),
      );
      sut = AcceptResolutionCase(
        items,
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('resolves open resolution', () async {
      items.itemsById[resolutionId] = _sampleResolution(
        id: resolutionId,
        beaconId: beaconId,
        creatorId: creatorId,
      );
      final out = await sut.call(userId: actorId, itemId: resolutionId);
      expect(out.status, coordinationItemStatusResolved);
      expect(items.statusUpdates, hasLength(1));
      expect(items.statusUpdates.single.id, resolutionId);
      expect(items.statusUpdates.single.newStatus, coordinationItemStatusResolved);
      expect(items.statusUpdates.single.actorId, actorId);
    });

    test('resolves linked target when open or accepted', () async {
      items.itemsById[resolutionId] = _sampleResolution(
        id: resolutionId,
        beaconId: beaconId,
        creatorId: creatorId,
        targetItemId: targetItemId,
      );
      items.itemsById[targetItemId] = testCoordinationItem(
        id: targetItemId,
        beaconId: beaconId,
        kind: coordinationItemKindBlocker,
        status: coordinationItemStatusOpen,
        title: 'Blocker',
        creatorId: creatorId,
        published: true,
        source: coordinationItemSourceDefault,
        createdAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024),
      );
      await sut.call(userId: actorId, itemId: resolutionId);
      expect(items.statusUpdates, hasLength(2));
      expect(items.statusUpdates[0].id, targetItemId);
      expect(items.statusUpdates[0].newStatus, coordinationItemStatusResolved);
      expect(items.statusUpdates[1].id, resolutionId);
      expect(items.statusUpdates[1].newStatus, coordinationItemStatusResolved);
    });

    test('skips target update when target already resolved', () async {
      items.itemsById[resolutionId] = _sampleResolution(
        id: resolutionId,
        beaconId: beaconId,
        creatorId: creatorId,
        targetItemId: targetItemId,
      );
      items.itemsById[targetItemId] = testCoordinationItem(
        id: targetItemId,
        beaconId: beaconId,
        kind: coordinationItemKindBlocker,
        status: coordinationItemStatusResolved,
        title: 'Blocker',
        creatorId: creatorId,
        published: true,
        source: coordinationItemSourceDefault,
        createdAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024),
      );
      await sut.call(userId: actorId, itemId: resolutionId);
      expect(items.statusUpdates, hasLength(1));
      expect(items.statusUpdates.single.id, resolutionId);
    });

    test('rejects missing resolution', () async {
      await expectLater(
        () => sut.call(userId: actorId, itemId: resolutionId),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.statusUpdates, isEmpty);
    });

    test('rejects wrong kind', () async {
      items.itemsById[resolutionId] = _sampleResolution(
        id: resolutionId,
        beaconId: beaconId,
        creatorId: creatorId,
      ).copyWith(kind: coordinationItemKindAsk);
      await expectLater(
        () => sut.call(userId: actorId, itemId: resolutionId),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.statusUpdates, isEmpty);
    });

    test('rejects non-open resolution', () async {
      items.itemsById[resolutionId] = _sampleResolution(
        id: resolutionId,
        beaconId: beaconId,
        creatorId: creatorId,
        status: coordinationItemStatusResolved,
      );
      await expectLater(
        () => sut.call(userId: actorId, itemId: resolutionId),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.statusUpdates, isEmpty);
    });

    test('records commitmentResolved for resolution creator', () async {
      items.itemsById[resolutionId] = _sampleResolution(
        id: resolutionId,
        beaconId: beaconId,
        creatorId: creatorId,
        targetItemId: targetItemId,
      );
      items.itemsById[targetItemId] = testCoordinationItem(
        id: targetItemId,
        beaconId: beaconId,
        kind: coordinationItemKindBlocker,
        status: coordinationItemStatusOpen,
        title: 'Blocker',
        creatorId: actorId,
        published: true,
        source: coordinationItemSourceDefault,
        createdAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024),
      );
      final acceptedAt = DateTime.utc(2024, 8, 1, 12, 0, 0, 123, 456);
      items.nextUpdatedAt = acceptedAt;

      await sut.call(userId: actorId, itemId: resolutionId);

      expect(attention.recorded, hasLength(1));
      final intent = attention.recorded.single;
      expect(intent.eventType, AttentionEventType.commitmentResolved);
      expect(intent.kind, NotificationKind.commitmentResolved);
      expect(
        intent.sourceEventKey,
        'coordination_item:$resolutionId:resolution_accepted:'
        '${acceptedAt.microsecondsSinceEpoch}',
      );
      expect(intent.recipients, isNotEmpty);
      expect(
        intent.recipients.map((recipient) => recipient.recipientId),
        contains(creatorId),
      );
    });

    test('rolls back both status writes when second update fails', () async {
      final failingItems = _FailingOnSecondUpdateItems();
      failingItems.itemsById[resolutionId] = _sampleResolution(
        id: resolutionId,
        beaconId: beaconId,
        creatorId: creatorId,
        targetItemId: targetItemId,
      );
      failingItems.itemsById[targetItemId] = testCoordinationItem(
        id: targetItemId,
        beaconId: beaconId,
        kind: coordinationItemKindBlocker,
        status: coordinationItemStatusOpen,
        title: 'Blocker',
        creatorId: actorId,
        published: true,
        source: coordinationItemSourceDefault,
        createdAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024),
      );
      final dispatch = _RecordingDispatch();
      final transactional = TransactionalAttentionCase(
        _SnapshotUnitOfWork(failingItems),
        dispatch,
      );
      final rollbackSut = AcceptResolutionCase(
        failingItems,
        attentionIntents: attention.intents,
        attention: transactional,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );

      await expectLater(
        () => rollbackSut.call(userId: actorId, itemId: resolutionId),
        throwsStateError,
      );
      expect(
        failingItems.itemsById[targetItemId]!.status,
        coordinationItemStatusOpen,
      );
      expect(
        failingItems.itemsById[resolutionId]!.status,
        coordinationItemStatusOpen,
      );
      expect(dispatch.recorded, isEmpty);
    });
  });

  group('RejectResolutionCase', () {
    late _StubItems items;
    late TestAttentionHarness attention;
    late RejectResolutionCase sut;

    setUp(() {
      items = _StubItems();
      attention = TestAttentionHarness(
        context: BeaconNotificationContext(beaconAuthorId: beaconAuthorId),
      );
      sut = RejectResolutionCase(
        items,
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('cancels open resolution', () async {
      items.itemsById[resolutionId] = _sampleResolution(
        id: resolutionId,
        beaconId: beaconId,
        creatorId: creatorId,
      );
      final out = await sut.call(userId: actorId, itemId: resolutionId);
      expect(out.status, coordinationItemStatusCancelled);
      expect(items.statusUpdates, hasLength(1));
      expect(items.statusUpdates.single.id, resolutionId);
      expect(items.statusUpdates.single.newStatus, coordinationItemStatusCancelled);
      expect(items.statusUpdates.single.actorId, actorId);
    });

    test('records commitmentCancelled for resolution creator', () async {
      items.itemsById[resolutionId] = _sampleResolution(
        id: resolutionId,
        beaconId: beaconId,
        creatorId: creatorId,
      );
      final rejectedAt = DateTime.utc(2024, 8, 2, 12, 0, 0, 123, 456);
      items.nextUpdatedAt = rejectedAt;

      await sut.call(userId: actorId, itemId: resolutionId);

      expect(attention.recorded, hasLength(1));
      final intent = attention.recorded.single;
      expect(intent.eventType, AttentionEventType.commitmentCancelled);
      expect(intent.kind, NotificationKind.commitmentCancelled);
      expect(
        intent.sourceEventKey,
        'coordination_item:$resolutionId:resolution_rejected:'
        '${rejectedAt.microsecondsSinceEpoch}',
      );
      expect(intent.recipients, isNotEmpty);
      expect(
        intent.recipients.map((recipient) => recipient.recipientId),
        contains(creatorId),
      );
    });

    test('rejects missing resolution', () async {
      await expectLater(
        () => sut.call(userId: actorId, itemId: resolutionId),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.statusUpdates, isEmpty);
    });

    test('rejects wrong kind', () async {
      items.itemsById[resolutionId] = _sampleResolution(
        id: resolutionId,
        beaconId: beaconId,
        creatorId: creatorId,
      ).copyWith(kind: coordinationItemKindPromise);
      await expectLater(
        () => sut.call(userId: actorId, itemId: resolutionId),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.statusUpdates, isEmpty);
    });

    test('rejects non-open resolution', () async {
      items.itemsById[resolutionId] = _sampleResolution(
        id: resolutionId,
        beaconId: beaconId,
        creatorId: creatorId,
        status: coordinationItemStatusCancelled,
      );
      await expectLater(
        () => sut.call(userId: actorId, itemId: resolutionId),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.statusUpdates, isEmpty);
    });
  });
}
