import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';
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

import '../../support/coordination_item_record_fixtures.dart';
import '../../support/test_attention_harness.dart';

const _beaconId = 'Baaaaaaaaaaaa';
const _userId = 'Uaaaaaaaaaaaa';
const _otherUserId = 'Ubbbbbbbbbbbb';
const _messageId = 'Raaaaaaaaaaaa';
const _replyMessageId = 'Rbbbbbbbbbbbb';
const _threadItemId = 'CIaskaaaaaaaa';

class _StubItems extends Fake implements CoordinationItemRepositoryPort {
  CoordinationItemRecord? itemById;

  @override
  Future<CoordinationItemRecord?> getById(String id) async => itemById;
}

class _StubRoom extends Fake implements BeaconRoomRepositoryPort {
  bool isAuthor = false;
  bool isSteward = false;
  BeaconParticipantRecord? participant;
  BeaconRoomMessageRecord? messageById;
  BeaconRoomMessageRecord? replyMessage;

  String? insertedBody;
  List<String>? insertedMentions;
  String? updatedBody;
  List<String>? updatedMentions;
  String? deletedMessageId;

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async => isAuthor;

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async => isSteward;

  @override
  Future<BeaconParticipantRecord?> findParticipant({
    required String beaconId,
    required String userId,
  }) async => participant;

  @override
  Future<int> countRecentMessagesByAuthor({
    required String authorId,
    required Duration window,
  }) async => 0;

  @override
  Future<List<String>> resolveMentionUserIdsForBeacon({
    required String beaconId,
    required String body,
  }) async => body.contains('@mention') ? [_otherUserId] : const [];

  @override
  Future<BeaconRoomMessageRecord> insertRoomMessage({
    required String beaconId,
    required String authorId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    String? linkedParticipantId,
    String? linkedPollingId,
    int? semanticMarker,
    Map<String, Object?>? systemPayload,
    List<String> mentions = const [],
  }) async {
    insertedBody = body;
    insertedMentions = mentions;
    return BeaconRoomMessageRecord(
      id: _messageId,
      beaconId: beaconId,
      authorId: authorId,
      body: body,
      replyToMessageId: replyToMessageId,
      threadItemId: threadItemId,
      createdAt: DateTime.utc(2026),
      mentions: mentions,
    );
  }

  @override
  Future<BeaconRoomMessageRecord?> getRoomMessageById(String id) async {
    if (replyMessage != null && id == replyMessage!.id) {
      return replyMessage;
    }
    if (messageById != null && id == messageById!.id) {
      return messageById;
    }
    return messageById;
  }

  @override
  Future<void> updateMessage({
    required String messageId,
    required String newBody,
    required List<String> mentions,
  }) async {
    updatedBody = newBody;
    updatedMentions = mentions;
  }

  @override
  Future<void> deleteRoomMessage({required String messageId}) async {
    deletedMessageId = messageId;
  }
}

void main() {
  late _StubItems items;
  late _StubRoom room;
  late BeaconRoomCase sut;
  late TestAttentionHarness attention;

  setUp(() {
    items = _StubItems();
    room = _StubRoom()
      ..participant = testBeaconParticipant(
        beaconId: _beaconId,
        userId: _userId,
        roomAccess: RoomAccessBits.admitted,
      )
      ..messageById = BeaconRoomMessageRecord(
        id: _messageId,
        beaconId: _beaconId,
        authorId: _userId,
        body: 'original',
        createdAt: DateTime.utc(2026),
      );
    attention = TestAttentionHarness();
    sut = BeaconRoomCase(
      room,
      items,
      _FakeFactCards(),
      _FakePush(),
      _FakeImages(),
      _FakeTasks(),
      _FakeRemoteStorage(),
      _FakePolling(),
      _FakeUploadQuota(),
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: Env(
        environment: Environment.test,
      ),
      logger: Logger('BeaconRoomCaseMessageMutationsTest'),
    );
  });

  group('createMessage', () {
    test(
      'inserts trimmed body and resolved mentions for admitted member',
      () async {
        final out = await sut.createMessage(
          beaconId: _beaconId,
          userId: _userId,
          body: '  hello @mention  ',
        );

        expect(out['id'], _messageId);
        expect(out['beaconId'], _beaconId);
        expect(room.insertedBody, 'hello @mention');
        expect(room.insertedMentions, [_otherUserId]);
        final intent = attention.recorded.single;
        expect(intent.eventType, AttentionEventType.roomMessagePosted);
        expect(intent.messageId, _messageId);
        expect(intent.coordinationItemId, isNull);
        expect(intent.actionUrl, contains('message=$_messageId'));
        expect(
          intent.recipients.map((recipient) => recipient.recipientId),
          [_otherUserId],
        );
      },
    );

    test('ordinary Chat message creates no Updates receipt', () async {
      await sut.createMessage(
        beaconId: _beaconId,
        userId: _userId,
        body: 'hello room',
      );

      expect(attention.recorded, isEmpty);
    });

    test('reply targets the original author in the same chat scope', () async {
      room.replyMessage = BeaconRoomMessageRecord(
        id: _replyMessageId,
        beaconId: _beaconId,
        authorId: _otherUserId,
        body: 'question',
        createdAt: DateTime.utc(2026),
      );

      await sut.createMessage(
        beaconId: _beaconId,
        userId: _userId,
        body: 'answer',
        replyToMessageId: _replyMessageId,
      );

      expect(
        attention.recorded.single.recipients.single.recipientId,
        _otherUserId,
      );
    });

    test('rejects a reply that crosses beacon chat scope', () async {
      room.replyMessage = BeaconRoomMessageRecord(
        id: _replyMessageId,
        beaconId: 'Bother',
        authorId: _otherUserId,
        createdAt: DateTime.utc(2026),
      );

      await expectLater(
        sut.createMessage(
          beaconId: _beaconId,
          userId: _userId,
          body: 'answer',
          replyToMessageId: _replyMessageId,
        ),
        throwsA(isA<IdWrongException>()),
      );
      expect(attention.recorded, isEmpty);
    });

    test(
      'throws UnauthorizedException when caller lacks room access',
      () async {
        room.participant = testBeaconParticipant(
          beaconId: _beaconId,
          userId: _userId,
          roomAccess: RoomAccessBits.requested,
        );

        await expectLater(
          sut.createMessage(
            beaconId: _beaconId,
            userId: _userId,
            body: 'hello',
          ),
          throwsA(
            isA<UnauthorizedException>().having(
              (e) => e.description,
              'description',
              contains('Room access required'),
            ),
          ),
        );
      },
    );

    test(
      'throws BeaconCreateException when body and attachment are empty',
      () async {
        await expectLater(
          sut.createMessage(
            beaconId: _beaconId,
            userId: _userId,
            body: '   ',
          ),
          throwsA(
            isA<BeaconCreateException>().having(
              (e) => e.description,
              'description',
              contains('text or attachment required'),
            ),
          ),
        );
      },
    );

    test('throws BeaconCreateException when body exceeds max length', () async {
      await expectLater(
        sut.createMessage(
          beaconId: _beaconId,
          userId: _userId,
          body: 'x' * (kMaxRoomMessageBodyLength + 1),
        ),
        throwsA(
          isA<BeaconCreateException>().having(
            (e) => e.description,
            'description',
            contains('too long'),
          ),
        ),
      );
    });

    test('allows ask item thread when caller is item participant', () async {
      items.itemById = testCoordinationItem(
        id: _threadItemId,
        beaconId: _beaconId,
        kind: coordinationItemKindAsk,
        creatorId: _userId,
      );
      room.participant = null;
      room.isAuthor = false;

      final out = await sut.createMessage(
        beaconId: _beaconId,
        userId: _userId,
        body: 'thread reply',
        threadItemId: _threadItemId,
      );

      expect(out['id'], _messageId);
      expect(room.insertedBody, 'thread reply');
    });

    test(
      'directed item target receives exact thread message receipt',
      () async {
        items.itemById = testCoordinationItem(
          id: _threadItemId,
          beaconId: _beaconId,
          kind: coordinationItemKindAsk,
          creatorId: _userId,
          targetPersonId: _otherUserId,
        );
        room.participant = null;

        await sut.createMessage(
          beaconId: _beaconId,
          userId: _userId,
          body: 'directed update',
          threadItemId: _threadItemId,
        );

        final intent = attention.recorded.single;
        expect(intent.coordinationItemId, _threadItemId);
        expect(intent.actionUrl, contains('item=$_threadItemId'));
        expect(intent.recipients.single.recipientId, _otherUserId);
      },
    );
  });

  group('editMessage', () {
    test('updates body and mentions for message author', () async {
      final ok = await sut.editMessage(
        beaconId: _beaconId,
        messageId: _messageId,
        userId: _userId,
        newBody: '  edited @mention  ',
      );

      expect(ok, isTrue);
      expect(room.updatedBody, 'edited @mention');
      expect(room.updatedMentions, [_otherUserId]);
    });

    test('throws IdNotFoundException when message is missing', () async {
      room.messageById = null;

      await expectLater(
        sut.editMessage(
          beaconId: _beaconId,
          messageId: _messageId,
          userId: _userId,
          newBody: 'nope',
        ),
        throwsA(isA<IdNotFoundException>()),
      );
    });

    test(
      'throws UnauthorizedException when caller is not the author',
      () async {
        room.participant = testBeaconParticipant(
          beaconId: _beaconId,
          userId: _otherUserId,
          roomAccess: RoomAccessBits.admitted,
        );

        await expectLater(
          sut.editMessage(
            beaconId: _beaconId,
            messageId: _messageId,
            userId: _otherUserId,
            newBody: 'nope',
          ),
          throwsA(
            isA<UnauthorizedException>().having(
              (e) => e.description,
              'description',
              contains('Only the message author can edit'),
            ),
          ),
        );
      },
    );

    test('throws BeaconCreateException when new body is empty', () async {
      await expectLater(
        sut.editMessage(
          beaconId: _beaconId,
          messageId: _messageId,
          userId: _userId,
          newBody: '   ',
        ),
        throwsA(
          isA<BeaconCreateException>().having(
            (e) => e.description,
            'description',
            contains('cannot be empty'),
          ),
        ),
      );
    });

    test(
      'throws BeaconCreateException when new body exceeds max length',
      () async {
        await expectLater(
          sut.editMessage(
            beaconId: _beaconId,
            messageId: _messageId,
            userId: _userId,
            newBody: 'x' * (kMaxRoomMessageBodyLength + 1),
          ),
          throwsA(
            isA<BeaconCreateException>().having(
              (e) => e.description,
              'description',
              contains('too long'),
            ),
          ),
        );
      },
    );
  });

  group('deleteMessage', () {
    test('deletes message for author with room access', () async {
      final ok = await sut.deleteMessage(
        beaconId: _beaconId,
        messageId: _messageId,
        userId: _userId,
      );

      expect(ok, isTrue);
      expect(room.deletedMessageId, _messageId);
    });

    test('throws IdNotFoundException when message is missing', () async {
      room.messageById = null;

      await expectLater(
        sut.deleteMessage(
          beaconId: _beaconId,
          messageId: _messageId,
          userId: _userId,
        ),
        throwsA(isA<IdNotFoundException>()),
      );
    });

    test(
      'throws UnauthorizedException when caller is not the author',
      () async {
        room.participant = testBeaconParticipant(
          beaconId: _beaconId,
          userId: _otherUserId,
          roomAccess: RoomAccessBits.admitted,
        );

        await expectLater(
          sut.deleteMessage(
            beaconId: _beaconId,
            messageId: _messageId,
            userId: _otherUserId,
          ),
          throwsA(
            isA<UnauthorizedException>().having(
              (e) => e.description,
              'description',
              contains('Only the message author can delete'),
            ),
          ),
        );
      },
    );

    test(
      'throws UnauthorizedException when caller lacks room access',
      () async {
        room.participant = testBeaconParticipant(
          beaconId: _beaconId,
          userId: _otherUserId,
          roomAccess: RoomAccessBits.requested,
        );

        await expectLater(
          sut.deleteMessage(
            beaconId: _beaconId,
            messageId: _messageId,
            userId: _otherUserId,
          ),
          throwsA(
            isA<UnauthorizedException>().having(
              (e) => e.description,
              'description',
              contains('Room access required'),
            ),
          ),
        );
      },
    );
  });
}

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
  }) async => true;
}
