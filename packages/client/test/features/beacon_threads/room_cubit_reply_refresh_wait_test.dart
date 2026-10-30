import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';

import '../../support/burst_coalescer_test_timing.dart';
import '../../support/test_realtime_sync.dart';
import 'room_cubit_fakes.dart';
import 'room_cubit_reply_refresh_wait.dart';

final _kBaseTime = DateTime.utc(2026, 1, 1, 12);

RoomMessage _roomMsg({
  required String id,
  required DateTime createdAt,
  String body = 'body',
}) {
  return RoomMessage(
    id: id,
    beaconId: kRoomCubitFakeBeaconId,
    authorId: 'other',
    body: body,
    createdAt: createdAt,
    author: Profile(id: 'other', displayName: 'Author other'),
  );
}

Future<void> _awaitCondition(bool Function() condition) async {
  final deadline = DateTime.now().add(burstCoalescerSettleTimeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for room cubit condition.');
}

void main() {
  group('Room reply refresh settled waiter', () {
    test(
      'invalidation path keeps waiter open until reflectsRefreshedSnapshot',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final visible = _roomMsg(
          id: 'visible',
          createdAt: _kBaseTime.add(const Duration(minutes: 5)),
        );
        final pinned = _roomMsg(
          id: 'pin-me',
          createdAt: _kBaseTime,
          body: 'stale pin body',
        );
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..messages = [visible];
        fakeRoom.fetchMessageTargetsById['pin-me'] = pinned;
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);

        await awaitRoomCubitLoad(cubit);
        expect(await cubit.jumpToRepliedMessage('pin-me'), isTrue);

        final edited = pinned.copyWith(body: 'fresh server body');
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) {
            gate.complete();
          }
        });
        fakeRoom
          ..messages = [visible, edited]
          ..fetchMessagesCompleter = gate;
        final expectedFetches = fakeRoom.fetchMessagesCallCount + 1;
        fakeRoom.emitInvalidation(BeaconRoomEntityType.roomMessage);

        bool reflectsEditedPin() => cubit.state.messages.any(
          (message) =>
              message.id == edited.id && message.body == edited.body,
        );

        var settled = false;
        final wait = awaitRoomReplyRefreshSettled(
          room: fakeRoom,
          cubit: cubit,
          expectedFetchCount: expectedFetches,
          reflectsRefreshedSnapshot: reflectsEditedPin,
        ).then((_) => settled = true);
        unawaited(wait);

        await _awaitCondition(
          () => fakeRoom.fetchMessagesCallCount >= expectedFetches,
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(reflectsEditedPin(), isFalse);
        expect(
          settled,
          isFalse,
          reason:
              'awaitRoomReplyRefreshSettled must not complete while '
              'reflectsRefreshedSnapshot is false',
        );

        gate.complete();
        await wait;
        expect(reflectsEditedPin(), isTrue);
      },
    );

    test(
      'catch-up path keeps waiter open until reflectsRefreshedSnapshot',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final realtime = buildTestRealtimeSync();
        addTearDown(realtime.port.dispose);
        final visible = _roomMsg(
          id: 'visible',
          createdAt: _kBaseTime.add(const Duration(minutes: 5)),
        );
        final pinned = _roomMsg(
          id: 'pin-me',
          createdAt: _kBaseTime,
          body: 'stale pin body',
        );
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..messages = [visible];
        fakeRoom.fetchMessageTargetsById['pin-me'] = pinned;
        final cubit = roomCubitForTest(
          fakeRoom,
          realtimeSyncCase: realtime.case_,
        );
        addTearDown(cubit.close);

        await awaitRoomCubitLoad(cubit);
        expect(await cubit.jumpToRepliedMessage('pin-me'), isTrue);

        final edited = pinned.copyWith(body: 'fresh server body');
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) {
            gate.complete();
          }
        });
        fakeRoom
          ..messages = [visible, edited]
          ..fetchMessagesCompleter = gate;
        final expectedFetches = fakeRoom.fetchMessagesCallCount + 1;
        realtime.port.emitCatchUp(connectionEpoch: 2);

        bool reflectsEditedPin() => cubit.state.messages.any(
          (message) =>
              message.id == edited.id && message.body == edited.body,
        );

        var settled = false;
        final wait = awaitRoomReplyRefreshSettled(
          room: fakeRoom,
          cubit: cubit,
          expectedFetchCount: expectedFetches,
          reflectsRefreshedSnapshot: reflectsEditedPin,
        ).then((_) => settled = true);
        unawaited(wait);

        await _awaitCondition(
          () => fakeRoom.fetchMessagesCallCount >= expectedFetches,
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(reflectsEditedPin(), isFalse);
        expect(
          settled,
          isFalse,
          reason:
              'awaitRoomReplyRefreshSettled must not complete while '
              'reflectsRefreshedSnapshot is false',
        );

        gate.complete();
        await wait;
        expect(reflectsEditedPin(), isTrue);
      },
    );
  });
}
