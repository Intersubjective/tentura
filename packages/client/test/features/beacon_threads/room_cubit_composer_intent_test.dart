import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_plan/domain/use_case/beacon_plan_case.dart';
import 'package:tentura/features/beacon_plan/domain/exception/beacon_plan_exceptions.dart';
import 'package:tentura/features/beacon_threads/domain/entity/room_composer_intent.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_plan/beacon_plan_test_support.dart';
import 'room_cubit_fakes.dart';

const _prefill = "› Step 3: Build frame — can't make it: ";

const _cantMake = PlanCantMakeInChat(
  stepId: 'PS000000000003',
  baseRevisionSeq: 4,
);

FakeBeaconPlanRepository _planRepo() =>
    FakeBeaconPlanRepository(BeaconPlan.decode(planJson()));

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
      "sending the quoted message records the plan «can't make it» once",
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        );
        final plan = _planRepo();
        final cubit = roomCubitForTest(fakeRoom, planCase: planCaseFor(plan));
        addTearDown(cubit.close);
        await awaitRoomCubitLoad(cubit);

        cubit.armComposerIntent(
          const RoomComposerIntent(prefill: _prefill, planCantMake: _cantMake),
        );

        // An unrelated message first: the intent keeps waiting.
        expect(await cubit.sendMessage(body: 'hello'), isTrue);
        expect(plan.cantMakeCalls, isEmpty);

        expect(
          await cubit.sendMessage(body: '${_prefill}stuck in traffic'),
          isTrue,
        );
        await Future<void>.delayed(Duration.zero);
        expect(plan.cantMakeCalls, [
          ('PS000000000003', PlanCantMakeOption.chat, null),
        ]);
        expect(plan.cantMakeExcerpts, ['stuck in traffic']);

        // Fired once only.
        expect(await cubit.sendMessage(body: '${_prefill}again'), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(plan.cantMakeCalls, hasLength(1));
      },
    );

    test('an intent without a plan step records nothing', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      final plan = _planRepo();
      final cubit = roomCubitForTest(fakeRoom, planCase: planCaseFor(plan));
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      cubit.armComposerIntent(const RoomComposerIntent(prefill: _prefill));
      expect(await cubit.sendMessage(body: '${_prefill}late'), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(plan.cantMakeCalls, isEmpty);
    });

    test('a failed send keeps the intent armed', () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      )..createMessageError = StateError('network');
      final plan = _planRepo();
      final cubit = roomCubitForTest(fakeRoom, planCase: planCaseFor(plan));
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      cubit.armComposerIntent(
        const RoomComposerIntent(prefill: _prefill, planCantMake: _cantMake),
      );
      expect(await cubit.sendMessage(body: '${_prefill}late'), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(plan.cantMakeCalls, isEmpty);

      fakeRoom.createMessageError = null;
      expect(await cubit.sendMessage(body: '${_prefill}late'), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(plan.cantMakeCalls, hasLength(1));
    });

    test("a refused «can't make it» surfaces as an error", () async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      final plan = _planRepo()
        ..cantMakeError = const PlanActionStaleException();
      final effects = FakeUiEffectPort();
      final cubit = roomCubitForTest(
        fakeRoom,
        planCase: planCaseFor(plan),
        effects: effects,
      );
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);

      cubit.armComposerIntent(
        const RoomComposerIntent(prefill: _prefill, planCantMake: _cantMake),
      );
      expect(await cubit.sendMessage(body: '${_prefill}late'), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(
        effects.emitted.whereType<ShowError>().map((e) => e.error),
        [isA<PlanActionStaleException>()],
      );
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
