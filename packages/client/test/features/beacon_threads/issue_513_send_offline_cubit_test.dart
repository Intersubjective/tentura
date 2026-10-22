import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/exception/generic_exception.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

/// #513: a send that fails because the browser is offline must leave a
/// visible "not sent" state the composer can show (with Retry), instead of
/// only a snackbar. A refusal from the server is not "offline".
void main() {
  group('issue #513 RoomCubit.sendMessage offline state', () {
    test('a connectivity failure marks the send as not sent offline', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      )..createMessageError = const ConnectionUplinkException();
      final cubit = roomCubitForTest(fakeRoom, effects: FakeUiEffectPort());
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      expect(cubit.state.sendFailedOffline, isFalse);

      expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);

      expect(fakeRoom.createMessageCalls, 1);
      expect(cubit.state.sendFailedOffline, isTrue);
    });

    test('a request timeout also marks the send as not sent offline', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom =
          FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId)
            ..createMessageError = TimeoutException(
              'GraphQL request timed out',
              const Duration(seconds: 1),
            );
      final cubit = roomCubitForTest(fakeRoom, effects: FakeUiEffectPort());
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);

      expect(cubit.state.sendFailedOffline, isTrue);
    });

    test('a server refusal is not reported as offline', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom =
          FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId)
            ..createMessageError = const RemoteApiException(
              'Discussion is closed',
              code: '1501',
            );
      final effects = FakeUiEffectPort();
      final cubit = roomCubitForTest(fakeRoom, effects: effects);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);

      expect(cubit.state.sendFailedOffline, isFalse);
      // Today's behaviour for a refusal stays: the error is still surfaced.
      expect(effects.emitted, isNotEmpty);
    });

    test('the next successful send clears the not sent state', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      )..createMessageError = const ConnectionUplinkException();
      final cubit = roomCubitForTest(fakeRoom, effects: FakeUiEffectPort());
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);
      expect(cubit.state.sendFailedOffline, isTrue);

      fakeRoom.createMessageError = null;
      expect(await cubit.sendMessage(body: 'see you at 6'), isTrue);

      expect(fakeRoom.createMessageCalls, 2);
      expect(cubit.state.sendFailedOffline, isFalse);
    });

    test(
      'a refusal after an offline failure clears the offline state',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..createMessageError = const ConnectionUplinkException();
        final cubit = roomCubitForTest(fakeRoom, effects: FakeUiEffectPort());
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);
        expect(cubit.state.sendFailedOffline, isTrue);

        fakeRoom.createMessageError = const RemoteApiException(
          'Discussion is closed',
          code: '1501',
        );
        expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);

        expect(cubit.state.sendFailedOffline, isFalse);
      },
    );
  });
}
