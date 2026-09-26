import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../support/fake_beacon_hierarchy_repository.dart';

import 'package:tentura_server/domain/entity/beacon_room_record.dart';
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

import '../../support/coordination_item_record_fixtures.dart';
import '../../support/test_attention_harness.dart';
import '../../support/fake_user_block_repository.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';

const _beaconId = 'Baaaaaaaaaaaa';
const _userId = 'Uaaaaaaaaaaaa';
const _messageId = 'Raaaaaaaaaaaa';
const _factId = 'Faaaaaaaaaaaa';
const Object _notPassed = Object();

class _StubItems extends Fake implements CoordinationItemRepositoryPort {}

class _StubRoom extends Fake implements BeaconRoomRepositoryPort {
  BeaconParticipantRecord? participant;
  BeaconRoomMessageRecord? messageById;

  int insertCalls = 0;
  String? insertedBody;
  String? insertedQuotedFactCardId;
  int? insertedQuotedFactRevisionSeq;
  int updateCalls = 0;
  String? updatedBody;

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async => false;

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async => false;

  @override
  Future<BeaconParticipantRecord?> findParticipant({
    required String beaconId,
    required String userId,
  }) async => participant;

  @override
  Future<String?> beaconAuthorUserId(String beaconId) async => null;

  @override
  Future<int> countRecentMessagesByAuthor({
    required String authorId,
    required Duration window,
  }) async => 0;

  @override
  Future<List<AdmittedRoomMentionParticipant>> listAdmittedMentionParticipants(
    String beaconId,
  ) async => const [];

  @override
  Future<List<String>> resolveMentionUserIdsForBeacon({
    required String beaconId,
    required String body,
  }) async => const [];

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
    List<Map<String, Object?>> mentionSpans = const [],
    String? quotedFactCardId,
    int? quotedFactRevisionSeq,
  }) async {
    insertCalls++;
    insertedBody = body;
    insertedQuotedFactCardId = quotedFactCardId;
    insertedQuotedFactRevisionSeq = quotedFactRevisionSeq;
    return BeaconRoomMessageRecord(
      id: _messageId,
      beaconId: beaconId,
      authorId: authorId,
      body: body,
      createdAt: DateTime.utc(2026),
      quotedFactCardId: quotedFactCardId,
      quotedFactRevisionSeq: quotedFactRevisionSeq,
    );
  }

  @override
  Future<BeaconRoomMessageRecord?> getRoomMessageById(String id) async =>
      messageById;

  /// Every named argument the case passed to [updateMessage]. Extra optional
  /// quote parameters (absent from the port) default to [_notPassed], so a
  /// case that tried to rewrite the quote through this call would show up.
  Map<String, Object?>? updateArgs;

  @override
  Future<void> updateMessage({
    required String messageId,
    required String newBody,
    required List<String> mentions,
    required List<Map<String, Object?>> mentionSpans,
    Object? quotedFactCardId = _notPassed,
    Object? quotedFactRevisionSeq = _notPassed,
  }) async {
    updateCalls++;
    updatedBody = newBody;
    updateArgs = {
      'messageId': messageId,
      'newBody': newBody,
      'mentions': mentions,
      'mentionSpans': mentionSpans,
      if (!identical(quotedFactCardId, _notPassed))
        'quotedFactCardId': quotedFactCardId,
      if (!identical(quotedFactRevisionSeq, _notPassed))
        'quotedFactRevisionSeq': quotedFactRevisionSeq,
    };
    // Mirror the repository contract: only body/mentions/editedAt change; the
    // quote columns are carried over from the stored row.
    final old = messageById!;
    messageById = BeaconRoomMessageRecord(
      id: old.id,
      beaconId: old.beaconId,
      authorId: old.authorId,
      body: newBody,
      createdAt: old.createdAt,
      editedAt: DateTime.utc(2026, 2),
      mentions: mentions,
      mentionSpans: mentionSpans,
      quotedFactCardId: old.quotedFactCardId,
      quotedFactRevisionSeq: old.quotedFactRevisionSeq,
    );
  }
}

/// tentura-617.16 (issue #181 plan §8.5, §8.11): `RoomMessageCreate` may carry
/// a quoted fact snapshot (`quotedFactCardId` + `quotedFactRevisionSeq`, both
/// or neither). A quote alone is enough content; the empty-body guard becomes
/// 'Message text, attachment or quoted fact required'. Editing a message only
/// rewrites body/mentions, so the quote survives.
void main() {
  late _StubRoom room;
  late BeaconRoomCase sut;

  setUp(() {
    room = _StubRoom()
      ..participant = testBeaconParticipant(
        beaconId: _beaconId,
        userId: _userId,
      );
    final attention = TestAttentionHarness();
    sut = BeaconRoomCase(
      room,
      _StubItems(),
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
      attentionIntents: attention.intents,
      attention: attention.transactional,
      env: Env(environment: Environment.test),
      logger: Logger('BeaconRoomCaseQuoteTest'),
    );
  });

  group('createMessage with a quoted fact', () {
    test(
      'empty body + quote is accepted and forwards both quote args',
      () async {
        final out = await sut.createMessage(
          beaconId: _beaconId,
          userId: _userId,
          body: '   ',
          quotedFactCardId: _factId,
          quotedFactRevisionSeq: 2,
        );

        expect(out['id'], _messageId);
        expect(room.insertCalls, 1);
        expect(room.insertedBody, '');
        expect(room.insertedQuotedFactCardId, _factId);
        expect(room.insertedQuotedFactRevisionSeq, 2);
      },
    );

    test(
      'text + quote forwards the trimmed body and both quote args',
      () async {
        await sut.createMessage(
          beaconId: _beaconId,
          userId: _userId,
          body: '  about this  ',
          quotedFactCardId: _factId,
          quotedFactRevisionSeq: 1,
        );

        expect(room.insertedBody, 'about this');
        expect(room.insertedQuotedFactCardId, _factId);
        expect(room.insertedQuotedFactRevisionSeq, 1);
      },
    );

    test('no quote leaves both quote args null on insert', () async {
      await sut.createMessage(
        beaconId: _beaconId,
        userId: _userId,
        body: 'plain',
      );

      expect(room.insertCalls, 1);
      expect(room.insertedQuotedFactCardId, isNull);
      expect(room.insertedQuotedFactRevisionSeq, isNull);
    });

    test(
      'empty body, no attachment, no quote → BeaconCreateException with the '
      'new message',
      () async {
        await expectLater(
          sut.createMessage(beaconId: _beaconId, userId: _userId, body: '  '),
          throwsA(
            isA<BeaconCreateException>().having(
              (e) => e.description,
              'description',
              equals('Message text, attachment or quoted fact required'),
            ),
          ),
        );
        expect(room.insertCalls, 0);
      },
    );

    Future<Object> rejection(Future<Object?> Function() attempt) async {
      try {
        await attempt();
      } on Object catch (e) {
        return e;
      }
      fail('a half quote must be rejected');
    }

    test('only quotedFactCardId (no seq) is rejected before insert', () async {
      final error = await rejection(
        () => sut.createMessage(
          beaconId: _beaconId,
          userId: _userId,
          body: 'half a quote',
          quotedFactCardId: _factId,
        ),
      );
      expect(error, isA<ExceptionBase>());
      expect(room.insertCalls, 0);
    });

    test(
      'only quotedFactRevisionSeq (no card id) is rejected before insert',
      () async {
        final error = await rejection(
          () => sut.createMessage(
            beaconId: _beaconId,
            userId: _userId,
            body: 'half a quote',
            quotedFactRevisionSeq: 1,
          ),
        );
        expect(error, isA<ExceptionBase>());
        expect(room.insertCalls, 0);
      },
    );

    test(
      'both one-sided quotes are rejected the same way (both-or-neither pair '
      'rule, not per-argument handling)',
      () async {
        final cardOnly = await rejection(
          () => sut.createMessage(
            beaconId: _beaconId,
            userId: _userId,
            body: 'half a quote',
            quotedFactCardId: _factId,
          ),
        );
        final seqOnly = await rejection(
          () => sut.createMessage(
            beaconId: _beaconId,
            userId: _userId,
            body: 'half a quote',
            quotedFactRevisionSeq: 1,
          ),
        );
        expect(cardOnly, isA<ExceptionBase>());
        expect(seqOnly.runtimeType, cardOnly.runtimeType);
        expect(room.insertCalls, 0);
      },
    );
  });

  group('editMessage on a quoted message', () {
    test('rewrites only the body; the quote is kept', () async {
      room.messageById = BeaconRoomMessageRecord(
        id: _messageId,
        beaconId: _beaconId,
        authorId: _userId,
        body: 'original',
        createdAt: DateTime.utc(2026),
        quotedFactCardId: _factId,
        quotedFactRevisionSeq: 3,
      );

      final ok = await sut.editMessage(
        beaconId: _beaconId,
        messageId: _messageId,
        userId: _userId,
        newBody: '  edited  ',
      );

      expect(ok, isTrue);
      expect(room.updateCalls, 1);
      expect(room.insertCalls, 0);
      // The case may only ask the port to change body and mentions; no quote
      // argument is passed to updateMessage at all.
      expect(room.updateArgs, {
        'messageId': _messageId,
        'newBody': 'edited',
        'mentions': const <String>[],
        'mentionSpans': const <Map<String, Object?>>[],
      });
      final stored = await room.getRoomMessageById(_messageId);
      expect(stored!.body, 'edited');
      expect(stored.quotedFactCardId, _factId);
      expect(stored.quotedFactRevisionSeq, 3);
    });
  });
}

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
  }) async => true;
}
