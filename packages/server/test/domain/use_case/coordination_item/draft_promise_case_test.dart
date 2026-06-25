import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/create_draft_promise_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/delete_draft_promise_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/publish_draft_promise_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/update_draft_promise_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/coordination_item_record_fixtures.dart';
import '../../../support/noop_beacon_room_notification_port.dart';

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
  String? lastCreateBeaconId;
  String? lastPublishId;
  String? lastUpdateId;
  String? lastDeleteId;

  @override
  Future<CoordinationItemRecord?> getById(String id) async => item;

  @override
  Future<CoordinationItemRecord> createDraftPromise({
    required String beaconId,
    required String creatorId,
    required String title,
    String body = '',
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  }) async {
    lastCreateBeaconId = beaconId;
    return nextReturn ?? item!;
  }

  @override
  Future<CoordinationItemRecord> publishDraft({
    required String id,
    required String actorId,
    required String targetPersonId,
    int? staleAfterDays,
  }) async {
    lastPublishId = id;
    return nextReturn ?? item!.copyWith(
      published: true,
      targetPersonId: targetPersonId,
    );
  }

  @override
  Future<CoordinationItemRecord> updateDraftAsk({
    required String id,
    required String actorId,
    required String title,
    String body = '',
    bool updateTargetPersonId = false,
    String? targetPersonId,
    bool updateStaleAfterDays = false,
    int? staleAfterDays,
  }) async {
    lastUpdateId = id;
    return nextReturn ??
        item!.copyWith(
          title: title,
          body: body,
          targetPersonId: updateTargetPersonId ? targetPersonId : item!.targetPersonId,
          staleAfterDays: updateStaleAfterDays ? staleAfterDays : item!.staleAfterDays,
        );
  }

  @override
  Future<void> deleteDraftAsk({
    required String id,
    required String actorId,
  }) async {
    lastDeleteId = id;
  }
}

class _StubRoom extends Fake implements BeaconRoomRepositoryPort {
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
  Future<BeaconParticipantRecord?> findParticipant({
    required String beaconId,
    required String userId,
  }) async {
    if (!admittedUserIds.contains(userId)) {
      return null;
    }
    return testBeaconParticipant(
      id: 'Ptest',
      beaconId: beaconId,
      userId: userId,
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

CoordinationItemRecord _draftPromise({
  required String id,
  required String beaconId,
  required String creatorId,
  String? targetPersonId,
}) {
  final now = DateTime.utc(2024);
  return testCoordinationItem(
    id: id,
    beaconId: beaconId,
    kind: coordinationItemKindPromise,
    status: coordinationItemStatusOpen,
    title: 'Draft promise',
    body: 'Details',
    creatorId: creatorId,
    targetPersonId: targetPersonId,
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
  const targetId = 'Utarget000001';
  const beaconId = 'Bbbbbbbbbbbbb';
  const itemId = 'Piiiiiiiiiiii';

  group('CreateDraftPromiseCase', () {
    late _StubBeacons beacons;
    late _StubItems items;
    late CreateDraftPromiseCase sut;

    setUp(() {
      beacons = _StubBeacons(_openBeacon(beaconId));
      items = _StubItems();
      items.nextReturn = _draftPromise(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
      );
      sut = CreateDraftPromiseCase(
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
        title: 'Will deliver',
        body: 'By Friday',
      );
      expect(out.id, itemId);
      expect(items.lastCreateBeaconId, beaconId);
    });

    test('admitted non-owner can create draft', () async {
      items.nextReturn = _draftPromise(
        id: itemId,
        beaconId: beaconId,
        creatorId: otherId,
      );
      final out = await sut.call(
        userId: otherId,
        beaconId: beaconId,
        title: 'Will deliver',
        body: 'By Friday',
      );
      expect(out.creatorId, otherId);
    });

    test('non-participant rejected', () async {
      final noAccess = CreateDraftPromiseCase(
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
          title: 'Will deliver',
          body: 'By Friday',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('empty body rejected', () async {
      expect(
        () => sut.call(
          userId: ownerId,
          beaconId: beaconId,
          title: 'Will deliver',
          body: '  ',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('self-target rejected', () async {
      expect(
        () => sut.call(
          userId: ownerId,
          beaconId: beaconId,
          title: 'Will deliver',
          body: 'By Friday',
          targetPersonId: ownerId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });
  });

  group('PublishDraftPromiseCase', () {
    late _StubBeacons beacons;
    late _StubItems items;
    late PublishDraftPromiseCase sut;

    setUp(() {
      beacons = _StubBeacons(_openBeacon(beaconId));
      items = _StubItems();
      items.item = _draftPromise(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
      );
      items.nextReturn = items.item!.copyWith(
        published: true,
        targetPersonId: targetId,
      );
      sut = PublishDraftPromiseCase(
        beacons,
        items,
        _NoopRoomPush(),
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('creator can publish with target', () async {
      final out = await sut.call(
        userId: ownerId,
        itemId: itemId,
        targetPersonId: targetId,
      );
      expect(out.published, isTrue);
      expect(out.targetPersonId, targetId);
      expect(items.lastPublishId, itemId);
    });

    test('empty target rejected', () async {
      expect(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          targetPersonId: '  ',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('wrong kind rejected', () async {
      items.item = items.item!.copyWith(kind: coordinationItemKindAsk);
      expect(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          targetPersonId: targetId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('already published rejected', () async {
      items.item = items.item!.copyWith(published: true);
      expect(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          targetPersonId: targetId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('non-creator rejected', () async {
      expect(
        () => sut.call(
          userId: otherId,
          itemId: itemId,
          targetPersonId: targetId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('self-target rejected', () async {
      expect(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          targetPersonId: ownerId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });
  });

  group('UpdateDraftPromiseCase', () {
    late _StubBeacons beacons;
    late _StubItems items;
    late UpdateDraftPromiseCase sut;

    setUp(() {
      beacons = _StubBeacons(_openBeacon(beaconId));
      items = _StubItems();
      items.item = _draftPromise(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
      );
      sut = UpdateDraftPromiseCase(
        beacons,
        items,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('creator can update title and body', () async {
      final out = await sut.call(
        userId: ownerId,
        itemId: itemId,
        title: 'Updated title',
        body: 'Updated body',
      );
      expect(out.title, 'Updated title');
      expect(out.body, 'Updated body');
      expect(items.lastUpdateId, itemId);
    });

    test('empty body rejected', () async {
      expect(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          title: 'Updated title',
          body: '  ',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('non-creator rejected', () async {
      expect(
        () => sut.call(
          userId: otherId,
          itemId: itemId,
          title: 'Updated title',
          body: 'Updated body',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('self-target rejected when updating target', () async {
      expect(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          title: 'Updated title',
          body: 'Updated body',
          updateTargetPersonId: true,
          targetPersonId: ownerId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });
  });

  group('DeleteDraftPromiseCase', () {
    late _StubBeacons beacons;
    late _StubItems items;
    late DeleteDraftPromiseCase sut;

    setUp(() {
      beacons = _StubBeacons(_openBeacon(beaconId));
      items = _StubItems();
      items.item = _draftPromise(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
      );
      sut = DeleteDraftPromiseCase(
        beacons,
        items,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('creator can delete', () async {
      final ok = await sut.call(userId: ownerId, itemId: itemId);
      expect(ok, isTrue);
      expect(items.lastDeleteId, itemId);
    });

    test('non-creator rejected', () async {
      expect(
        () => sut.call(userId: otherId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('wrong kind rejected', () async {
      items.item = items.item!.copyWith(kind: coordinationItemKindAsk);
      expect(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
    });
  });
}

class _NoopRoomPush extends NoopBeaconRoomNotificationPort {}
