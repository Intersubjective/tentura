import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/message/discussion_read_only_message.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

void main() {
  group('RoomCubit discussion write guard', () {
    test('sendMessage no-ops when closed without calling repository', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      final effects = FakeUiEffectPort();
      final cubit = roomCubitForTest(fakeRoom, effects: effects);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      cubit.syncBeaconStatus(BeaconStatus.closed);
      final before = cubit.state.messages.length;

      expect(await cubit.sendMessage(body: 'hello'), isFalse);
      expect(fakeRoom.createMessageCalls, 0);
      expect(cubit.state.messages.length, before);
      expect(
        effects.emitted.whereType<ShowMessage>().single.message,
        isA<DiscussionReadOnlyMessage>(),
      );
    });

    test('sendMessage still works when status null (server decides)', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      expect(cubit.state.beaconStatus, isNull);

      expect(await cubit.sendMessage(body: 'hello'), isTrue);
      expect(fakeRoom.createMessageCalls, 1);
    });

    test('syncBeaconStatus clears replyTarget when locking', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final target = RoomMessage(
        id: 'msg-target',
        beaconId: kRoomCubitFakeBeaconId,
        authorId: 'other',
        body: 'quoted',
        createdAt: DateTime.utc(2026),
      );
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      )..messages = [target];
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      cubit.syncBeaconStatus(BeaconStatus.open);
      cubit.startReplyTo(target);
      expect(cubit.state.replyTarget?.id, target.id);

      cubit.syncBeaconStatus(BeaconStatus.closed);
      expect(cubit.state.replyTarget, isNull);
      expect(cubit.state.canWriteDiscussion, isFalse);
    });

    test('reviewOpen remains writable', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      cubit.syncBeaconStatus(BeaconStatus.reviewOpen);

      expect(await cubit.sendMessage(body: 'still ok'), isTrue);
      expect(fakeRoom.createMessageCalls, 1);
    });
  });
}
