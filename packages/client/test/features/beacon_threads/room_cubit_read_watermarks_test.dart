import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_read_watermark.dart';
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
    (state as dynamic).readWatermarks as Map<String, RoomReadWatermark>;

bool _readWatermarksLoaded(RoomState state) =>
    (state as dynamic).readWatermarksLoaded as bool;

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
}
