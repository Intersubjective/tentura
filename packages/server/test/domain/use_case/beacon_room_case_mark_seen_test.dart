import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/polling_repository.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';
import 'package:tentura_server/data/storage/remote_storage.dart';
import 'package:tentura_server/domain/entity/coordination_item_with_counts.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  @override
  Future<List<CoordinationItemWithCounts>> listByBeacon(
    String beaconId, {
    required String viewerUserId,
    int? status,
    int? kind,
    String? acceptedById,
    String? targetPersonId,
    String? linkedParentItemId,
    bool rootOnly = false,
  }) async =>
      const [];
}

class _MarkSeenStubRoom extends Fake implements BeaconRoomRepository {
  DateTime? existingSeen;
  DateTime? latestMessageAt;
  DateTime? persistedAt;
  String? persistedBeaconId;

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
  Future<BeaconRoomState?> getBeaconRoomState(String beaconId) async => null;

  @override
  Future<DateTime?> latestMainRoomMessageCreatedAt(String beaconId) async =>
      latestMessageAt;

  @override
  Future<DateTime?> getMainRoomLastSeen({
    required String beaconId,
    required String userId,
  }) async =>
      existingSeen;

  @override
  Future<void> markBeaconRoomSeen({
    required String userId,
    required String beaconId,
    required String? threadItemId,
    required DateTime at,
  }) async {
    persistedBeaconId = beaconId;
    persistedAt = at;
  }

  @override
  Future<int> countRoomMessagesAfter({
    required String beaconId,
    DateTime? after,
    String? excludeAuthorId,
  }) async =>
      0;
}

void main() {
  late _MarkSeenStubRoom room;
  late BeaconRoomCase sut;

  const beaconId = 'Baaaaaaaaaaaa';
  const userId = 'Uaaaaaaaaaaaa';

  setUp(() {
    room = _MarkSeenStubRoom();
    sut = BeaconRoomCase(
      room,
      _StubItems(),
      FakeBeaconFactCardRepository(),
      FakeBeaconRoomPushService(),
      FakeImageRepositoryPort(),
      FakeTaskRepositoryPort(),
      FakeRemoteStorage(),
      FakePollingRepository(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconRoomCaseMarkSeenTest'),
    );
  });

  test('markBeaconRoomSeen returns persisted seenAt and clamps to latest message',
      () async {
    final readThrough = DateTime.utc(2026, 5, 1, 12);
    final latest = DateTime.utc(2026, 5, 1, 14);
    room.latestMessageAt = latest;

    final out = await sut.markBeaconRoomSeen(
      beaconId: beaconId,
      userId: userId,
      readThroughAtIso: readThrough.toIso8601String(),
    );

    expect(out['beaconId'], beaconId);
    expect(out['threadItemId'], null);
    expect(out['seenAt'], latest.toUtc().toIso8601String());
    expect(room.persistedAt, latest);
  });

  test('markBeaconRoomSeen never regresses below existing seen watermark', () async {
    final existing = DateTime.utc(2026, 5, 1, 16);
    final readThrough = DateTime.utc(2026, 5, 1, 12);
    room.existingSeen = existing;
    room.latestMessageAt = DateTime.utc(2026, 5, 1, 14);

    final out = await sut.markBeaconRoomSeen(
      beaconId: beaconId,
      userId: userId,
      readThroughAtIso: readThrough.toIso8601String(),
    );

    expect(out['seenAt'], existing.toUtc().toIso8601String());
    expect(room.persistedAt, existing);
  });

  test('inboxRoomContextBatch includes lastSeenAt for room members', () async {
    final seen = DateTime.utc(2026, 5, 2, 10);
    room.existingSeen = seen;

    final rows = await sut.inboxRoomContextBatch(
      userId: userId,
      beaconIds: [beaconId],
    );

    expect(rows, hasLength(1));
    expect(rows.first['beaconId'], beaconId);
    expect(rows.first['isRoomMember'], isTrue);
    expect(rows.first['roomUnreadCount'], 0);
    expect(rows.first['lastSeenAt'], seen.toUtc().toIso8601String());
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
