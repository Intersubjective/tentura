import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

void main() {
  group('RoomCubit.sendMessage', () {
    test('returns false for blank input with no uploads', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId);
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);

      expect(await cubit.sendMessage(body: '   '), isFalse);
      expect(fakeRoom.createMessageCalls, 0);
    });

    test('returns true on success', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId);
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);

      expect(await cubit.sendMessage(body: 'hello'), isTrue);
      expect(fakeRoom.createMessageCalls, 1);
    });

    test('passes replyToMessageId after startReplyTo', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final target = RoomMessage(
        id: 'msg-target',
        beaconId: kRoomCubitFakeBeaconId,
        authorId: 'other',
        body: 'quoted',
        createdAt: DateTime.utc(2026),
      );
      final fakeRoom = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [target];
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      cubit.startReplyTo(target);

      expect(await cubit.sendMessage(body: 'reply body'), isTrue);
      expect(fakeRoom.createMessageCalls, 1);
      expect(fakeRoom.lastReplyToMessageId, target.id);
    });

    test('returns false when use case throws before message is created', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId)
        ..createMessageError = StateError('network');
      final effects = FakeUiEffectPort();
      final cubit = roomCubitForTest(fakeRoom, effects: effects);
      addTearDown(cubit.close);

      await awaitRoomCubitLoad(cubit);
      final beforeCount = cubit.state.messages.length;

      expect(await cubit.sendMessage(body: 'hello'), isFalse);
      expect(fakeRoom.createMessageCalls, 1);
      expect(fakeRoom.addAttachmentCalls, 0);
      expect(cubit.state.messages.length, beforeCount);
      expect(effects.emitted, isNotEmpty);
    });

    test(
      'returns false when extra attachment fails after create succeeds',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId)
          ..addAttachmentError = StateError('upload failed');
        final effects = FakeUiEffectPort();
        final cubit = roomCubitForTest(fakeRoom, effects: effects);
        addTearDown(cubit.close);

        await awaitRoomCubitLoad(cubit);
        final beforeCount = cubit.state.messages.length;

        expect(
          await cubit.sendMessage(
            body: 'two files',
            uploads: [
              roomCubitFakeUpload('a.png'),
              roomCubitFakeUpload('b.png'),
            ],
          ),
          isFalse,
        );
        expect(fakeRoom.createMessageCalls, 1);
        expect(fakeRoom.addAttachmentCalls, 1);
        expect(cubit.state.messages.length, beforeCount);
        expect(effects.emitted, isNotEmpty);
      },
    );
  });
}
