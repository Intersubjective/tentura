// tentura-fpi landing gate acceptance (chat read receipts / room_seen_peer)

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/realtime/realtime_seen_peer.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_read_watermark.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'room_cubit_fakes.dart';

final _kAnchorTime = DateTime.utc(2026, 1, 1, 12);
final _kOlderWatermark = _kAnchorTime;
final _kNewerWatermark = _kAnchorTime.add(const Duration(hours: 2));

RoomMessage _msg(String id, DateTime createdAt, {String authorId = 'other'}) =>
    RoomMessage(
      id: id,
      beaconId: kRoomCubitFakeBeaconId,
      authorId: authorId,
      body: '',
      createdAt: createdAt,
    );

RoomReadWatermark _watermark(String userId, DateTime lastSeenAt) =>
    RoomReadWatermark(userId: userId, lastSeenAt: lastSeenAt);

Map<String, RoomReadWatermark> _readWatermarks(RoomState state) =>
    state.readWatermarks;

bool _readWatermarksLoaded(RoomState state) => state.readWatermarksLoaded;

Future<void> _pump() => Future<void>.delayed(Duration.zero);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

Future<void> _awaitPeerHandlerSettled(
  FakeBeaconThreadsRepository fakeRoom, {
  required int baselineMessages,
  required int baselineParticipants,
}) async {
  final deadline = DateTime.now().add(const Duration(milliseconds: 500));
  while (DateTime.now().isBefore(deadline)) {
    await _pump();
    if (fakeRoom.fetchMessagesCallCount > baselineMessages ||
        fakeRoom.fetchParticipantsCallCount > baselineParticipants) {
      return;
    }
  }
}

void _expectNoPeerRefetch(
  FakeBeaconThreadsRepository fakeRoom, {
  required int baselineMessages,
  required int baselineParticipants,
}) {
  expect(
    fakeRoom.fetchMessagesCallCount,
    baselineMessages,
    reason: 'roomSeenPeer must not refetch messages',
  );
  expect(
    fakeRoom.fetchParticipantsCallCount,
    baselineParticipants,
    reason: 'roomSeenPeer must not refetch participants',
  );
}

void _emitSeenPeer(
  FakeBeaconThreadsRepository fakeRoom, {
  required String userId,
  required DateTime lastSeenAt,
}) {
  fakeRoom.emitInvalidation(
    BeaconRoomEntityType.roomSeenPeer,
    seenPeer: RealtimeSeenPeer(userId: userId, lastSeenAt: lastSeenAt),
  );
}

void main() {
  group('RoomCubit read watermarks (tentura-1hg)', () {
    test(
      'full load populates readWatermarks by userId and sets readWatermarksLoaded',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);

        final peerA = _watermark('peer-a', _kAnchorTime);
        final peerB = _watermark(
          'peer-b',
          _kAnchorTime.add(const Duration(minutes: 5)),
        );
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )
          ..messages = [_msg('m1', _kAnchorTime)]
          ..mainRoomReadWatermarks = [peerA, peerB];
        addTearDown(fakeRoom.dispose);

        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);

        final state = await awaitRoomCubitLoad(cubit);

        expect(fakeRoom.fetchMainRoomReadWatermarksCallCount, 1);
        expect(_readWatermarksLoaded(state), isTrue);
        expect(_readWatermarks(state), hasLength(2));
        expect(
          _readWatermarks(state)['peer-a']?.lastSeenAt,
          peerA.lastSeenAt,
        );
        expect(
          _readWatermarks(state)['peer-b']?.lastSeenAt,
          peerB.lastSeenAt,
        );
      },
    );

    test(
      'author without participant row seeds own anchor from read watermark',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);

        final watermarkTime = _kAnchorTime.add(const Duration(hours: 1));
        final watermarkStore = RoomReadWatermarkStore.testing();
        addTearDown(watermarkStore.dispose);

        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )
          ..participants = const <BeaconParticipant>[]
          ..mainRoomReadWatermarks = [
            _watermark(kRoomCubitFakeMyUserId, watermarkTime),
          ]
          ..messages = [
            _msg(
              'before',
              watermarkTime.subtract(const Duration(minutes: 1)),
            ),
            _msg('after', watermarkTime.add(const Duration(minutes: 1))),
          ];
        addTearDown(fakeRoom.dispose);

        final case_ = roomCubitMakeCase(
          fakeRoom,
          watermarkStore: watermarkStore,
        );
        final cubit = roomCubitForTest(
          fakeRoom,
          beaconRoomCase: case_,
        );
        addTearDown(cubit.close);

        final state = await awaitRoomCubitLoad(cubit);

        expect(
          watermarkStore.syncedAt(kRoomCubitFakeBeaconId),
          watermarkTime,
          reason: 'observeServerReadThrough seeds from viewer watermark',
        );
        expect(state.unreadAnchorAt, watermarkTime);
        expect(state.unreadCount, 1, reason: 'only messages after anchor');
        expect(state.firstUnreadMessageId, 'after');
      },
    );

    test(
      'watermark fetch failure is non-fatal and leaves readWatermarksLoaded false',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);

        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )
          ..fetchMainRoomReadWatermarksError = StateError('watermark offline')
          ..messages = [_msg('stable', _kAnchorTime)]
          ..participants = [
            BeaconParticipant(
              id: 'p-viewer',
              beaconId: kRoomCubitFakeBeaconId,
              userId: kRoomCubitFakeMyUserId,
              role: 0,
              status: 0,
              roomAccess: 1,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          ];
        addTearDown(fakeRoom.dispose);

        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);

        final state = await awaitRoomCubitLoad(cubit);

        expect(fakeRoom.fetchMainRoomReadWatermarksCallCount, 1);
        expect(state.messages.single.id, 'stable');
        expect(state.participants, hasLength(1));
        expect(state.status, isA<StateIsSuccess>());
        expect(_readWatermarksLoaded(state), isFalse);
        expect(_readWatermarks(state), isEmpty);
      },
    );

    test(
      'full refresh keeps newer in-state watermark when fetch returns older value',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);

        const peerUserId = 'peer-u';
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )
          ..messages = [_msg('m1', _kAnchorTime)]
          ..mainRoomReadWatermarks = [
            _watermark(peerUserId, _kNewerWatermark),
          ];
        addTearDown(fakeRoom.dispose);

        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);

        final initial = await awaitRoomCubitLoad(cubit);
        expect(
          _readWatermarks(initial)[peerUserId]?.lastSeenAt,
          _kNewerWatermark,
        );

        fakeRoom.mainRoomReadWatermarks = [
          _watermark(peerUserId, _kOlderWatermark),
        ];
        await cubit.reloadMessages(silent: true);

        expect(
          _readWatermarks(cubit.state)[peerUserId]?.lastSeenAt,
          _kNewerWatermark,
          reason: 'merge must not regress peer watermark',
        );
        expect(_readWatermarksLoaded(cubit.state), isTrue);
      },
    );
  });

  group('RoomCubit roomSeenPeer read watermarks (tentura-s54)', () {
    test(
      'roomSeenPeer invalidation patches readWatermarks without refetch',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);

        const peerUserId = 'peer-seen';
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )
          ..messages = [_msg('m1', _kAnchorTime)]
          ..mainRoomReadWatermarks = [
            _watermark(peerUserId, _kOlderWatermark),
          ];
        addTearDown(fakeRoom.dispose);

        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);

        await awaitRoomCubitLoad(cubit);
        final messagesAfterLoad = fakeRoom.fetchMessagesCallCount;
        final participantsAfterLoad = fakeRoom.fetchParticipantsCallCount;

        _emitSeenPeer(
          fakeRoom,
          userId: peerUserId,
          lastSeenAt: _kNewerWatermark,
        );
        await _awaitPeerHandlerSettled(
          fakeRoom,
          baselineMessages: messagesAfterLoad,
          baselineParticipants: participantsAfterLoad,
        );

        expect(
          _readWatermarks(cubit.state)[peerUserId]?.lastSeenAt,
          _kNewerWatermark,
        );
        _expectNoPeerRefetch(
          fakeRoom,
          baselineMessages: messagesAfterLoad,
          baselineParticipants: participantsAfterLoad,
        );
      },
    );

    test(
      'older roomSeenPeer frame leaves newer watermark and emits no state',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);

        const peerUserId = 'peer-stale';
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )
          ..messages = [_msg('m1', _kAnchorTime)]
          ..mainRoomReadWatermarks = [
            _watermark(peerUserId, _kNewerWatermark),
          ];
        addTearDown(fakeRoom.dispose);

        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);

        await awaitRoomCubitLoad(cubit);
        final messagesAfterLoad = fakeRoom.fetchMessagesCallCount;
        final participantsAfterLoad = fakeRoom.fetchParticipantsCallCount;
        var emissions = 0;
        final sub = cubit.stream.listen((_) => emissions++);
        addTearDown(sub.cancel);

        _emitSeenPeer(
          fakeRoom,
          userId: peerUserId,
          lastSeenAt: _kOlderWatermark,
        );
        await _awaitPeerHandlerSettled(
          fakeRoom,
          baselineMessages: messagesAfterLoad,
          baselineParticipants: participantsAfterLoad,
        );

        expect(
          _readWatermarks(cubit.state)[peerUserId]?.lastSeenAt,
          _kNewerWatermark,
          reason: 'older peer frame must not regress watermark',
        );
        _expectNoPeerRefetch(
          fakeRoom,
          baselineMessages: messagesAfterLoad,
          baselineParticipants: participantsAfterLoad,
        );
        expect(emissions, 0, reason: 'stale peer frame must not emit');
      },
    );

    test('identical roomSeenPeer frame emits nothing', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);

      const peerUserId = 'peer-same';
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      )
        ..messages = [_msg('m1', _kAnchorTime)]
        ..mainRoomReadWatermarks = [
          _watermark(peerUserId, _kNewerWatermark),
        ];
      addTearDown(fakeRoom.dispose);

      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      final messagesAfterLoad = fakeRoom.fetchMessagesCallCount;
      final participantsAfterLoad = fakeRoom.fetchParticipantsCallCount;
      var emissions = 0;
      final sub = cubit.stream.listen((_) => emissions++);
      addTearDown(sub.cancel);

      _emitSeenPeer(
        fakeRoom,
        userId: peerUserId,
        lastSeenAt: _kNewerWatermark,
      );
      await _awaitPeerHandlerSettled(
        fakeRoom,
        baselineMessages: messagesAfterLoad,
        baselineParticipants: participantsAfterLoad,
      );

      _expectNoPeerRefetch(
        fakeRoom,
        baselineMessages: messagesAfterLoad,
        baselineParticipants: participantsAfterLoad,
      );
      expect(emissions, 0, reason: 'duplicate peer frame must not emit');
    });

    test(
      'roomSeenPeer frame before initial load survives load merge',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);

        const peerUserId = 'peer-preload';
        final preloadWatermark = _kAnchorTime.add(const Duration(hours: 3));
        final loadGate = Completer<void>();
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )
          ..messages = [_msg('m1', _kAnchorTime)]
          ..fetchMessagesCompleter = loadGate
          ..mainRoomReadWatermarks = [
            _watermark(peerUserId, _kOlderWatermark),
          ];
        addTearDown(fakeRoom.dispose);

        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);

        _emitSeenPeer(
          fakeRoom,
          userId: peerUserId,
          lastSeenAt: preloadWatermark,
        );
        await _pump();
        loadGate.complete();
        final state = await awaitRoomCubitLoad(cubit);

        expect(
          _readWatermarks(state)[peerUserId]?.lastSeenAt,
          preloadWatermark,
          reason: 'pre-load peer patch must survive initial fetch merge',
        );
        expect(_readWatermarksLoaded(state), isTrue);
      },
    );

    test('roomSeenPeer for viewer id patches own read watermark', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);

      final viewerWatermark = _kAnchorTime.add(const Duration(hours: 4));
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      )
        ..messages = [_msg('m1', _kAnchorTime)]
        ..mainRoomReadWatermarks = [
          _watermark(kRoomCubitFakeMyUserId, _kOlderWatermark),
        ];
      addTearDown(fakeRoom.dispose);

      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);

      _emitSeenPeer(
        fakeRoom,
        userId: kRoomCubitFakeMyUserId,
        lastSeenAt: viewerWatermark,
      );
      await _settle();

      expect(
        _readWatermarks(cubit.state)[kRoomCubitFakeMyUserId]?.lastSeenAt,
        viewerWatermark,
        reason: 'viewer peer frame must update own watermark entry',
      );
    });

    test(
      'roomSeenPeer during in-flight full refresh survives terminal emit',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);

        const peerUserId = 'peer-inflight';
        final inflightWatermark = _kAnchorTime.add(const Duration(hours: 5));
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )
          ..messages = [_msg('m1', _kAnchorTime)]
          ..mainRoomReadWatermarks = [
            _watermark(peerUserId, _kOlderWatermark),
          ];
        addTearDown(fakeRoom.dispose);

        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        final messagesGate = Completer<void>();
        final participantsGate = Completer<void>();
        fakeRoom
          ..fetchMessagesCompleter = messagesGate
          ..fetchParticipantsCompleter = participantsGate
          ..mainRoomReadWatermarks = [
            _watermark(peerUserId, _kOlderWatermark),
          ];
        fakeRoom.emitInvalidation(BeaconRoomEntityType.participant);
        await _pump();
        expect(fakeRoom.fetchMessagesCallCount, greaterThan(1));

        _emitSeenPeer(
          fakeRoom,
          userId: peerUserId,
          lastSeenAt: inflightWatermark,
        );
        await _pump();
        expect(
          _readWatermarks(cubit.state)[peerUserId]?.lastSeenAt,
          inflightWatermark,
          reason: 'peer patch should land before refresh completes',
        );

        messagesGate.complete();
        await _pump();
        participantsGate.complete();
        await _settle();

        expect(
          _readWatermarks(cubit.state)[peerUserId]?.lastSeenAt,
          inflightWatermark,
          reason: 'in-flight peer patch must survive full refresh merge',
        );
      },
    );

    test(
      'roomSeenPeer for unknown user adds watermark with default profile fields',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);

        const unknownUserId = 'peer-unknown';
        final unknownWatermark = _kAnchorTime.add(const Duration(hours: 6));
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..messages = [_msg('m1', _kAnchorTime)];
        addTearDown(fakeRoom.dispose);

        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);

        await awaitRoomCubitLoad(cubit);
        expect(_readWatermarks(cubit.state), isNot(contains(unknownUserId)));

        _emitSeenPeer(
          fakeRoom,
          userId: unknownUserId,
          lastSeenAt: unknownWatermark,
        );
        await _settle();

        final entry = _readWatermarks(cubit.state)[unknownUserId];
        expect(entry, isNotNull);
        expect(entry!.lastSeenAt, unknownWatermark);
        expect(entry.userTitle, '');
        expect(entry.userHasPicture, isFalse);
        expect(entry.userImageId, '');
        expect(entry.userBlurHash, '');
        expect(entry.userPicHeight, 0);
        expect(entry.userPicWidth, 0);
      },
    );
  });
}
