import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';

import '../../support/burst_coalescer_test_timing.dart';
import '../../support/test_realtime_sync.dart';
import 'room_cubit_fakes.dart';

RoomMessage _message(String id, int minute) => RoomMessage(
  id: id,
  beaconId: kRoomCubitFakeBeaconId,
  authorId: 'other',
  author: const Profile(id: 'other', displayName: 'Another participant'),
  body: 'Reply $id',
  createdAt: DateTime.utc(2026, 1, 1, 12, minute),
);

class _MessageLinkRepository extends FakeBeaconThreadsRepository {
  _MessageLinkRepository() : super(userId: kRoomCubitFakeMyUserId) {
    messages = [_message('visible', 1)];
    fetchMessageTargetsById['old'] = _message('old', 0);
  }

  final lookedUpIds = <String>[];

  @override
  Future<RoomMessage?> fetchMessageTarget({
    required String beaconId,
    required String messageId,
  }) {
    lookedUpIds.add(messageId);
    return super.fetchMessageTarget(beaconId: beaconId, messageId: messageId);
  }
}

Iterable<String> _messageIds(RoomCubit room) =>
    room.state.messages.map((message) => message.id);

Future<void> _openOlderReply(RoomCubit room) async {
  expect(_messageIds(room), isNot(contains('old')));
  final scrollRequested = room.stream
      .firstWhere((state) => state.scrollToMessageId == 'old')
      .timeout(burstCoalescerSettleTimeout);
  room.prepareThreadScroll(messageId: 'old');
  await scrollRequested;
  expect(_messageIds(room), contains('old'));
}

enum _Refresh { messageInvalidation, reload, realtimeCatchUp }

void main() {
  group('Room message links', () {
    setUp(() => registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId));

    test(
      'only a linked reply outside the first page is looked up and pinned',
      () async {
        final repo = _MessageLinkRepository()
          ..messages = [_message('visible', 1), _message('recent', 2)];
        final room = roomCubitForTest(repo);
        addTearDown(room.close);
        await awaitRoomCubitLoad(room).timeout(burstCoalescerSettleTimeout);

        expect(_messageIds(room), ['visible', 'recent']);
        room.prepareThreadScroll(messageId: 'recent');
        expect(room.state.scrollToMessageId, 'recent');
        expect(room.state.pinnedJumpMessageIds, isNot(contains('recent')));
        expect(repo.lookedUpIds, isEmpty);
        room.clearScrollToMessageTarget();

        await _openOlderReply(room);
        expect(room.state.scrollToMessageId, 'old');
        expect(repo.lookedUpIds, ['old']);
        expect(room.state.pinnedJumpMessageIds, ['old']);
      },
    );

    for (final (refresh, description) in [
      (_Refresh.messageInvalidation, 'a room-message invalidation'),
      (_Refresh.reload, 'a silent room reload'),
      (_Refresh.realtimeCatchUp, 'a realtime catch-up'),
    ]) {
      test(
        '$description retains the linked reply without requesting a second scroll',
        () async {
          final repo = _MessageLinkRepository();
          final realtime = buildTestRealtimeSync();
          addTearDown(realtime.port.dispose);
          final room = roomCubitForTest(repo, realtimeSyncCase: realtime.case_);
          addTearDown(room.close);
          await awaitRoomCubitLoad(room).timeout(burstCoalescerSettleTimeout);
          await _openOlderReply(room);
          room.clearScrollToMessageTarget();
          expect(room.state.scrollToMessageId, isNull);

          // Keep the same page membership but observe a changed row so the
          // assertions run only after the refreshed page has reached the cubit.
          const refreshedBody = 'Edited visible reply';
          repo.messages = [repo.messages.single.copyWith(body: refreshedBody)];
          final refreshed = room.stream
              .firstWhere(
                (state) => state.messages.any(
                  (message) =>
                      message.id == 'visible' && message.body == refreshedBody,
                ),
              )
              .timeout(burstCoalescerSettleTimeout);
          final repeatedScrolls = <String>[];
          final subscription = room.stream.listen((state) {
            if (state.scrollToMessageId case final id?) repeatedScrolls.add(id);
          });
          addTearDown(subscription.cancel);
          switch (refresh) {
            case _Refresh.messageInvalidation:
              repo.emitInvalidation(BeaconRoomEntityType.roomMessage);
            case _Refresh.reload:
              await room.reloadMessages(silent: true);
            case _Refresh.realtimeCatchUp:
              realtime.port.emitCatchUp();
          }
          await refreshed;

          expect(room.state.scrollToMessageId, isNull);
          expect(repeatedScrolls, isEmpty);
          expect(
            {
              'loaded messages': _messageIds(room),
              'pinned messages': room.state.pinnedJumpMessageIds,
            },
            {
              'loaded messages': ['old', 'visible'],
              'pinned messages': ['old'],
            },
          );
        },
      );
    }

    test(
      'reopening the chat without the link drops the pinned reply',
      () async {
        final repo = _MessageLinkRepository();
        final linkedRoom = roomCubitForTest(repo);
        addTearDown(() async {
          if (!linkedRoom.isClosed) await linkedRoom.close();
        });
        await awaitRoomCubitLoad(
          linkedRoom,
        ).timeout(burstCoalescerSettleTimeout);
        await _openOlderReply(linkedRoom);
        final pinsBeforeLeaving = linkedRoom.state.pinnedJumpMessageIds;
        await linkedRoom.close();

        final reopenedRoom = roomCubitForTest(repo);
        addTearDown(reopenedRoom.close);
        await awaitRoomCubitLoad(
          reopenedRoom,
        ).timeout(burstCoalescerSettleTimeout);

        expect(_messageIds(reopenedRoom), ['visible']);
        expect(reopenedRoom.state.pinnedJumpMessageIds, isEmpty);
        expect(pinsBeforeLeaving, ['old']);
      },
    );
  });
}
