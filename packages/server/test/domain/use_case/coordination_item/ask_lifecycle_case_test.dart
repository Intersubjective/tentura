import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/accept_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/cancel_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/create_draft_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/delete_draft_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/mark_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/publish_draft_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/redirect_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/resolve_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/update_draft_ask_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/coordination_item_record_fixtures.dart';
import '../../../support/noop_beacon_room_notification_port.dart';
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

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  CoordinationItemRecord? item;
  CoordinationItemRecord? nextReturn;
  String? lastCreateBeaconId;
  String? lastPublishId;
  String? lastPublishTarget;
  int? lastStatusUpdate;
  String? lastMarkTarget;
  String? lastUpdateDraftTitle;
  String? lastDeleteDraftId;
  String? lastAcceptedById;
  String? lastRedirectTarget;

  @override
  Future<CoordinationItemRecord?> getById(String id) async => item;

  @override
  Future<CoordinationItemRecord> createDraftAsk({
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
    lastPublishTarget = targetPersonId;
    return nextReturn ??
        item!.copyWith(published: true, targetPersonId: targetPersonId);
  }

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
    lastMarkTarget = targetPersonId;
    final now = DateTime.utc(2024);
    return nextReturn ??
        testCoordinationItem(
          id: item?.id ?? 'Iiiiiiiiiiiii',
          beaconId: beaconId,
          kind: kind,
          status: coordinationItemStatusOpen,
          title: title,
          body: body,
          creatorId: creatorId,
          targetPersonId: targetPersonId,
          published: true,
          source: coordinationItemSourceDefault,
          createdAt: now,
          updatedAt: now,
          ordering: ordering,
        );
  }

  @override
  Future<CoordinationItemRecord> updateStatus({
    required String id,
    required int newStatus,
    required String actorId,
  }) async {
    lastStatusUpdate = newStatus;
    return nextReturn ?? item!.copyWith(status: newStatus);
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
    lastUpdateDraftTitle = title;
    return (nextReturn ?? item!).copyWith(title: title, body: body);
  }

  @override
  Future<void> deleteDraftAsk({
    required String id,
    required String actorId,
  }) async {
    lastDeleteDraftId = id;
  }

  @override
  Future<CoordinationItemRecord> acceptItem({
    required String id,
    required String actorId,
    required String acceptedById,
  }) async {
    lastAcceptedById = acceptedById;
    return (nextReturn ?? item!).copyWith(
      status: coordinationItemStatusAccepted,
      acceptedById: acceptedById,
    );
  }

  @override
  Future<CoordinationItemRecord> redirectTarget({
    required String id,
    required String actorId,
    required String newTargetPersonId,
  }) async {
    lastRedirectTarget = newTargetPersonId;
    return (nextReturn ?? item!).copyWith(targetPersonId: newTargetPersonId);
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
  }) async => userId == authorId;

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async => false;

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

CoordinationItemRecord _draftAsk({
  required String id,
  required String beaconId,
  required String creatorId,
  String? targetPersonId,
}) {
  final now = DateTime.utc(2024);
  return testCoordinationItem(
    id: id,
    beaconId: beaconId,
    kind: coordinationItemKindAsk,
    status: coordinationItemStatusOpen,
    title: 'Need help',
    body: 'Please assist',
    creatorId: creatorId,
    targetPersonId: targetPersonId,
    published: false,
    source: coordinationItemSourceDefault,
    createdAt: now,
    updatedAt: now,
    ordering: 0,
  );
}

CoordinationItemRecord _publishedAsk({
  required String id,
  required String beaconId,
  required String creatorId,
  String? targetPersonId,
  int status = coordinationItemStatusOpen,
}) {
  final now = DateTime.utc(2024);
  return testCoordinationItem(
    id: id,
    beaconId: beaconId,
    kind: coordinationItemKindAsk,
    status: status,
    title: 'Need help',
    body: 'Please assist',
    creatorId: creatorId,
    targetPersonId: targetPersonId,
    published: true,
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
  const itemId = 'Iiiiiiiiiiiii';

  group('CreateDraftAskCase', () {
    late _StubBeacons beacons;
    late _StubItems items;
    late CreateDraftAskCase sut;

    setUp(() {
      beacons = _StubBeacons(_openBeacon(beaconId));
      items = _StubItems();
      items.nextReturn = _draftAsk(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
      );
      sut = CreateDraftAskCase(
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
        title: 'Need help',
        body: 'Details here',
      );
      expect(out.id, itemId);
      expect(items.lastCreateBeaconId, beaconId);
    });

    test('admitted non-owner can create draft', () async {
      items.nextReturn = _draftAsk(
        id: itemId,
        beaconId: beaconId,
        creatorId: otherId,
      );
      final out = await sut.call(
        userId: otherId,
        beaconId: beaconId,
        title: 'Need help',
        body: 'Details here',
      );
      expect(out.creatorId, otherId);
    });

    test('non-participant rejected', () async {
      final noAccess = CreateDraftAskCase(
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
          body: 'y',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('empty body rejected', () async {
      expect(
        () => sut.call(
          userId: ownerId,
          beaconId: beaconId,
          title: 'Need help',
          body: '  ',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('inactive beacon rejected', () async {
      beacons.entity = _openBeacon(
        beaconId,
      ).copyWith(status: BeaconStatus.cancelled);
      expect(
        () => sut.call(
          userId: ownerId,
          beaconId: beaconId,
          title: 'Need help',
          body: 'Details',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('self-target rejected when target provided', () async {
      await expectLater(
        () => sut.call(
          userId: ownerId,
          beaconId: beaconId,
          title: 'Need help',
          body: 'Details',
          targetPersonId: ownerId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastCreateBeaconId, null);
    });

    test('draft without target still allowed', () async {
      final out = await sut.call(
        userId: ownerId,
        beaconId: beaconId,
        title: 'Need help',
        body: 'Details',
      );
      expect(out.id, itemId);
      expect(items.lastCreateBeaconId, beaconId);
    });
  });

  group('PublishDraftAskCase', () {
    late _StubBeacons beacons;
    late _StubItems items;
    late PublishDraftAskCase sut;

    setUp(() {
      beacons = _StubBeacons(_openBeacon(beaconId));
      items = _StubItems();
      items.item = _draftAsk(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
      );
      items.nextReturn = items.item!.copyWith(
        published: true,
        targetPersonId: targetId,
      );
      final attention = TestAttentionHarness();
      sut = PublishDraftAskCase(
        beacons,
        items,
        _NoopRoomPush(),
        attentionIntents: attention.intents,
        attention: attention.transactional,
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
      expect(items.lastPublishId, itemId);
      expect(items.lastPublishTarget, targetId);
    });

    test('wrong kind rejected', () async {
      items.item = items.item!.copyWith(kind: coordinationItemKindBlocker);
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

    test('inactive beacon rejected', () async {
      beacons.entity = _openBeacon(
        beaconId,
      ).copyWith(status: BeaconStatus.cancelled);
      expect(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          targetPersonId: targetId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('rejects self-target', () async {
      await expectLater(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          targetPersonId: ownerId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastPublishId, null);
    });
  });

  group('MarkAskCase', () {
    late _StubBeacons beacons;
    late _StubItems items;
    late MarkAskCase sut;

    setUp(() {
      beacons = _StubBeacons(_openBeacon(beaconId));
      items = _StubItems();
      items.item = _publishedAsk(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
        targetPersonId: targetId,
      );
      final attention = TestAttentionHarness();
      sut = MarkAskCase(
        beacons,
        items,
        _NoopRoomPush(),
        attentionIntents: attention.intents,
        attention: attention.transactional,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('creates published ask with target', () async {
      final out = await sut.call(
        userId: ownerId,
        beaconId: beaconId,
        title: 'Need help',
        targetPersonId: targetId,
        body: 'Details',
      );
      expect(out.id, itemId);
      expect(items.lastMarkTarget, targetId);
    });

    test('empty title rejected', () async {
      expect(
        () => sut.call(
          userId: ownerId,
          beaconId: beaconId,
          title: '  ',
          targetPersonId: targetId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('empty target rejected', () async {
      expect(
        () => sut.call(
          userId: ownerId,
          beaconId: beaconId,
          title: 'Need help',
          targetPersonId: '  ',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('inactive beacon rejected', () async {
      beacons.entity = _openBeacon(
        beaconId,
      ).copyWith(status: BeaconStatus.cancelled);
      expect(
        () => sut.call(
          userId: ownerId,
          beaconId: beaconId,
          title: 'Need help',
          targetPersonId: targetId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('rejects self-target', () async {
      await expectLater(
        () => sut.call(
          userId: ownerId,
          beaconId: beaconId,
          title: 'Need help',
          targetPersonId: ownerId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastMarkTarget, null);
    });
  });

  group('ResolveAskCase', () {
    late _StubItems items;
    late ResolveAskCase sut;

    setUp(() {
      items = _StubItems();
      items.item = _publishedAsk(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
        targetPersonId: targetId,
      );
      items.nextReturn = items.item!.copyWith(
        status: coordinationItemStatusResolved,
      );
      sut = ResolveAskCase(
        items,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('resolves open ask', () async {
      await sut.call(userId: ownerId, itemId: itemId);
      expect(items.lastStatusUpdate, coordinationItemStatusResolved);
    });

    test('resolves accepted ask', () async {
      items.item = items.item!.copyWith(status: coordinationItemStatusAccepted);
      await sut.call(userId: targetId, itemId: itemId);
      expect(items.lastStatusUpdate, coordinationItemStatusResolved);
    });

    test('not found rejected', () async {
      items.item = null;
      expect(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<IdNotFoundException>()),
      );
    });

    test('wrong kind rejected', () async {
      items.item = items.item!.copyWith(kind: coordinationItemKindPromise);
      expect(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('already cancelled rejected', () async {
      items.item = items.item!.copyWith(
        status: coordinationItemStatusCancelled,
      );
      expect(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('already resolved rejected', () async {
      items.item = items.item!.copyWith(status: coordinationItemStatusResolved);
      expect(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
    });
  });

  group('CancelAskCase', () {
    late _StubItems items;
    late CancelAskCase sut;

    setUp(() {
      items = _StubItems();
      items.item = _publishedAsk(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
        targetPersonId: targetId,
      );
      items.nextReturn = items.item!.copyWith(
        status: coordinationItemStatusCancelled,
      );
      sut = CancelAskCase(
        items,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('cancels open ask', () async {
      await sut.call(userId: ownerId, itemId: itemId);
      expect(items.lastStatusUpdate, coordinationItemStatusCancelled);
    });

    test('cancels accepted ask', () async {
      items.item = items.item!.copyWith(status: coordinationItemStatusAccepted);
      await sut.call(userId: targetId, itemId: itemId);
      expect(items.lastStatusUpdate, coordinationItemStatusCancelled);
    });

    test('not found rejected', () async {
      items.item = null;
      expect(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<IdNotFoundException>()),
      );
    });

    test('wrong kind rejected', () async {
      items.item = items.item!.copyWith(kind: coordinationItemKindBlocker);
      expect(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('already resolved rejected', () async {
      items.item = items.item!.copyWith(status: coordinationItemStatusResolved);
      expect(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
    });

    test('already cancelled rejected', () async {
      items.item = items.item!.copyWith(
        status: coordinationItemStatusCancelled,
      );
      expect(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
    });
  });

  group('UpdateDraftAskCase', () {
    late _StubBeacons beacons;
    late _StubItems items;
    late UpdateDraftAskCase sut;

    setUp(() {
      beacons = _StubBeacons(_openBeacon(beaconId));
      items = _StubItems();
      items.item = _draftAsk(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
      );
      items.nextReturn = items.item!.copyWith(title: 'Updated');
      sut = UpdateDraftAskCase(
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
        body: 'New details',
      );
      expect(out.title, 'Updated');
      expect(items.lastUpdateDraftTitle, 'Updated');
    });

    test('empty body rejected', () async {
      await expectLater(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          title: 'Updated',
          body: '  ',
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
          body: 'details',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastUpdateDraftTitle, null);
    });

    test('wrong kind rejected', () async {
      items.item = items.item!.copyWith(kind: coordinationItemKindBlocker);
      await expectLater(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          title: 'Updated',
          body: 'details',
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
          body: 'details',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastUpdateDraftTitle, null);
    });

    test('inactive beacon rejected', () async {
      beacons.entity = _openBeacon(
        beaconId,
      ).copyWith(status: BeaconStatus.cancelled);
      await expectLater(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          title: 'Updated',
          body: 'details',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastUpdateDraftTitle, null);
    });

    test('rejects self-target when updating target', () async {
      await expectLater(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          title: 'Updated',
          body: 'details',
          updateTargetPersonId: true,
          targetPersonId: ownerId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastUpdateDraftTitle, null);
    });
  });

  group('DeleteDraftAskCase', () {
    late _StubBeacons beacons;
    late _StubItems items;
    late DeleteDraftAskCase sut;

    setUp(() {
      beacons = _StubBeacons(_openBeacon(beaconId));
      items = _StubItems();
      items.item = _draftAsk(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
      );
      sut = DeleteDraftAskCase(
        beacons,
        items,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('creator can delete draft', () async {
      final ok = await sut.call(userId: ownerId, itemId: itemId);
      expect(ok, isTrue);
      expect(items.lastDeleteDraftId, itemId);
    });

    test('not found rejected', () async {
      items.item = null;
      await expectLater(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastDeleteDraftId, null);
    });

    test('non-creator rejected', () async {
      await expectLater(
        () => sut.call(userId: otherId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastDeleteDraftId, null);
    });

    test('inactive beacon rejected', () async {
      beacons.entity = _openBeacon(
        beaconId,
      ).copyWith(status: BeaconStatus.cancelled);
      await expectLater(
        () => sut.call(userId: ownerId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastDeleteDraftId, null);
    });
  });

  group('AcceptAskCase', () {
    late _StubItems items;
    late AcceptAskCase sut;

    setUp(() {
      items = _StubItems();
      items.item = _publishedAsk(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
        targetPersonId: targetId,
      );
      items.nextReturn = items.item!.copyWith(
        status: coordinationItemStatusAccepted,
      );
      sut = AcceptAskCase(
        items,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('accepts open ask', () async {
      final out = await sut.call(userId: targetId, itemId: itemId);
      expect(out.status, coordinationItemStatusAccepted);
      expect(items.lastAcceptedById, targetId);
    });

    test('not found rejected', () async {
      items.item = null;
      await expectLater(
        () => sut.call(userId: targetId, itemId: itemId),
        throwsA(isA<IdNotFoundException>()),
      );
      expect(items.lastAcceptedById, null);
    });

    test('wrong kind rejected', () async {
      items.item = items.item!.copyWith(kind: coordinationItemKindPromise);
      await expectLater(
        () => sut.call(userId: targetId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastAcceptedById, null);
    });

    test('non-open status rejected', () async {
      items.item = items.item!.copyWith(status: coordinationItemStatusAccepted);
      await expectLater(
        () => sut.call(userId: targetId, itemId: itemId),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastAcceptedById, null);
    });
  });

  group('RedirectAskCase', () {
    late _StubItems items;
    late RedirectAskCase sut;

    const newTargetId = 'Unewtarget001';

    setUp(() {
      items = _StubItems();
      items.item = _publishedAsk(
        id: itemId,
        beaconId: beaconId,
        creatorId: ownerId,
        targetPersonId: targetId,
      );
      items.nextReturn = items.item!.copyWith(targetPersonId: newTargetId);
      sut = RedirectAskCase(
        items,
        env: Env(environment: Environment.test),
        logger: Logger('_'),
      );
    });

    test('redirects open ask', () async {
      final out = await sut.call(
        userId: ownerId,
        itemId: itemId,
        newTargetPersonId: newTargetId,
      );
      expect(out.targetPersonId, newTargetId);
      expect(items.lastRedirectTarget, newTargetId);
    });

    test('not found rejected', () async {
      items.item = null;
      await expectLater(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          newTargetPersonId: newTargetId,
        ),
        throwsA(isA<IdNotFoundException>()),
      );
      expect(items.lastRedirectTarget, null);
    });

    test('wrong kind rejected', () async {
      items.item = items.item!.copyWith(kind: coordinationItemKindBlocker);
      await expectLater(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          newTargetPersonId: newTargetId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastRedirectTarget, null);
    });

    test('non-open status rejected', () async {
      items.item = items.item!.copyWith(status: coordinationItemStatusResolved);
      await expectLater(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          newTargetPersonId: newTargetId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastRedirectTarget, null);
    });

    test('empty target rejected', () async {
      await expectLater(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          newTargetPersonId: '  ',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastRedirectTarget, null);
    });

    test('rejects self-target', () async {
      await expectLater(
        () => sut.call(
          userId: ownerId,
          itemId: itemId,
          newTargetPersonId: ownerId,
        ),
        throwsA(isA<BeaconCreateException>()),
      );
      expect(items.lastRedirectTarget, null);
    });
  });
}

class _NoopRoomPush extends NoopBeaconRoomNotificationPort {}
