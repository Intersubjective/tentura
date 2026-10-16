import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

void main() {
  group('RoomCubit.createPoll', () {
    test('returns true when the server takes the poll', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      final created = await cubit.createPoll(
        question: 'When?',
        variants: ['Mon', 'Tue'],
      );

      expect(created, isTrue);
      expect(fakeRoom.createPollCalls, 1);
    });

    test('returns false and shows the error when the server says no, '
        'so the sheet keeps the draft', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      )..createPollError = Exception('Poll options must be distinct');
      final effects = FakeUiEffectPort();
      final cubit = roomCubitForTest(fakeRoom, effects: effects);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      final created = await cubit.createPoll(
        question: 'When?',
        variants: ['Mon', 'mon'],
      );

      expect(created, isFalse);
      expect(fakeRoom.createPollCalls, 1);
      expect(effects.emitted.whereType<ShowError>(), isNotEmpty);
    });

    test('returns false without calling the server when the discussion is '
        'read-only', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
      cubit.syncBeaconStatus(BeaconStatus.closed);

      final created = await cubit.createPoll(
        question: 'When?',
        variants: ['Mon', 'Tue'],
      );

      expect(created, isFalse);
      expect(fakeRoom.createPollCalls, 0);
    });
  });
}
