// #1173 split (PR-CU), observable pins for two RoomCubit cleanups:
// - e780937bd: a failed reaction toggle shows the error snack exactly once,
//   after rolling back the optimistic reaction when there was one.
// - f348731ef: BeaconThreadsCase.createMessage now takes the committed
//   mentions and splits them into the wire lists itself; RoomCubit sends
//   the same explicit-mention user ids / offsets / lengths as before.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

class _RecordingRepository extends FakeBeaconThreadsRepository {
  _RecordingRepository() : super(userId: kRoomCubitFakeMyUserId);

  StateError? reactionError;
  int reactionCalls = 0;
  List<String>? mentionUserIds;
  List<int>? mentionOffsets;
  List<int>? mentionLengths;

  @override
  Future<bool> toggleReaction({
    required String beaconId,
    required String messageId,
    required String emoji,
  }) async {
    reactionCalls++;
    final error = reactionError;
    if (error != null) throw error;
    return true;
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
    mentionUserIds = explicitMentionUserIds;
    mentionOffsets = explicitMentionOffsets;
    mentionLengths = explicitMentionLengths;
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
}

RoomMessage _message(String id) => RoomMessage(
  id: id,
  beaconId: kRoomCubitFakeBeaconId,
  authorId: 'other-user',
  body: 'hello',
  createdAt: DateTime.utc(2026),
);

void main() {
  group('toggleReaction failure', () {
    test(
      'a known message rolls back and shows the error exactly once',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final failure = StateError('reaction failed');
        final repository = _RecordingRepository()
          ..messages = [_message('m1')]
          ..reactionError = failure;
        final effects = FakeUiEffectPort();
        final cubit = roomCubitForTest(repository, effects: effects);
        addTearDown(repository.dispose);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);
        final before = cubit.state.messages.singleWhere((m) => m.id == 'm1');

        await cubit.toggleReaction(messageId: 'm1', emoji: '👍');

        expect(repository.reactionCalls, 1);
        final errors = effects.emitted.whereType<ShowError>().toList();
        expect(errors, hasLength(1));
        expect(errors.single.error, same(failure));
        expect(
          cubit.state.messages.singleWhere((m) => m.id == 'm1'),
          before,
          reason: 'the optimistic reaction is rolled back',
        );
      },
    );

    test('a message not in the list (no rollback) still shows the error '
        'exactly once', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final repository = _RecordingRepository()
        ..messages = [_message('m1')]
        ..reactionError = StateError('reaction failed');
      final effects = FakeUiEffectPort();
      final cubit = roomCubitForTest(repository, effects: effects);
      addTearDown(repository.dispose);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
      final before = cubit.state.messages;

      await cubit.toggleReaction(messageId: 'not-loaded', emoji: '👍');

      expect(repository.reactionCalls, 1);
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
      expect(cubit.state.messages, before);
    });
  });

  group('sendMessage explicit mentions on the wire', () {
    test('user ids, offsets and lengths are split from the committed '
        'mentions, shifted past trimmed leading whitespace', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final repository = _RecordingRepository();
      final cubit = roomCubitForTest(repository, effects: FakeUiEffectPort());
      addTearDown(repository.dispose);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      // "  hi @Ann and @Bob  ": two leading spaces are trimmed off.
      const body = '  hi @Ann and @Bob  ';
      final sent = await cubit.sendMessage(
        body: body,
        explicitMentions: const [
          (userId: 'Uann', start: 5, end: 9),
          (userId: 'Ubob', start: 14, end: 18),
          // Inside the trimmed trailing whitespace: dropped.
          (userId: 'Ughost', start: 18, end: 20),
        ],
      );

      expect(sent, isTrue);
      expect(repository.createMessageCalls, 1);
      expect(repository.mentionUserIds, ['Uann', 'Ubob']);
      expect(repository.mentionOffsets, [3, 12]);
      expect(repository.mentionLengths, [4, 4]);
    });

    test('no mentions sends three empty lists', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final repository = _RecordingRepository();
      final cubit = roomCubitForTest(repository, effects: FakeUiEffectPort());
      addTearDown(repository.dispose);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      expect(await cubit.sendMessage(body: 'plain'), isTrue);

      expect(repository.mentionUserIds, isEmpty);
      expect(repository.mentionOffsets, isEmpty);
      expect(repository.mentionLengths, isEmpty);
    });
  });
}
