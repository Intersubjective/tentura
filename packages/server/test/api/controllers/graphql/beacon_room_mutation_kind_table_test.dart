import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/mutation/mutation_beacon_room.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/beacon_not_request_matcher.dart';
import '../../../support/beacon_repository_ctor_arg.dart';
import '../../../support/fake_beacon_hierarchy_repository.dart';
import '../../../support/fake_user_block_repository.dart';
import '../../../support/test_attention_harness.dart';

const _beaconId = 'Bpostroom0001';
const _messageId = 'Rpostroom0001';
const _userId = 'Upostroomusr1';
const _otherUserId = 'Upostroomusr2';

/// Every room mutation, classified by whether it also works in a Post's room.
///
/// `true`: the author and addressees of a Post keep using it (messages,
/// reactions, attachments, polls, read marks). `false`: Request-only — the
/// room use case rejects a Post with `BeaconNotRequestException` (wire code
/// 1321) before it writes anything.
///
/// Adding a mutation to `MutationBeaconRoom.all` without classifying it, and
/// without a use-case probe in [_probes], fails the first test below. Thread
/// listing is a query rather than a mutation, so it has no row here.
const _postAllowedByMutation = <String, bool>{
  'RoomMessageCreate': true,
  'RoomMessageAttachmentAdd': true,
  'RoomMessageEdit': true,
  'RoomMessageDelete': true,
  'RoomMessageReactionToggle': true,
  'MarkThreadSeen': true,
  'RoomPollCreate': true,
  'BeaconParticipantOfferHelp': false,
  'BeaconRoomAdmit': false,
  'BeaconStewardPromote': false,
  'RoomMessageMarkSemanticDone': false,
  'BeaconRoomNowLineUpdate': false,
};

/// The classification the product requires, spelled out independently of the
/// table above so a wrong flip in either place fails.
const _requiredPostAllowed = {
  'RoomMessageCreate',
  'RoomMessageAttachmentAdd',
  'RoomMessageEdit',
  'RoomMessageDelete',
  'RoomMessageReactionToggle',
  'MarkThreadSeen',
  'RoomPollCreate',
};

const _requiredRequestOnly = {
  'BeaconParticipantOfferHelp',
  'BeaconRoomAdmit',
  'BeaconStewardPromote',
  'RoomMessageMarkSemanticDone',
  'BeaconRoomNowLineUpdate',
};

/// Calls the use-case method behind each mutation, for a Post room.
final _probes = <String, Future<Object?> Function(BeaconRoomCase)>{
  'RoomMessageCreate': (c) =>
      c.createMessage(beaconId: _beaconId, userId: _userId, body: 'hello'),
  'RoomMessageAttachmentAdd': (c) => c.addMessageAttachment(
    beaconId: _beaconId,
    userId: _userId,
    messageId: _messageId,
    attachmentBytes: Stream.value(Uint8List.fromList([1, 2, 3])),
    attachmentFilename: 'photo.png',
    attachmentMimeType: 'image/png',
  ),
  'RoomMessageEdit': (c) => c.editMessage(
    beaconId: _beaconId,
    messageId: _messageId,
    userId: _userId,
    newBody: 'edited',
  ),
  'RoomMessageDelete': (c) => c.deleteMessage(
    beaconId: _beaconId,
    messageId: _messageId,
    userId: _userId,
  ),
  'RoomMessageReactionToggle': (c) => c.reactionToggle(
    beaconId: _beaconId,
    messageId: _messageId,
    userId: _userId,
    emoji: '👍',
  ),
  'MarkThreadSeen': (c) => c.markThreadSeen(
    beaconId: _beaconId,
    userId: _userId,
    threadId: 'general',
  ),
  'RoomPollCreate': (c) => c.createPoll(
    beaconId: _beaconId,
    userId: _userId,
    question: 'Which day?',
    variants: const ['Mon', 'Tue'],
  ),
  'BeaconParticipantOfferHelp': (c) =>
      c.offerHelp(beaconId: _beaconId, userId: _otherUserId, note: 'I can'),
  'BeaconRoomAdmit': (c) => c.admit(
    beaconId: _beaconId,
    participantUserId: _otherUserId,
    actorUserId: _userId,
  ),
  'BeaconStewardPromote': (c) => c.stewardPromote(
    beaconId: _beaconId,
    stewardUserId: _otherUserId,
    authorUserId: _userId,
  ),
  'RoomMessageMarkSemanticDone': (c) => c.roomMessageMarkSemanticDone(
    beaconId: _beaconId,
    userId: _userId,
    messageId: _messageId,
  ),
  'BeaconRoomNowLineUpdate': (c) =>
      c.updateRoomNowLine(beaconId: _beaconId, userId: _userId, text: 'Now'),
};

final _now = DateTime.utc(2026);

/// Serves one Post and nothing else.
class _PostBeaconRepo extends Fake implements BeaconRepositoryPort {
  final _post = BeaconEntity(
    id: _beaconId,
    title: '',
    author: const UserEntity(id: _userId),
    createdAt: _now,
    updatedAt: _now,
    kind: BeaconKind.post,
  );

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async => _post;

  @override
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  }) => fn(_post);
}

/// A room where the caller is the author and the message exists, recording
/// the room writes a Request-only mutation must not reach for a Post.
class _PostRoom extends Fake implements BeaconRoomRepositoryPort {
  final writes = <String>[];

  @override
  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async => userId == _userId;

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) async => false;

  @override
  Future<BeaconParticipantRecord?> findParticipant({
    required String beaconId,
    required String userId,
  }) async => null;

  @override
  Future<String?> beaconAuthorUserId(String beaconId) async => _userId;

  @override
  Future<BeaconRoomMessageRecord?> getRoomMessageById(String messageId) async =>
      _message;

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
  }) async => _message;

  @override
  Future<void> updateMessage({
    required String messageId,
    required String newBody,
    required List<String> mentions,
    required List<Map<String, Object?>> mentionSpans,
  }) async {}

  @override
  Future<void> deleteRoomMessage({required String messageId}) async {}

  @override
  Future<bool> toggleReaction({
    required String messageId,
    required String userId,
    required String emoji,
  }) async => true;

  @override
  Future<DateTime?> latestMainRoomMessageCreatedAt(String beaconId) async =>
      null;

  @override
  Future<DateTime?> getMainRoomLastSeen({
    required String beaconId,
    required String userId,
  }) async => null;

  @override
  Future<DateTime> markBeaconRoomSeen({
    required String userId,
    required String beaconId,
    required String? threadItemId,
    required DateTime at,
  }) async => at;

  @override
  Future<int> countAttachmentsForMessage(String messageId) async => 0;

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
  }) async {}

  @override
  Future<Map<String, Object?>> insertAndEnrichPollMessage({
    required String beaconId,
    required String authorId,
    required String linkedPollingId,
    required String viewerUserId,
  }) async => {'id': _messageId, 'beaconId': beaconId};

  @override
  Future<void> participantOfferHelp({
    required String beaconId,
    required String userId,
    required String note,
  }) async => writes.add('participantOfferHelp');

  @override
  Future<void> admitParticipant({
    required String beaconId,
    required String participantUserId,
    required String actorUserId,
    String admissionReason = 'admit',
  }) async => writes.add('admitParticipant');

  @override
  Future<void> setBeaconSteward({
    required String beaconId,
    required String stewardUserId,
    required String authorUserId,
  }) async => writes.add('setBeaconSteward');

  @override
  Future<void> markRoomMessageSemanticDone({
    required String messageId,
    required String actingUserId,
  }) async => writes.add('markRoomMessageSemanticDone');

  @override
  Future<void> setBeaconRoomCurrentLine({
    required String beaconId,
    required String text,
    required String updatedBy,
  }) async => writes.add('setBeaconRoomCurrentLine');
}

final _message = BeaconRoomMessageRecord(
  id: _messageId,
  beaconId: _beaconId,
  authorId: _userId,
  body: 'hello',
  createdAt: _now,
);

class _UnusedItems extends Fake implements CoordinationItemRepositoryPort {}

class _UnusedFacts extends Fake implements BeaconFactCardRepositoryPort {}

class _StubImages extends Fake implements ImageRepositoryPort {
  @override
  Future<String> put({
    required String authorId,
    required Stream<Uint8List> bytes,
  }) async => 'Iimage000001';
}

class _StubTasks extends Fake implements TaskRepositoryPort {
  @override
  Future<String> schedule(TaskEntity task) async => 'Ttask0000001';
}

class _UnusedStorage extends Fake implements RemoteStoragePort {}

class _StubPolling extends Fake implements PollingRepositoryPort {
  @override
  Future<String> createWithVariants({
    required String authorId,
    required String question,
    required List<String> variants,
    String pollType = 'single',
    bool isAnonymous = true,
    bool allowRevote = true,
  }) async => 'Ppoll00000001';
}

class _UnusedQuota extends Fake implements UploadQuotaRepositoryPort {}

void main() {
  group('room mutation kind classification', () {
    test('names every room mutation exactly once and probes each', () {
      final registered = MutationBeaconRoom(
        beaconRoomCase: _UnusedRoomCase(),
      ).all.map((f) => f.name).toList();

      expect(registered, hasLength(registered.toSet().length));
      expect(
        _postAllowedByMutation.keys.toSet(),
        registered.toSet(),
        reason:
            'classify new room mutations in _postAllowedByMutation: '
            'missing = ${registered.toSet().difference(_postAllowedByMutation.keys.toSet())}, '
            'stale = ${_postAllowedByMutation.keys.toSet().difference(registered.toSet())}',
      );
      expect(_probes.keys.toSet(), registered.toSet());
    });

    test('classifies messages, reactions, attachments, polls and read marks '
        'as Post-allowed', () {
      final postAllowed = {
        for (final e in _postAllowedByMutation.entries)
          if (e.value) e.key,
      };

      expect(postAllowed, _requiredPostAllowed);
    });

    test('classifies offer, admission, steward, semantic-done and now-line '
        'mutations as Request-only', () {
      final requestOnly = {
        for (final e in _postAllowedByMutation.entries)
          if (!e.value) e.key,
      };

      expect(requestOnly, _requiredRequestOnly);
    });
  });

  group('BeaconRoomCase in a Post room', () {
    late _PostRoom room;
    late BeaconRoomCase roomCase;

    setUp(() {
      room = _PostRoom();
      final attention = TestAttentionHarness();
      roomCase = buildWithBeaconRepository<BeaconRoomCase>(
        BeaconRoomCase.new,
        positional: [
          room,
          _UnusedItems(),
          _UnusedFacts(),
          _StubImages(),
          _StubTasks(),
          _UnusedStorage(),
          _StubPolling(),
          _UnusedQuota(),
          FakeUserBlockRepository(),
          PassThroughMutatingUnitOfWork(),
          FakeBeaconHierarchyRepository(),
          const ProductionDiscussionProductPolicy(),
        ],
        named: {
          #attentionIntents: attention.intents,
          #attention: attention.transactional,
          #env: Env(environment: Environment.test),
          #logger: Logger('BeaconRoomMutationKindTableTest'),
        },
        beaconRepository: _PostBeaconRepo(),
      );
    });

    for (final name in _requiredRequestOnly) {
      test('$name rejects a Post before writing', () async {
        await expectLater(_probes[name]!(roomCase), throwsBeaconNotRequest);

        expect(room.writes, isEmpty);
      });
    }

    for (final name in _requiredPostAllowed) {
      test('$name still works in a Post room', () async {
        await expectLater(_probes[name]!(roomCase), completes);
      });
    }
  });
}

class _UnusedRoomCase extends Fake implements BeaconRoomCase {}
