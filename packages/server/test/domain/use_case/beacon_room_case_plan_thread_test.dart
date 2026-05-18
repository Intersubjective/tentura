import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/polling_repository.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';
import 'package:tentura_server/data/storage/remote_storage.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  CoordinationItem? itemById;

  @override
  Future<CoordinationItem?> getById(String id) async => itemById;
}

class _StubRoom extends Fake implements BeaconRoomRepository {
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
  Future<BeaconParticipant?> findParticipant({
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
}

void main() {
  late _StubItems items;
  late _StubRoom room;
  late BeaconRoomCase sut;

  const beaconId = 'Baaaaaaaaaaaa';
  const userId = 'Uaaaaaaaaaaaa';
  const planItemId = 'CIplanaaaaaaa';
  const askItemId = 'CIaskaaaaaaaa';

  CoordinationItem sampleItem({
    required String id,
    required int kind,
  }) {
    final now = PgDateTime(DateTime.utc(2026, 5));
    return CoordinationItem(
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
      FakeBeaconRoomPushService(),
      FakeImageRepositoryPort(),
      FakeTaskRepositoryPort(),
      FakeRemoteStorage(),
      FakePollingRepository(),
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
    implements BeaconFactCardRepository {}

class FakeBeaconRoomPushService extends Fake implements BeaconRoomPushService {}

class FakeImageRepositoryPort extends Fake implements ImageRepositoryPort {}

class FakeTaskRepositoryPort extends Fake implements TaskRepositoryPort {}

class FakeRemoteStorage extends Fake implements RemoteStorage {}

class FakePollingRepository extends Fake implements PollingRepository {}
