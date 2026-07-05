import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
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

final _jpegBytes = Uint8List.fromList([
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
  0x4A,
  0x46,
  0x49,
  0x46,
]);

class _CapturingRoom extends Fake implements BeaconRoomRepositoryPort {
  String? lastFileDisplayName;
  String? lastImageDisplayName;

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

  @override
  Future<void> insertRoomMessageAttachmentFile({
    required String attachmentId,
    required String messageId,
    required int position,
    required String storagePath,
    required String mime,
    required int sizeBytes,
    required String displayName,
    required String mutatingUserId,
  }) async {
    lastFileDisplayName = displayName;
  }

  @override
  Future<void> insertRoomMessageAttachmentImage({
    required String attachmentId,
    required String messageId,
    required int position,
    required String imageId,
    required String mime,
    required int sizeBytes,
    required String displayName,
    required String mutatingUserId,
  }) async {
    lastImageDisplayName = displayName;
  }
}

class _AllowingQuota extends Fake implements UploadQuotaRepositoryPort {
  @override
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async =>
      true;
}

class _CapturingRemoteStorage extends Fake implements RemoteStoragePort {
  String? lastPutPath;

  @override
  Future<String> putObject(
    String path,
    Stream<Uint8List> bytes, {
    Map<String, String>? metadata,
  }) async {
    lastPutPath = path;
    return path;
  }
}

class _CapturingImages extends Fake implements ImageRepositoryPort {
  @override
  Future<String> put({
    required String authorId,
    required Stream<Uint8List> bytes,
  }) async =>
      'Iaaaaaaaaaaaa';
}

class _CapturingTasks extends Fake implements TaskRepositoryPort {
  @override
  Future<String> schedule(TaskEntity task) async => 'task-id';
}

class _FakeItems extends Fake implements CoordinationItemRepositoryPort {}

class _FakeFactCards extends Fake implements BeaconFactCardRepositoryPort {}

class _FakePush extends Fake implements BeaconRoomNotificationPort {}

class _FakePolling extends Fake implements PollingRepositoryPort {}

BeaconRoomCase _sut({
  required _CapturingRoom room,
  required _CapturingRemoteStorage storage,
  ImageRepositoryPort? images,
}) =>
    BeaconRoomCase(
      room,
      _FakeItems(),
      _FakeFactCards(),
      _FakePush(),
      images ?? _CapturingImages(),
      _CapturingTasks(),
      storage,
      _FakePolling(),
      _AllowingQuota(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconRoomAttachmentUploadTest'),
    );

void main() {
  test('file attachment stores Cyrillic displayName and hash storage key', () async {
    final room = _CapturingRoom();
    final storage = _CapturingRemoteStorage();
    final sut = _sut(room: room, storage: storage);
    final bytes = Uint8List.fromList('plain text content'.codeUnits);
    final expectedPath =
        '$kRoomAttachmentsPath/${sha256.convert(bytes).toString()}';

    await sut.addMessageAttachment(
      beaconId: _beaconId,
      userId: _userId,
      messageId: _messageId,
      attachmentBytes: Stream.value(bytes),
      attachmentFilename: 'Отчёт.pdf',
      attachmentMimeType: 'application/pdf',
    );

    expect(room.lastFileDisplayName, 'Отчёт.pdf');
    expect(storage.lastPutPath, expectedPath);
  });

  test('image attachment stores Cyrillic displayName in image pipeline', () async {
    final room = _CapturingRoom();
    final storage = _CapturingRemoteStorage();
    final sut = _sut(room: room, storage: storage);

    await sut.addMessageAttachment(
      beaconId: _beaconId,
      userId: _userId,
      messageId: _messageId,
      attachmentBytes: Stream.value(_jpegBytes),
      attachmentFilename: 'фото.png',
      attachmentMimeType: 'application/octet-stream',
    );

    expect(room.lastImageDisplayName, 'фото.png');
    expect(room.lastFileDisplayName, isNull);
    expect(storage.lastPutPath, isNull);
  });
}
