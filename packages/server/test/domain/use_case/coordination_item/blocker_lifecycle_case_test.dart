import 'package:drift_postgres/drift_postgres.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/cancel_blocker_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/mark_blocker_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/resolve_blocker_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/update_draft_blocker_case.dart';
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

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  CoordinationItemRecord? item;
  CoordinationItemRecord? nextReturn;
  int? lastCreateKind;
  String? lastCreateTitle;
  int? lastUpdateStatus;
  String? lastUpdateDraftTitle;

  @override
  Future<CoordinationItemRecord?> getById(String id) async => item;

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
    return nextReturn ?? item!;
  }

  @override
  Future<CoordinationItemRecord> updateStatus({
    required String id,
    required int newStatus,
    required String actorId,
  }) async {
    lastUpdateStatus = newStatus;
    return (nextReturn ?? item!).copyWith(status: newStatus);
  }

  @override
  Future<CoordinationItemRecord> updateDraftBlocker({
    required String id,
    required String actorId,
    required String title,
    String body = '',
    bool updateTargetPersonId = false,
    String? targetPersonId,
    bool updateStaleAfterDays = false,
    int? staleAfterDays,
  }) async {
    lastUpdateDraftTitle = title;
    return (nextReturn ?? item!).copyWith(title: title, body: body);
  }
}

class _RecordingPush extends Fake implements BeaconRoomNotificationPort {
  int blockerOpenedCalls = 0;
  int blockerResolvedCalls = 0;

  @override
  Future<void> notifyBlockerOpened({
    required String beaconId,
    required String actorUserId,
    required String excerpt,
    String? targetPersonId,
    String? coordinationItemId,
  }) async {
    blockerOpenedCalls++;
  }

  @override
  Future<void> notifyBlockerResolved({
    required String beaconId,
    required String actorUserId,
    required String excerpt,
    String? targetPersonId,
    String? coordinationItemId,
  }) async {
    blockerResolvedCalls++;
  }
}

BeaconEntity _openBeacon(String id, {String authorId = 'Uowner0000001'}) =>
    BeaconEntity(
      id: id,
      title: 'Beacon',
      author: UserEntity(id: authorId),
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );

CoordinationItemRecord _publishedBlocker({
  required String id,
  required String beaconId,
  required String creatorId,
  int status = coordinationItemStatusOpen,
}) {
  final now = DateTime.utc(2024);
  return testCoordinationItem(
    id: id,
    beaconId: beaconId,
    kind: coordinationItemKindBlocker,
    status: status,
    title: 'Blocked',
    body: '',
    creatorId: creatorId,
    published: true,
    source: coordinationItemSourceDefault,
    createdAt: now,
    updatedAt: now,
    ordering: 0,
  );
}

CoordinationItemRecord _draftBlocker({
  required String id,
  required String beaconId,
  required String creatorId,
}) {
  final now = DateTime.utc(2024);
  return testCoordinationItem(
    id: id,
    beaconId: beaconId,
    kind: coordinationItemKindBlocker,
    status: coordinationItemStatusOpen,
    title: 'Blocked',
    body: '',
    creatorId: creatorId,
    published: false,
    source: coordinationItemSourceDefault,
    createdAt: now,
    updatedAt: now,
    ordering: 0,
  );
}

void main() {
  const ownerId = 'Uowner0000001';
  const otherId = 'Uother0000001';
  const beaconId = 'Bbbbbbbbbbbbb';
  const itemId = 'Iiiiiiiiiiiii';

  group('MarkBlockerCase', () {
    late _StubBeacons beacons;
    late _StubItems items;
    late _RecordingPush push;
    late MarkBlockerCase sut;

    setUp(() {
      beacons = _StubBeacons(_openBeacon(beaconId));
      items = _StubItems();
      items.nextReturn = _publishedBlocker(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
      );
      push = _RecordingPush();
      sut = MarkBlockerCase(
        beacons,
        items,
        push,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('marks blocker on open beacon', () async {
      final out = await sut.call(
        userId: ownerId,
        beaconId: beaconId,
        title: 'Need parts',
      );
      expect(out.id, itemId);
      expect(items.lastCreateKind, coordinationItemKindBlocker);
      expect(items.lastCreateTitle, 'Need parts');
      expect(push.blockerOpenedCalls, 1);
    });

    test('empty title rejected', () async {
      await expectLater(
        () => sut.call(
          userId: ownerId,
          beaconId: beaconId,
          title: '  ',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastCreateKind, null);
    });

    test('inactive beacon rejected', () async {
      beacons.entity =
          _openBeacon(beaconId).copyWith(status: BeaconStatus.cancelled);
      await expectLater(
        () => sut.call(
          userId: ownerId,
          beaconId: beaconId,
          title: 'Need parts',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastCreateKind, null);
    });
  });

  group('ResolveBlockerCase', () {
    late _StubItems items;
    late _RecordingPush push;
    late ResolveBlockerCase sut;

    setUp(() {
      items = _StubItems();
      items.item = _publishedBlocker(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
      );
      items.nextReturn = items.item!.copyWith(
        status: coordinationItemStatusResolved,
      );
      push = _RecordingPush();
      sut = ResolveBlockerCase(
        items,
        push,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('resolves open blocker', () async {
      final out = await sut.call(userId: ownerId, itemId: itemId);
      expect(out.status, coordinationItemStatusResolved);
      expect(items.lastUpdateStatus, coordinationItemStatusResolved);
      expect(push.blockerResolvedCalls, 1);
    });

    test('not found rejected', () async {
      items.item = null;
      await expectLater(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<IdNotFoundException>()),
      );
      expect(items.lastUpdateStatus, null);
    });

    test('wrong kind rejected', () async {
      items.item = items.item!.copyWith(kind: coordinationItemKindAsk);
      await expectLater(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastUpdateStatus, null);
    });

    test('non-open status rejected', () async {
      items.item = items.item!.copyWith(
        status: coordinationItemStatusResolved,
      );
      await expectLater(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastUpdateStatus, null);
    });
  });

  group('CancelBlockerCase', () {
    late _StubItems items;
    late CancelBlockerCase sut;

    setUp(() {
      items = _StubItems();
      items.item = _publishedBlocker(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
      );
      items.nextReturn = items.item!.copyWith(
        status: coordinationItemStatusCancelled,
      );
      sut = CancelBlockerCase(
        items,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('cancels open blocker', () async {
      final out = await sut.call(userId: ownerId, itemId: itemId);
      expect(out.status, coordinationItemStatusCancelled);
      expect(items.lastUpdateStatus, coordinationItemStatusCancelled);
    });

    test('not found rejected', () async {
      items.item = null;
      await expectLater(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<IdNotFoundException>()),
      );
      expect(items.lastUpdateStatus, null);
    });

    test('wrong kind rejected', () async {
      items.item = items.item!.copyWith(kind: coordinationItemKindAsk);
      await expectLater(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastUpdateStatus, null);
    });

    test('non-open status rejected', () async {
      items.item = items.item!.copyWith(
        status: coordinationItemStatusCancelled,
      );
      await expectLater(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastUpdateStatus, null);
    });
  });

  group('UpdateDraftBlockerCase', () {
    late _StubBeacons beacons;
    late _StubItems items;
    late UpdateDraftBlockerCase sut;

    setUp(() {
      beacons = _StubBeacons(_openBeacon(beaconId));
      items = _StubItems();
      items.item = _draftBlocker(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
      );
      items.nextReturn = items.item!.copyWith(title: 'Updated');
      sut = UpdateDraftBlockerCase(
        beacons,
        items,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('creator can update draft', () async {
      final out = await sut.call(
        userId: ownerId,
        itemId: itemId,
        title: 'Updated',
        body: 'details',
      );
      expect(out.title, 'Updated');
      expect(items.lastUpdateDraftTitle, 'Updated');
    });

    test('empty title rejected', () async {
      await expectLater(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          title: '  ',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastUpdateDraftTitle, null);
    });

    test('not found rejected', () async {
      items.item = null;
      await expectLater(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          title: 'Updated',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastUpdateDraftTitle, null);
    });

    test('wrong kind rejected', () async {
      items.item = items.item!.copyWith(kind: coordinationItemKindAsk);
      await expectLater(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          title: 'Updated',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastUpdateDraftTitle, null);
    });

    test('non-creator rejected', () async {
      await expectLater(
        () => sut.call(
          userId: otherId,
          itemId: itemId,
          title: 'Updated',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastUpdateDraftTitle, null);
    });

    test('inactive beacon rejected', () async {
      beacons.entity =
          _openBeacon(beaconId).copyWith(status: BeaconStatus.cancelled);
      await expectLater(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          title: 'Updated',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastUpdateDraftTitle, null);
    });
  });
}
