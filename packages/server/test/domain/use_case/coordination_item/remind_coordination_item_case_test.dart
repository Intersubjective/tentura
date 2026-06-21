import 'package:drift_postgres/drift_postgres.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_notification_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/remind_coordination_item_case.dart';
import 'package:tentura_server/env.dart';

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  CoordinationItem? item;
  int claimAttempts = 0;
  bool claimSucceeds = true;

  @override
  Future<CoordinationItem?> getById(String id) async => item;

  @override
  Future<CoordinationItem?> tryClaimRemind({
    required String itemId,
    required String actorId,
  }) async {
    claimAttempts++;
    if (!claimSucceeds || claimAttempts > 1) return null;
    return item;
  }
}

class _StubRoom extends Fake implements BeaconRoomRepository {
  _StubRoom({this.admittedUserIds = const {}});

  final Set<String> admittedUserIds;

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async =>
      false;

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
    if (!admittedUserIds.contains(userId)) return null;
    final now = PgDateTime(DateTime.utc(2026));
    return BeaconParticipant(
      createdAt: now,
      updatedAt: now,
      id: 'P1',
      beaconId: beaconId,
      userId: userId,
      role: BeaconParticipantRoleBits.helper,
      status: 0,
      roomAccess: RoomAccessBits.admitted,
    );
  }
}

class _RecordingPush extends BeaconRoomPushService {
  _RecordingPush() : super(_NoopNotificationPort());

  int staleRemindCalls = 0;
  String? lastTarget;

  @override
  Future<void> notifyStaleRemind({
    required String beaconId,
    required String actorUserId,
    required String targetPersonId,
    required String excerpt,
    String? coordinationItemId,
  }) async {
    staleRemindCalls++;
    lastTarget = targetPersonId;
  }
}

class _NoopNotificationPort implements BeaconNotificationPort {
  @override
  Future<void> dispatch(BeaconNotificationIntent intent) async {}
}

void main() {
  late _StubItems items;
  late _StubRoom room;
  late _RecordingPush push;
  late RemindCoordinationItemCase sut;

  const beaconId = 'Bbbbbbbbbbbbb';
  const itemId = 'Iiiiiiiiiiiii';
  const creatorId = 'Ucreator00001';
  const targetId = 'Utarget000001';
  const observerId = 'Uobserver0001';

  CoordinationItem staleAsk({
    int kind = coordinationItemKindAsk,
    int status = coordinationItemStatusOpen,
    String? acceptedById,
  }) {
    final now = PgDateTime(DateTime.utc(2026, 6, 12));
    return CoordinationItem(
      id: itemId,
      beaconId: beaconId,
      kind: kind,
      status: status,
      title: 'Follow up',
      body: 'Body',
      creatorId: creatorId,
      targetPersonId: targetId,
      acceptedById: acceptedById,
      published: true,
      source: coordinationItemSourceDefault,
      createdAt: now,
      updatedAt: now,
      ordering: 0,
      staleAt: PgDateTime(DateTime.utc(2026, 6, 10)),
    );
  }

  setUp(() {
    items = _StubItems();
    room = _StubRoom(admittedUserIds: {observerId, targetId, creatorId});
    push = _RecordingPush();
    items.item = staleAsk();
    items.claimSucceeds = true;
    sut = RemindCoordinationItemCase(
      items,
      room,
      push,
      env: Env(environment: Environment.test),
      logger: Logger('_'),
    );
  });

  test('sends push when claim succeeds', () async {
    await sut.call(userId: observerId, itemId: itemId);
    expect(items.claimAttempts, 1);
    expect(push.staleRemindCalls, 1);
    expect(push.lastTarget, targetId);
  });

  test('rejects responsible person reminding themselves', () async {
    await expectLater(
      () => sut.call(userId: targetId, itemId: itemId),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(push.staleRemindCalls, 0);
  });

  test('rejects non-stale item', () async {
    final now = PgDateTime(DateTime.utc(2026, 6, 12));
    items.item = CoordinationItem(
      id: itemId,
      beaconId: beaconId,
      kind: coordinationItemKindAsk,
      status: coordinationItemStatusOpen,
      title: 'Future',
      body: 'Body',
      creatorId: creatorId,
      targetPersonId: targetId,
      published: true,
      source: coordinationItemSourceDefault,
      createdAt: now,
      updatedAt: now,
      ordering: 0,
      staleAt: PgDateTime(DateTime.utc(2099)),
    );
    await expectLater(
      () => sut.call(userId: observerId, itemId: itemId),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(push.staleRemindCalls, 0);
  });

  test('rejects plan items', () async {
    items.item = staleAsk(kind: coordinationItemKindPlan);
    await expectLater(
      () => sut.call(userId: observerId, itemId: itemId),
      throwsA(isA<BeaconCreateException>()),
    );
  });

  test('throttle when claim returns null', () async {
    items.claimSucceeds = false;
    await expectLater(
      () => sut.call(userId: observerId, itemId: itemId),
      throwsA(isA<BeaconCreateException>()),
    );
    expect(push.staleRemindCalls, 0);
  });

  test('concurrent remind allows at most one push', () async {
    final results = await Future.wait<bool>(
      [
        sut.call(userId: observerId, itemId: itemId).then((_) => true),
        sut.call(userId: creatorId, itemId: itemId).then((_) => true),
      ].map(
        (f) => f.catchError((_) => false),
      ),
    );
    expect(results.where((ok) => ok).length, 1);
    expect(push.staleRemindCalls, 1);
  });
}
