import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../support/fake_beacon_hierarchy_repository.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/room_read_watermark_record.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/coordination_item_record_fixtures.dart';
import '../../support/fake_user_block_repository.dart';

const _beaconId = 'Baaaaaaaaaaaa';
const _userId = 'Uaaaaaaaaaaaa';
const _otherUserId = 'Ubbbbbbbbbbbb';

RoomReadWatermarkRecord _watermark({
  required String userId,
  required DateTime lastSeenAt,
  String userTitle = 'title',
}) =>
    RoomReadWatermarkRecord(
      userId: userId,
      lastSeenAt: lastSeenAt,
      userTitle: userTitle,
      userHasPicture: false,
      userImageId: '',
      userBlurHash: '',
      userPicHeight: 0,
      userPicWidth: 0,
    );

class _StubRoom extends Fake implements BeaconRoomRepositoryPort {
  bool isAuthor = false;
  bool isSteward = false;
  BeaconParticipantRecord? participant;
  List<RoomReadWatermarkRecord> watermarkRows = const [];
  int mainRoomReadWatermarksCallCount = 0;
  String? lastMainRoomReadWatermarksBeaconId;

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

  @override
  Future<List<RoomReadWatermarkRecord>> mainRoomReadWatermarks(
    String beaconId,
  ) async {
    mainRoomReadWatermarksCallCount++;
    lastMainRoomReadWatermarksBeaconId = beaconId;
    return watermarkRows;
  }
}

void main() {
  late _StubRoom room;
  late BeaconRoomCase sut;

  setUp(() {
    room = _StubRoom();
    sut = BeaconRoomCase(
      room,
      _FakeItems(),
      _FakeFactCards(),
      _FakeImages(),
      _FakeTasks(),
      _FakeRemoteStorage(),
      _FakePolling(),
      _FakeUploadQuota(),
      FakeUserBlockRepository(),
      PassThroughMutatingUnitOfWork(),
      FakeBeaconHierarchyRepository(),
      const ProductionDiscussionProductPolicy(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconRoomCaseReadWatermarksTest'),
    );
  });

  group('listMainRoomReadWatermarks', () {
    test('denies non-member and never calls the port', () async {
      room
        ..isAuthor = false
        ..isSteward = false
        ..participant = testBeaconParticipant(
          beaconId: _beaconId,
          userId: _userId,
          roomAccess: RoomAccessBits.requested,
        )
        ..watermarkRows = [
          _watermark(
            userId: _otherUserId,
            lastSeenAt: DateTime.utc(2026, 3, 1),
          ),
        ];

      await expectLater(
        sut.listMainRoomReadWatermarks(
          beaconId: _beaconId,
          userId: _userId,
        ),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.description,
            'description',
            contains('Room access required'),
          ),
        ),
      );
      expect(room.mainRoomReadWatermarksCallCount, 0);
    });

    test('returns port rows unchanged and in order for admitted viewer', () async {
      final newer = DateTime.utc(2026, 3, 2, 12);
      final older = DateTime.utc(2026, 3, 1, 8);
      room
        ..isAuthor = false
        ..isSteward = false
        ..participant = testBeaconParticipant(
          beaconId: _beaconId,
          userId: _userId,
          roomAccess: RoomAccessBits.admitted,
        )
        ..watermarkRows = [
          _watermark(userId: _otherUserId, lastSeenAt: newer, userTitle: 'other'),
          _watermark(userId: _userId, lastSeenAt: older, userTitle: 'viewer'),
        ];

      final rows = await sut.listMainRoomReadWatermarks(
        beaconId: _beaconId,
        userId: _userId,
      );

      expect(room.mainRoomReadWatermarksCallCount, 1);
      expect(room.lastMainRoomReadWatermarksBeaconId, _beaconId);
      expect(rows, room.watermarkRows);
      expect(rows.map((r) => r.userId).toList(), [_otherUserId, _userId]);
      expect(rows.map((r) => r.lastSeenAt).toList(), [newer, older]);
    });

    test('allows beacon author without a participant row', () async {
      room
        ..isAuthor = true
        ..isSteward = false
        ..participant = null
        ..watermarkRows = [
          _watermark(
            userId: _userId,
            lastSeenAt: DateTime.utc(2026, 3, 3),
            userTitle: 'author',
          ),
        ];

      final rows = await sut.listMainRoomReadWatermarks(
        beaconId: _beaconId,
        userId: _userId,
      );

      expect(room.mainRoomReadWatermarksCallCount, 1);
      expect(rows, room.watermarkRows);
    });
  });
}

class _FakeItems extends Fake implements CoordinationItemRepositoryPort {}

class _FakeFactCards extends Fake implements BeaconFactCardRepositoryPort {}

class _FakeImages extends Fake implements ImageRepositoryPort {}

class _FakeTasks extends Fake implements TaskRepositoryPort {}

class _FakeRemoteStorage extends Fake implements RemoteStoragePort {}

class _FakePolling extends Fake implements PollingRepositoryPort {}

class _FakeUploadQuota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async =>
      true;
}
