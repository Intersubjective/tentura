import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

/// #513 (QA on 7.41.30): when a send fails on a connection failure, the
/// inline «Not sent — you're offline» notice with Retry is the feedback; the
/// red «No Internet connection» snackbar must not also show on top of it.
/// A refusal from the server, or a request timeout (the message may have
/// posted; Retry could post it twice), still shows the snackbar.
void main() {
  group('issue #513 offline send shows no snackbar', () {
    test(
      'a connection failure shows the inline notice and no snackbar',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..createMessageError = const ConnectionUplinkException();
        final effects = FakeUiEffectPort();
        final cubit = roomCubitForTest(fakeRoom, effects: effects);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);
        effects.clear();

        expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);

        expect(cubit.state.sendFailedOffline, isTrue);
        expect(effects.emitted.whereType<ShowError>(), isEmpty);
      },
    );

    test(
      'a request timeout shows the snackbar, not the offline notice: the '
      'message may have posted, so Retry could post it twice',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom =
            FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId)
              ..createMessageError = TimeoutException(
                'GraphQL request timed out',
                const Duration(seconds: 1),
              );
        final effects = FakeUiEffectPort();
        final cubit = roomCubitForTest(fakeRoom, effects: effects);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);
        effects.clear();

        expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);

        expect(cubit.state.sendFailedOffline, isFalse);
        expect(effects.emitted.whereType<ShowError>(), hasLength(1));
      },
    );

    test('a server refusal still shows the snackbar (guard)', () async {
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
      effects.clear();

      expect(await cubit.sendMessage(body: 'see you at 6'), isFalse);

      expect(cubit.state.sendFailedOffline, isFalse);
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
    });
  });
}
