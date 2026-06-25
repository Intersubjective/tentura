import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/exception.dart';
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

const _beaconId = 'Baaaaaaaaaaaa';
const _userId = 'Uaaaaaaaaaaaa';
const _messageId = 'Raaaaaaaaaaaa';

class _StubRoom extends Fake implements BeaconRoomRepositoryPort {
  @override
  Future<BeaconRoomMessageRecord?> getRoomMessageById(String id) async =>
      BeaconRoomMessageRecord(
        id: _messageId,
        beaconId: _beaconId,
        authorId: _userId,
        createdAt: DateTime.utc(2026),
      );

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async =>
      true;

  @override
  Future<int> countAttachmentsForMessage(String messageId) async => 0;
}

class _RejectingQuota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async =>
      false;
}

class _FakeItems extends Fake implements CoordinationItemRepositoryPort {}

class _FakeFactCards extends Fake implements BeaconFactCardRepositoryPort {}

class _FakePush extends Fake implements BeaconRoomNotificationPort {}

class _FakeImages extends Fake implements ImageRepositoryPort {}

class _FakeTasks extends Fake implements TaskRepositoryPort {}

class _FakeRemoteStorage extends Fake implements RemoteStoragePort {}

class _FakePolling extends Fake implements PollingRepositoryPort {}

void main() {
  test('file attachment over the daily cap throws RateLimitedException',
      () async {
    final sut = BeaconRoomCase(
      _StubRoom(),
      _FakeItems(),
      _FakeFactCards(),
      _FakePush(),
      _FakeImages(),
      _FakeTasks(),
      _FakeRemoteStorage(),
      _FakePolling(),
      _RejectingQuota(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconRoomAttachmentQuotaTest'),
    );

    await expectLater(
      sut.addMessageAttachment(
        beaconId: _beaconId,
        userId: _userId,
        messageId: _messageId,
        attachmentBytes: Stream.value(
          Uint8List.fromList('plain text content'.codeUnits),
        ),
        attachmentFilename: 'notes.txt',
        attachmentMimeType: 'text/plain',
      ),
      throwsA(
        isA<RateLimitedException>().having(
          (e) => e.description,
          'description',
          'Daily upload limit reached, try again tomorrow',
        ),
      ),
    );
  });
}
