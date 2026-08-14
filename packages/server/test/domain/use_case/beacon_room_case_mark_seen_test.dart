import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/entity/coordination_item_with_counts.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/coordination_item_record_fixtures.dart';
import '../../support/fake_user_block_repository.dart';

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  CoordinationItemRecord? itemById;

  @override
  Future<CoordinationItemRecord?> getById(String id) async => itemById;

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

class _MarkSeenStubRoom extends Fake implements BeaconRoomRepositoryPort {
  DateTime? existingSeen;
  DateTime? latestMessageAt;
  DateTime? storedWatermark;
  String? persistedBeaconId;
  String? persistedThreadItemId;
  DateTime? persistedAt;

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
  Future<BeaconRoomStateRecord?> getBeaconRoomState(String beaconId) async =>
      null;

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
  Future<DateTime> markBeaconRoomSeen({
    required String userId,
    required String beaconId,
    required String? threadItemId,
    required DateTime at,
  }) async {
    persistedBeaconId = beaconId;
    persistedThreadItemId = threadItemId;
    persistedAt = at;
    final prior = storedWatermark;
    final persisted = prior != null && prior.isAfter(at) ? prior : at;
    storedWatermark = persisted;
    return persisted;
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
  late _StubItems items;
  late BeaconRoomCase sut;

  const beaconId = 'Baaaaaaaaaaaa';
  const userId = 'Uaaaaaaaaaaaa';
  const askItemId = 'CIaskaaaaaaaa';
  const planItemId = 'CIplanaaaaaaa';

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
    room = _MarkSeenStubRoom();
    items = _StubItems();
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
      logger: Logger('BeaconRoomCaseMarkSeenTest'),
    );
  });

  test(
    'markThreadSeen general returns persisted seenAt and clamps to latest message',
    () async {
      final readThrough = DateTime.utc(2026, 5, 1, 12);
      final latest = DateTime.utc(2026, 5, 1, 14);
      room.latestMessageAt = latest;

      final out = await sut.markThreadSeen(
        beaconId: beaconId,
        userId: userId,
        threadId: 'general',
        readThroughAtIso: readThrough.toIso8601String(),
      );

      expect(out['beaconId'], beaconId);
      expect(out['threadItemId'], null);
      expect(out['seenAt'], latest.toUtc().toIso8601String());
      expect(room.persistedAt, latest);
      expect(room.persistedThreadItemId, null);
    },
  );

  test('markThreadSeen general never regresses below existing seen watermark',
      () async {
    final existing = DateTime.utc(2026, 5, 1, 16);
    final readThrough = DateTime.utc(2026, 5, 1, 12);
    room.existingSeen = existing;
    room.latestMessageAt = DateTime.utc(2026, 5, 1, 14);

    final out = await sut.markThreadSeen(
      beaconId: beaconId,
      userId: userId,
      threadId: 'general',
      readThroughAtIso: readThrough.toIso8601String(),
    );

    expect(out['seenAt'], existing.toUtc().toIso8601String());
    expect(room.persistedAt, existing);
  });

  test('markThreadSeen general sentinel reaches repository as null threadItemId',
      () async {
    final out = await sut.markThreadSeen(
      beaconId: beaconId,
      userId: userId,
      threadId: 'general',
    );

    expect(out['threadItemId'], null);
    expect(room.persistedThreadItemId, null);
    expect(room.persistedThreadItemId, isNot('general'));
  });

  test('markThreadSeen passes real item id unchanged', () async {
    items.itemById = sampleItem(id: askItemId, kind: coordinationItemKindAsk);

    final out = await sut.markThreadSeen(
      beaconId: beaconId,
      userId: userId,
      threadId: askItemId,
    );

    expect(out['threadItemId'], askItemId);
    expect(room.persistedThreadItemId, askItemId);
  });

  test('markThreadSeen semantic path does not clamp or floor readThrough', () async {
    final readThrough = DateTime.utc(2026, 5, 1, 10);
    final latest = DateTime.utc(2026, 5, 1, 14);
    final existing = DateTime.utc(2026, 5, 1, 16);
    room.latestMessageAt = latest;
    room.existingSeen = existing;
    items.itemById = sampleItem(id: askItemId, kind: coordinationItemKindAsk);

    final out = await sut.markThreadSeen(
      beaconId: beaconId,
      userId: userId,
      threadId: askItemId,
      readThroughAtIso: readThrough.toIso8601String(),
    );

    expect(room.persistedAt, readThrough);
    expect(out['seenAt'], readThrough.toUtc().toIso8601String());
  });

  test('markThreadSeen rejects plan item thread', () async {
    items.itemById = sampleItem(id: planItemId, kind: coordinationItemKindPlan);

    expect(
      () => sut.markThreadSeen(
        beaconId: beaconId,
        userId: userId,
        threadId: planItemId,
      ),
      throwsA(isA<IdWrongException>()),
    );
  });

  test('markThreadSeen rejects empty threadId after trim', () async {
    expect(
      () => sut.markThreadSeen(
        beaconId: beaconId,
        userId: userId,
        threadId: '   ',
      ),
      throwsA(isA<ArgumentError>()),
    );
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
    implements BeaconFactCardRepositoryPort {
  @override
  Future<String> latestPublicFactSnippet(String beaconId) async => '';
}

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
