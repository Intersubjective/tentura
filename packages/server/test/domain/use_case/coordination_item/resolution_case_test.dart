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
import 'package:tentura_server/domain/use_case/coordination_item/accept_resolution_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/create_resolution_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/reject_resolution_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/coordination_item_record_fixtures.dart';

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
    final updated = existing.copyWith(status: newStatus);
    itemsById[id] = updated;
    return updated;
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

void main() {
  const creatorId = 'Ucreator00001';
  const actorId = 'Uactor0000001';
  const beaconId = 'Bbbbbbbbbbbbb';
  const resolutionId = 'Riiiiiiiiiiii';
  const targetItemId = 'Tiiiiiiiiiiii';

  group('CreateResolutionCase', () {
    late _StubBeacons beacons;
    late _StubItems items;
    late CreateResolutionCase sut;

    setUp(() {
      beacons = _StubBeacons(_openBeacon(beaconId));
      items = _StubItems();
      sut = CreateResolutionCase(
        beacons,
        items,
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
  });

  group('AcceptResolutionCase', () {
    late _StubItems items;
    late AcceptResolutionCase sut;

    setUp(() {
      items = _StubItems();
      sut = AcceptResolutionCase(
        items,
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
  });

  group('RejectResolutionCase', () {
    late _StubItems items;
    late RejectResolutionCase sut;

    setUp(() {
      items = _StubItems();
      sut = RejectResolutionCase(
        items,
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
