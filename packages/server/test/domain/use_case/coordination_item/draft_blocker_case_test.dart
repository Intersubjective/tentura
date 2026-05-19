import 'package:drift_postgres/drift_postgres.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/create_draft_blocker_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/delete_draft_blocker_case.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/port/beacon_notification_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/publish_draft_blocker_case.dart';
import 'package:tentura_server/env.dart';

import 'package:injectable/injectable.dart' show Environment;

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
  CoordinationItem? item;
  CoordinationItem? nextReturn;
  String? lastCreateBeaconId;
  String? lastPublishId;

  @override
  Future<CoordinationItem?> getById(String id) async => item;

  @override
  Future<CoordinationItem> createDraftBlocker({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
  }) async {
    lastCreateBeaconId = beaconId;
    return nextReturn ?? item!;
  }

  @override
  Future<CoordinationItem> publishDraftBlocker({
    required String id,
    required String actorId,
  }) async {
    lastPublishId = id;
    return nextReturn ?? item!;
  }

  @override
  Future<void> deleteDraftBlocker({
    required String id,
    required String actorId,
  }) async {}
}

class _StubRoom extends Fake implements BeaconRoomRepository {
  _StubRoom({required this.authorId, this.admittedUserIds = const {}});

  final String authorId;
  final Set<String> admittedUserIds;

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async =>
      userId == authorId;

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async =>
      false;

  @override
  Future<BeaconParticipant?> findParticipant({
    required String beaconId,
    required String userId,
  }) async {
    if (!admittedUserIds.contains(userId)) {
      return null;
    }
    final now = PgDateTime(DateTime.utc(2024));
    return BeaconParticipant(
      createdAt: now,
      updatedAt: now,
      id: 'Ptest',
      beaconId: beaconId,
      userId: userId,
      role: BeaconParticipantRoleBits.helper,
      status: 0,
      roomAccess: RoomAccessBits.admitted,
    );
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

CoordinationItem _draftBlocker({
  required String id,
  required String beaconId,
  required String creatorId,
}) {
  final now = PgDateTime(DateTime.utc(2024));
  return CoordinationItem(
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

  group('CreateDraftBlockerCase', () {
    late _StubBeacons beacons;
    late _StubItems items;
    late CreateDraftBlockerCase sut;

    setUp(() {
      beacons = _StubBeacons(_openBeacon(beaconId, authorId: ownerId));
      items = _StubItems();
      items.nextReturn = _draftBlocker(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
      );
      sut = CreateDraftBlockerCase(
        beacons,
        items,
        _StubRoom(authorId: ownerId, admittedUserIds: {otherId}),
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('owner can create draft', () async {
      final out = await sut.call(
        userId: ownerId,
        beaconId: beaconId,
        title: 'Need parts',
      );
      expect(out.id, itemId);
      expect(items.lastCreateBeaconId, beaconId);
    });

    test('admitted non-owner can create draft', () async {
      items.nextReturn = _draftBlocker(
        id: itemId,
        beaconId: beaconId,
        creatorId: otherId,
      );
      final out = await sut.call(
        userId: otherId,
        beaconId: beaconId,
        title: 'Need parts',
      );
      expect(out.creatorId, otherId);
    });

    test('non-participant rejected', () async {
      final noAccess = CreateDraftBlockerCase(
        beacons,
        items,
        _StubRoom(authorId: ownerId),
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
      expect(
        () => noAccess.call(
          userId: otherId,
          beaconId: beaconId,
          title: 'x',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('empty title rejected', () async {
      expect(
        () => sut.call(
          userId: ownerId,
          beaconId: beaconId,
          title: '  ',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });
  });

  group('PublishDraftBlockerCase', () {
    late _StubBeacons beacons;
    late _StubItems items;
    late PublishDraftBlockerCase sut;

    setUp(() {
      beacons = _StubBeacons(_openBeacon(beaconId, authorId: ownerId));
      items = _StubItems();
      items.item = _draftBlocker(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
      );
      items.nextReturn = items.item!.copyWith(published: true);
      sut = PublishDraftBlockerCase(
        beacons,
        items,
        _NoopRoomPush(),
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('creator can publish', () async {
      await sut.call(userId: ownerId, itemId: itemId);
      expect(items.lastPublishId, itemId);
    });

    test('wrong kind rejected', () async {
      items.item = items.item!.copyWith(kind: coordinationItemKindAsk);
      expect(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('non-creator rejected', () async {
      expect(
        () => sut.call(userId: otherId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
    });
  });

  group('DeleteDraftBlockerCase', () {
    late _StubBeacons beacons;
    late _StubItems items;
    late DeleteDraftBlockerCase sut;

    setUp(() {
      beacons = _StubBeacons(_openBeacon(beaconId, authorId: ownerId));
      items = _StubItems();
      items.item = _draftBlocker(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
      );
      sut = DeleteDraftBlockerCase(
        beacons,
        items,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('creator can delete', () async {
      final ok = await sut.call(userId: ownerId, itemId: itemId);
      expect(ok, isTrue);
    });
  });
}

class _NoopRoomPush extends BeaconRoomPushService {
  _NoopRoomPush() : super(_NoopNotificationPort());
}

class _NoopNotificationPort implements BeaconNotificationPort {
  @override
  Future<void> dispatch(BeaconNotificationIntent intent) async {}
}
