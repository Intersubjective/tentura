import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_threads/domain/entity/room_composer_intent.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';

import 'room_cubit_fakes.dart';

const _prefill = "› Step 3: Build frame — can't make it: ";

void main() {
  group('RoomComposerIntent', () {
    const intent = RoomComposerIntent(prefill: _prefill);

    test('matches only a body that still starts with the quote', () {
      expect(intent.matches('$_prefill traffic on the bridge'), isTrue);
      expect(intent.matches('  ${_prefill.trim()}'), isTrue);
      expect(intent.matches('something else'), isFalse);
      expect(
        const RoomComposerIntent(prefill: '  ').matches('anything'),
        isFalse,
      );
    });

    test('wordsOf strips the quote, keeps the body when nothing follows', () {
      expect(
        intent.wordsOf('$_prefill traffic on the bridge'),
        'traffic on the bridge',
      );
      expect(intent.wordsOf(_prefill), _prefill.trim());
      expect(intent.wordsOf('unrelated'), 'unrelated');
    });
  });

  group('RoomCubit composer intent (plan «Не успеваю», #220)', () {
    test('arming puts the prefill into state once per request', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      cubit.armComposerIntent(const RoomComposerIntent(prefill: _prefill));
      expect(cubit.state.composerPrefill, _prefill);
      final seq = cubit.state.composerPrefillSeq;
      expect(seq, greaterThan(0));

      cubit.clearComposerPrefill();
      expect(cubit.state.composerPrefill, isNull);
      expect(cubit.state.composerPrefillSeq, seq);
    });

    test(
      'sending the quoted message fires onSent once with the body',
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        );
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        final sent = <String>[];
        cubit.armComposerIntent(
          RoomComposerIntent(
            prefill: _prefill,
            onSent: (body) async => sent.add(body),
          ),
        );

        // An unrelated message first: the intent keeps waiting.
        expect(await cubit.sendMessage(body: 'hello'), isTrue);
        expect(sent, isEmpty);

        expect(
          await cubit.sendMessage(body: '${_prefill}stuck in traffic'),
          isTrue,
        );
        await Future<void>.delayed(Duration.zero);
        expect(sent, ['${_prefill}stuck in traffic'.trim()]);

        // Fired once only.
        expect(await cubit.sendMessage(body: '${_prefill}again'), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(sent, hasLength(1));
      },
    );

    test('a failed send keeps the intent armed', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      )..createMessageError = StateError('network');
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      final sent = <String>[];
      cubit.armComposerIntent(
        RoomComposerIntent(
          prefill: _prefill,
          onSent: (body) async => sent.add(body),
        ),
      );
      expect(await cubit.sendMessage(body: '${_prefill}late'), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(sent, isEmpty);

      fakeRoom.createMessageError = null;
      expect(await cubit.sendMessage(body: '${_prefill}late'), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(1));
    });
  });

  group('ThreadHostCubit.armComposerIntent', () {
    test('holds the intent until the General room exists', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      final host = ThreadHostCubit(
        beaconId: kRoomCubitFakeBeaconId,
        roomCubitFactory:
            ({
              required beaconId,
              threadItemId,
              initialUnreadAnchorAt,
              capabilities = const RoomCapabilities.request(),
            }) => roomCubitForTest(fakeRoom),
      );
      addTearDown(host.close);

      host.armComposerIntent(const RoomComposerIntent(prefill: _prefill));
      expect(host.roomCubit, isNull);

      await host.select(
        const RequestThread(
          threadId: RequestThread.generalId,
          kind: RequestThreadKind.general,
        ),
      );
      expect(host.roomCubit?.state.composerPrefill, _prefill);
    });
  });
}
