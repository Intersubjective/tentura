import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/polling_repository.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';
import 'package:tentura_server/data/storage/remote_storage.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_record.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

class _FakeItems extends Fake implements CoordinationItemRepositoryPort {}

class _BatchStubRoom extends Fake implements BeaconRoomRepository {
  List<String>? lastBeaconIds;
  String? lastViewerUserId;

  @override
  Future<List<MyWorkLastActivityEventRow>> latestActivityEventsByBeaconIds({
    required List<String> beaconIds,
    required String viewerUserId,
  }) async {
    lastBeaconIds = beaconIds;
    lastViewerUserId = viewerUserId;
    if (beaconIds.isEmpty) {
      return const [];
    }
    return [
      MyWorkLastActivityEventRow(
        beaconId: beaconIds.first,
        event: BeaconActivityEventRecord(
          id: 'E1',
          beaconId: beaconIds.first,
          visibility: 0,
          type: BeaconActivityEventTypeBits.beaconPublished,
          actorId: 'Uauth',
          createdAt: DateTime.utc(2026, 6, 18),
        ),
        actorTitle: 'Alice',
      ),
    ];
  }
}

void main() {
  test('myWorkLastActivityEventsByBeaconIds caps and delegates to room repo', () async {
    final room = _BatchStubRoom();
    final case_ = BeaconRoomCase(
      room,
      _FakeItems(),
      FakeBeaconFactCardRepository(),
      FakeBeaconRoomPushService(),
      FakeImageRepositoryPort(),
      FakeTaskRepositoryPort(),
      FakeRemoteStorage(),
      FakePollingRepository(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconRoomCaseBatchTest'),
    );

    final ids = List.generate(90, (i) => 'B$i');
    final rows = await case_.myWorkLastActivityEventsByBeaconIds(
      userId: 'Uviewer',
      beaconIds: ids,
    );

    expect(room.lastViewerUserId, 'Uviewer');
    expect(room.lastBeaconIds, hasLength(80));
    expect(rows, hasLength(1));
    expect(rows.single.event?.type, BeaconActivityEventTypeBits.beaconPublished);
  });
}

class FakeBeaconFactCardRepository extends Fake
    implements BeaconFactCardRepository {
  @override
  Future<String> latestPublicFactSnippet(String beaconId) async => '';
}

class FakeBeaconRoomPushService extends Fake implements BeaconRoomPushService {}

class FakeImageRepositoryPort extends Fake implements ImageRepositoryPort {}

class FakeTaskRepositoryPort extends Fake implements TaskRepositoryPort {}

class FakeRemoteStorage extends Fake implements RemoteStorage {}

class FakePollingRepository extends Fake implements PollingRepository {}
