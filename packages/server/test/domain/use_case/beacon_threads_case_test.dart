import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/beacon_thread_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_with_counts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_user_block_repository.dart';

class _RecordingItems extends Fake implements CoordinationItemRepositoryPort {
  bool? lastIncludeGeneral;
  bool? lastItemParticipantsOnly;
  List<BeaconThreadRecord> nextRows = const [];

  @override
  Future<List<BeaconThreadRecord>> listThreads({
    required String beaconId,
    required String viewerUserId,
    required bool includeGeneral,
    required bool itemParticipantsOnly,
    required int excerptCharacters,
  }) async {
    lastIncludeGeneral = includeGeneral;
    lastItemParticipantsOnly = itemParticipantsOnly;
    expect(excerptCharacters, 140);
    return nextRows;
  }
}

class _AuthStubRoom extends Fake implements BeaconRoomRepositoryPort {
  bool isAuthor = false;
  bool isSteward = false;
  BeaconParticipantRecord? participant;

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async =>
      isAuthor;

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async =>
      isSteward;

  @override
  Future<BeaconParticipantRecord?> findParticipant({
    required String beaconId,
    required String userId,
  }) async =>
      participant;
}

BeaconThreadRecord _generalRow() => const BeaconThreadRecord(
      threadId: 'general',
      threadKind: 'general',
      unreadCount: 0,
      messageCount: 0,
    );

BeaconThreadRecord _askRow(String id) => BeaconThreadRecord(
      threadId: id,
      threadKind: 'ask',
      unreadCount: 0,
      messageCount: 0,
      item: CoordinationItemWithCounts(
        item: CoordinationItemRecord(
          id: id,
          beaconId: 'Bthreadsauth1',
          kind: 2,
          status: 0,
          creatorId: 'Uthreadsauth1',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        messageCount: 0,
        unreadCount: 0,
      ),
    );

void main() {
  late _AuthStubRoom room;
  late _RecordingItems items;
  late BeaconRoomCase sut;

  const beaconId = 'Bthreadsauth1';
  const memberId = 'Uthreadsauth1';
  const outsiderId = 'Uthreadsauth2';

  setUp(() {
    room = _AuthStubRoom();
    items = _RecordingItems();
    sut = BeaconRoomCase(
      room,
      items,
      FakeBeaconFactCardRepository(),
      FakeImageRepositoryPort(),
      FakeTaskRepositoryPort(),
      FakeRemoteStorage(),
      FakePollingRepository(),
      FakeUploadQuota(),
      FakeUserBlockRepository(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconThreadsCaseTest'),
    );
  });

  test('room member requests General plus full item list', () async {
    room.isAuthor = true;
    items.nextRows = [_generalRow(), _askRow('Ithreadsask01')];

    final rows = await sut.listThreads(beaconId: beaconId, userId: memberId);

    expect(items.lastIncludeGeneral, isTrue);
    expect(items.lastItemParticipantsOnly, isFalse);
    expect(rows, hasLength(2));
    expect(rows.first.threadId, 'general');
  });

  test('item-only participant omits General and filters to participant items',
      () async {
    items.nextRows = [_askRow('Ithreadsask01')];

    final rows = await sut.listThreads(beaconId: beaconId, userId: outsiderId);

    expect(items.lastIncludeGeneral, isFalse);
    expect(items.lastItemParticipantsOnly, isTrue);
    expect(rows, hasLength(1));
    expect(rows.single.threadKind, 'ask');
    expect(rows.every((r) => r.threadId != 'general'), isTrue);
  });

  test('inaccessible empty result throws the item-thread unauthorized error',
      () async {
    items.nextRows = const [];

    expect(
      () => sut.listThreads(beaconId: beaconId, userId: outsiderId),
      throwsA(
        isA<UnauthorizedException>().having(
          (e) => e.description,
          'description',
          'Room or item thread access required',
        ),
      ),
    );
  });

  test('room member with only General still succeeds', () async {
    room.participant = BeaconParticipantRecord(
      id: 'Pthreadsauth1',
      beaconId: beaconId,
      userId: memberId,
      role: 2,
      status: 0,
      roomAccess: 3,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    items.nextRows = [_generalRow()];

    final rows = await sut.listThreads(beaconId: beaconId, userId: memberId);

    expect(rows, hasLength(1));
    expect(rows.single.threadId, 'general');
  });
}

class FakeBeaconFactCardRepository extends Fake
    implements BeaconFactCardRepositoryPort {}

class FakeImageRepositoryPort extends Fake implements ImageRepositoryPort {}

class FakeTaskRepositoryPort extends Fake implements TaskRepositoryPort {}

class FakeRemoteStorage extends Fake implements RemoteStoragePort {}

class FakePollingRepository extends Fake implements PollingRepositoryPort {}

class FakeUploadQuota extends Fake implements UploadQuotaRepositoryPort {}
