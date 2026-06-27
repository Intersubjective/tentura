import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/coordination_item_record_fixtures.dart';

const _beaconId = 'Baaaaaaaaaaaa';
const _userId = 'Uaaaaaaaaaaaa';

Map<String, Object?> _activityRow({
  required String id,
  required int visibility,
}) =>
    {
      'id': id,
      'beaconId': _beaconId,
      'visibility': visibility,
      'type': BeaconActivityEventTypeBits.beaconPublished,
      'createdAt': DateTime.utc(2026).toIso8601String(),
    };

class _StubRoom extends Fake implements BeaconRoomRepositoryPort {
  bool isAuthor = false;
  bool isSteward = false;
  BeaconParticipantRecord? participant;
  List<Map<String, Object?>> activityRows = const [];

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
  Future<List<Map<String, Object?>>> listActivityEvents({
    required String beaconId,
    int limit = 200,
  }) async =>
      activityRows;
}

void main() {
  late _StubRoom room;
  late BeaconRoomCase sut;

  setUp(() {
    room = _StubRoom()
      ..activityRows = [
        _activityRow(
          id: 'Epublic01',
          visibility: BeaconActivityEventVisibilityBits.public,
        ),
        _activityRow(
          id: 'Eroom0001',
          visibility: BeaconActivityEventVisibilityBits.room,
        ),
      ];
    sut = BeaconRoomCase(
      room,
      _FakeItems(),
      _FakeFactCards(),
      _FakePush(),
      _FakeImages(),
      _FakeTasks(),
      _FakeRemoteStorage(),
      _FakePolling(),
      _FakeUploadQuota(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconRoomCaseActivityEventsTest'),
    );
  });

  group('listActivityEvents', () {
    test('returns public-only rows when caller lacks room access', () async {
      room
        ..isAuthor = false
        ..isSteward = false
        ..participant = testBeaconParticipant(
          beaconId: _beaconId,
          userId: _userId,
          roomAccess: RoomAccessBits.requested,
        );

      final rows = await sut.listActivityEvents(
        beaconId: _beaconId,
        userId: _userId,
      );

      expect(rows, hasLength(1));
      expect(rows.single['id'], 'Epublic01');
      expect(
        rows.single['visibility'],
        BeaconActivityEventVisibilityBits.public,
      );
    });

    test('returns all rows for admitted room member', () async {
      room
        ..isAuthor = false
        ..isSteward = false
        ..participant = testBeaconParticipant(
          beaconId: _beaconId,
          userId: _userId,
          roomAccess: RoomAccessBits.admitted,
        );

      final rows = await sut.listActivityEvents(
        beaconId: _beaconId,
        userId: _userId,
      );

      expect(rows, hasLength(2));
      expect(rows.map((r) => r['id']), containsAll(['Epublic01', 'Eroom0001']));
    });
  });
}

class _FakeItems extends Fake implements CoordinationItemRepositoryPort {}

class _FakeFactCards extends Fake implements BeaconFactCardRepositoryPort {}

class _FakePush extends Fake implements BeaconRoomNotificationPort {}

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
