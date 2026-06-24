import 'package:drift_postgres/drift_postgres.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';
import '../../support/coordination_item_record_fixtures.dart';

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  CoordinationItemRecord? itemById;

  @override
  Future<CoordinationItemRecord?> getById(String id) async => itemById;
}

class _StubRoom extends Fake implements BeaconRoomRepositoryPort {
  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async =>
      true;

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
  }) async =>
      null;

  @override
  Future<List<Map<String, Object?>>> listMessagesEnriched({
    required String beaconId,
    required String viewerUserId,
    String? threadItemId,
    DateTime? before,
    int limit = 50,
  }) async =>
      const [];

  int recentMessageCount = 0;

  @override
  Future<int> countRecentMessagesByAuthor({
    required String authorId,
    required Duration window,
  }) async =>
      recentMessageCount;
}

void main() {
  late _StubItems items;
  late _StubRoom room;
  late BeaconRoomCase sut;

  const beaconId = 'Baaaaaaaaaaaa';
  const userId = 'Uaaaaaaaaaaaa';
  const planItemId = 'CIplanaaaaaaa';
  const askItemId = 'CIaskaaaaaaaa';

  CoordinationItemRecord sampleItem({
    required String id,
    required int kind,
  }) {
    final now = DateTime.utc(2026, 5);
    return testCoordinationItem(
      id: id,
      beaconId: beaconId,
      kind: kind,
      status: coordinationItemStatusOpen,
      title: 't',
      body: '',
      creatorId: userId,
      source: coordinationItemSourceDefault,
      published: true,
      createdAt: now,
      updatedAt: now,
      ordering: 0,
    );
  }

  setUp(() {
    items = _StubItems();
    room = _StubRoom();
    sut = BeaconRoomCase(
      room,
      items,
      FakeBeaconFactCardRepository(),
      FakeBeaconRoomNotificationPort(),
      FakeImageRepositoryPort(),
      FakeTaskRepositoryPort(),
      FakeRemoteStorage(),
      FakePollingRepository(),
      FakeUploadQuota(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconRoomCasePlanThreadTest'),
    );
  });

  test('createMessage rejects plan item thread', () async {
    items.itemById = sampleItem(id: planItemId, kind: coordinationItemKindPlan);

    expect(
      () => sut.createMessage(
        beaconId: beaconId,
        userId: userId,
        body: 'hello',
        threadItemId: planItemId,
      ),
      throwsA(
        isA<IdWrongException>().having(
          (e) => e.description,
          'description',
          contains('Plan items do not support'),
        ),
      ),
    );
  });

  test('listMessages rejects plan item thread', () async {
    items.itemById = sampleItem(id: planItemId, kind: coordinationItemKindPlan);

    expect(
      () => sut.listMessages(
        beaconId: beaconId,
        userId: userId,
        threadItemId: planItemId,
      ),
      throwsA(isA<IdWrongException>()),
    );
  });

  test('markBeaconRoomSeen rejects plan item thread', () async {
    items.itemById = sampleItem(id: planItemId, kind: coordinationItemKindPlan);

    expect(
      () => sut.markBeaconRoomSeen(
        beaconId: beaconId,
        userId: userId,
        threadItemId: planItemId,
      ),
      throwsA(isA<IdWrongException>()),
    );
  });

  test('createMessage throws RateLimitedException at the per-user cap',
      () async {
    room.recentMessageCount = 5;
    final limited = BeaconRoomCase(
      room,
      items,
      FakeBeaconFactCardRepository(),
      FakeBeaconRoomNotificationPort(),
      FakeImageRepositoryPort(),
      FakeTaskRepositoryPort(),
      FakeRemoteStorage(),
      FakePollingRepository(),
      FakeUploadQuota(),
      env: Env(environment: Environment.test, roomMessageMaxPerUser: 5),
      logger: Logger('BeaconRoomCaseRateLimitTest'),
    );

    await expectLater(
      limited.createMessage(
        beaconId: beaconId,
        userId: userId,
        body: 'spam spam spam',
      ),
      throwsA(isA<RateLimitedException>()),
    );
  });

  test('listMessages allows ask item thread', () async {
    items.itemById = sampleItem(id: askItemId, kind: coordinationItemKindAsk);

    final out = await sut.listMessages(
      beaconId: beaconId,
      userId: userId,
      threadItemId: askItemId,
    );

    expect(out, isEmpty);
  });
}

class FakeBeaconFactCardRepository extends Fake
    implements BeaconFactCardRepositoryPort {}

class FakeBeaconRoomNotificationPort extends Fake implements BeaconRoomNotificationPort {}

class FakeImageRepositoryPort extends Fake implements ImageRepositoryPort {}

class FakeTaskRepositoryPort extends Fake implements TaskRepositoryPort {}

class FakeRemoteStorage extends Fake implements RemoteStoragePort {}

class FakePollingRepository extends Fake implements PollingRepositoryPort {}

class FakeUploadQuota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async =>
      true;
}
