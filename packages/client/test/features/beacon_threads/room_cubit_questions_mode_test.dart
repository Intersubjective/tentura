import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/entity/room_read_watermark.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

const _kLobbyId = 'lobby-questions-1';

/// The Questions scope as the server serves it to someone who is not in the
/// Request's room: messages, create and seen work; the participant list is
/// refused.
class _QuestionsRepository extends FakeBeaconThreadsRepository {
  _QuestionsRepository() : super(userId: kRoomCubitFakeMyUserId);

  final fetchedThreadItemIds = <String?>[];
  final createdThreadItemIds = <String?>[];
  final seenThreadIds = <String>[];
  int fetchRoomStateCalls = 0;

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) {
    fetchedThreadItemIds.add(threadItemId);
    return super.fetchMessages(
      beaconId: beaconId,
      beforeIso: beforeIso,
      threadItemId: threadItemId,
    );
  }

  @override
  Future<List<BeaconParticipant>> fetchParticipants(String beaconId) async {
    fetchParticipantsCallCount++;
    throw StateError('participants are refused outside the room');
  }

  @override
  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) {
    fetchRoomStateCalls++;
    return super.fetchBeaconRoomState(beaconId);
  }

  @override
  Future<String> createMessage({
    required String beaconId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    RoomPendingUpload? firstAttachment,
    List<String> explicitMentionUserIds = const [],
    List<int> explicitMentionOffsets = const [],
    List<int> explicitMentionLengths = const [],
    String? quotedFactCardId,
    int? quotedFactRevisionSeq,
    String? clientMessageId,
  }) {
    createdThreadItemIds.add(threadItemId);
    return super.createMessage(
      beaconId: beaconId,
      body: body,
      replyToMessageId: replyToMessageId,
      threadItemId: threadItemId,
      firstAttachment: firstAttachment,
      explicitMentionUserIds: explicitMentionUserIds,
      explicitMentionOffsets: explicitMentionOffsets,
      explicitMentionLengths: explicitMentionLengths,
      quotedFactCardId: quotedFactCardId,
      quotedFactRevisionSeq: quotedFactRevisionSeq,
      clientMessageId: clientMessageId,
    );
  }

  @override
  Future<DateTime> markThreadSeen({
    required String beaconId,
    required String threadId,
    required DateTime readThroughAt,
  }) {
    seenThreadIds.add(threadId);
    return super.markThreadSeen(
      beaconId: beaconId,
      threadId: threadId,
      readThroughAt: readThroughAt,
    );
  }
}

class _CountingFactCardRepository extends FakeBeaconFactCardRepository {
  int listCalls = 0;

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) {
    listCalls++;
    return super.list(beaconId: beaconId);
  }
}

RoomMessage _question(String id, DateTime createdAt) => RoomMessage(
  id: id,
  beaconId: kRoomCubitFakeBeaconId,
  authorId: 'asker',
  body: 'How do I get there?',
  createdAt: createdAt,
  threadItemId: _kLobbyId,
);

BeaconLobbyAccess _access({
  bool canPost = true,
  BeaconLobbyLimitReason? limitReason,
}) => BeaconLobbyAccess(
  canRead: true,
  canPost: canPost,
  limitReason: limitReason,
);

({
  RoomCubit cubit,
  _QuestionsRepository repo,
  _CountingFactCardRepository facts,
})
_questionsCubit({
  BeaconLobbyAccess? access,
  List<RoomMessage> messages = const [],
}) {
  registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
  final repo = _QuestionsRepository()..messages = messages;
  final facts = _CountingFactCardRepository();
  final threadsCase = BeaconThreadsCase(
    repo,
    facts,
    FakePollingRepository(),
    FakeBeaconRoomHintsRepository(),
    RoomReadWatermarkStore.testing(),
    buildTestRealtimeSync().case_,
    env: const Env(),
    logger: Logger('test'),
  );
  final cubit = RoomCubit(
    beaconId: kRoomCubitFakeBeaconId,
    threadItemId: _kLobbyId,
    lobbyAccess: access ?? _access(),
    beaconRoomCase: threadsCase,
    coordinationItemRoomSync: CoordinationItemRoomSync(),
    presenceRepository: roomCubitFakePresenceRepository(),
    effects: FakeUiEffectPort(),
  );
  addTearDown(cubit.close);
  return (cubit: cubit, repo: repo, facts: facts);
}

void main() {
  group('RoomCubit Questions mode load', () {
    test(
      'shows the Questions messages for a viewer outside the room',
      () async {
        final t = _questionsCubit(
          messages: [_question('q1', DateTime.utc(2026, 1, 1, 10))],
        );

        final loaded = await awaitRoomCubitLoad(t.cubit);

        expect(loaded.status, isA<StateIsSuccess>());
        expect(loaded.loadError, isNull);
        expect(loaded.messages.map((m) => m.id), ['q1']);
        expect(t.repo.fetchedThreadItemIds, [_kLobbyId]);
      },
    );

    test('asks the server for nothing a non-member is refused', () async {
      final t = _questionsCubit(
        messages: [_question('q1', DateTime.utc(2026, 1, 1, 10))],
      );

      await awaitRoomCubitLoad(t.cubit);
      final fetchesAfterLoad = t.repo.fetchedThreadItemIds.length;
      await t.cubit.reloadMessages(silent: true);

      expect(t.repo.fetchedThreadItemIds.length, greaterThan(fetchesAfterLoad));
      expect(t.repo.fetchedThreadItemIds, everyElement(_kLobbyId));
      expect(t.repo.fetchParticipantsCallCount, 0);
      expect(t.facts.listCalls, 0);
      expect(t.repo.fetchRoomStateCalls, 0);
      expect(t.repo.fetchMainRoomReadWatermarksCallCount, 0);
      expect(t.cubit.state.participants, isEmpty);
      expect(t.cubit.state.factCards, isEmpty);
      expect(t.cubit.state.roomState, isNull);
      expect(t.cubit.state.readWatermarks, <String, RoomReadWatermark>{});
    });
  });

  group('RoomCubit Questions mode send and seen', () {
    test('posts a question into the Questions thread', () async {
      final t = _questionsCubit();
      await awaitRoomCubitLoad(t.cubit);

      expect(await t.cubit.sendMessage(body: 'Is parking free?'), isTrue);

      expect(t.repo.createdThreadItemIds, [_kLobbyId]);
    });

    test('marks the Questions thread as seen, not the room', () async {
      final t = _questionsCubit(
        messages: [_question('q1', DateTime.utc(2026, 1, 1, 10))],
      );
      await awaitRoomCubitLoad(t.cubit);

      await t.cubit.markReadToBottom();

      expect(t.repo.seenThreadIds, [_kLobbyId]);
    });
  });

  group('RoomCubit Questions mode write permission', () {
    test(
      'follows the server canPost on an open Request that denies it',
      () async {
        final t = _questionsCubit(access: _access(canPost: false));
        await awaitRoomCubitLoad(t.cubit);

        t.cubit.syncBeaconStatus(BeaconStatus.open);

        expect(t.cubit.state.canWriteDiscussion, isFalse);
        expect(await t.cubit.sendMessage(body: 'May I ask?'), isFalse);
        expect(t.repo.createMessageCalls, 0);
      },
    );

    test('refuses to send when the server denies posting before the Request '
        'status is known', () async {
      final t = _questionsCubit(access: _access(canPost: false));
      await awaitRoomCubitLoad(t.cubit);

      expect(t.cubit.state.canWriteDiscussion, isFalse);
      expect(await t.cubit.sendMessage(body: 'May I ask?'), isFalse);
      expect(t.repo.createMessageCalls, 0);
    });

    test('allows writing when the server canPost is true', () async {
      final t = _questionsCubit();
      await awaitRoomCubitLoad(t.cubit);

      expect(t.cubit.state.canWriteDiscussion, isTrue);

      t.cubit.syncBeaconStatus(BeaconStatus.open);

      expect(t.cubit.state.canWriteDiscussion, isTrue);
    });
  });
}
