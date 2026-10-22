// #479 (D9): after the author picks who takes a «Who'll take it?» ask, the
// pick's result offers «Create a plan step with {name}?»:
//  - only for a pick that went through with a resolved taker, on a Request
//    whose plan the author may edit; never after a failed pick;
//  - prefilled from the ask, with a step id minted once per offer;
//  - a failed save can be retried with the same step id, and a departed
//    taker is reported;
//  - a realtime refresh of the taken card never produces another offer.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/domain/exception/beacon_plan_exceptions.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/message/baton_plan_step_messages.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_plan/beacon_plan_test_support.dart';
import 'room_cubit_fakes.dart';

const _batonId = 'baton-1';
const _stepId = 'PS0000000000aa';

const _collecting = RoomBatonAuthorData(
  id: _batonId,
  status: RoomBatonStatus.collecting,
  candidates: [
    RoomBatonCandidate(
      userId: 'u-boris',
      title: 'Boris Driver',
      tier: 1,
      response: RoomBatonResponse.canHelp,
    ),
  ],
  allAnswered: true,
  eligibleCount: 1,
);

const _taken = RoomBatonAuthorData(
  id: _batonId,
  status: RoomBatonStatus.taken,
  candidates: [],
  allAnswered: true,
  eligibleCount: 1,
  taker: RoomBatonTaker(id: 'u-boris', title: 'Boris Driver'),
  selectionMode: RoomBatonSelectionMode.manual,
);

class _Repository extends FakeBeaconThreadsRepository {
  _Repository({required super.userId});

  Exception? error;

  /// What the server answers; [_taken] by default.
  RoomBatonData? answer = _taken;

  @override
  Future<RoomBatonData?> batonSelect({
    required String batonId,
    String? userId,
  }) async {
    final failure = error;
    if (failure != null) throw failure;
    messages = [
      for (final m in messages)
        RoomMessage(
          id: m.id,
          beaconId: m.beaconId,
          authorId: m.authorId,
          body: m.body,
          createdAt: m.createdAt,
          baton: answer,
        ),
    ];
    return answer;
  }
}

void main() {
  late _Repository repo;
  late FakeBeaconPlanRepository planRepo;
  late FakeUiEffectPort effects;
  late RoomCubit cubit;
  late int minted;

  Future<void> openRoom({
    bool editable = true,
    String body = 'Bring straps',
  }) async {
    registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
    repo = _Repository(userId: kRoomCubitFakeMyUserId)
      ..messages = [
        RoomMessage(
          id: 'msg-1',
          beaconId: kRoomCubitFakeBeaconId,
          authorId: kRoomCubitFakeMyUserId,
          body: body,
          createdAt: DateTime.utc(2026, 10, 3),
          baton: _collecting,
        ),
      ];
    planRepo = FakeBeaconPlanRepository(
      BeaconPlan.decode(planJson(editable: editable)),
    );
    effects = FakeUiEffectPort();
    minted = 0;
    cubit = roomCubitForTest(
      repo,
      effects: effects,
      planCase: planCaseFor(planRepo),
      newPlanStepId: () {
        minted++;
        return _stepId;
      },
    );
    addTearDown(cubit.close);
    await awaitRoomCubitLoad(cubit);
  }

  group('batonSelect result', () {
    test('offers a plan step for the resolved taker, prefilled from the '
        'ask', () async {
      await openRoom();

      final result = await cubit.batonSelect(
        batonId: _batonId,
        userId: 'u-boris',
      );

      expect(result, isA<BatonSelected>());
      final selected = result as BatonSelected;
      expect(selected.taker?.id, 'u-boris');
      final offer = selected.planStepOffer!;
      expect(offer.beaconId, kRoomCubitFakeBeaconId);
      expect(offer.batonId, _batonId);
      expect(offer.stepId, _stepId);
      expect(offer.assigneeId, 'u-boris');
      expect(offer.assigneeName, 'Boris Driver');
      expect(offer.title, 'Bring straps');
      expect(planRepo.saveCalls, isEmpty, reason: 'no automatic step');
    });

    test(
      '«Pick for me» offers the step for whoever the server chose',
      () async {
        await openRoom();

        final result = await cubit.batonSelect(batonId: _batonId);

        expect(
          (result as BatonSelected).planStepOffer?.assigneeId,
          'u-boris',
        );
      },
    );

    test('a failed pick offers nothing and reads no plan', () async {
      await openRoom();
      repo.error = Exception('nobody can take it');

      final result = await cubit.batonSelect(
        batonId: _batonId,
        userId: 'u-boris',
      );

      expect(result, isA<BatonSelectFailed>());
      expect(planRepo.fetchCount, 0);
      expect(minted, 0);
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
    });

    test('an answer without a taker offers nothing', () async {
      await openRoom();
      repo.answer = null;

      final result = await cubit.batonSelect(batonId: _batonId);

      expect(result, isA<BatonSelected>());
      expect((result as BatonSelected).planStepOffer, isNull);
      expect(planRepo.fetchCount, 0);
    });

    test('no offer when the author may not edit the plan', () async {
      await openRoom(editable: false);

      final result = await cubit.batonSelect(
        batonId: _batonId,
        userId: 'u-boris',
      );

      expect((result as BatonSelected).planStepOffer, isNull);
      expect(minted, 0);
    });

    test('a long ask is cut to the step title limit', () async {
      await openRoom(body: 'x' * 300);

      final result = await cubit.batonSelect(
        batonId: _batonId,
        userId: 'u-boris',
      );

      expect((result as BatonSelected).planStepOffer!.title, 'x' * 120);
    });

    test('a realtime refresh of the taken card makes no new offer', () async {
      await openRoom();
      await cubit.batonSelect(batonId: _batonId, userId: 'u-boris');
      final fetches = planRepo.fetchCount;

      repo.emitInvalidation(BeaconRoomEntityType.roomBaton);
      await pumpEventQueue();
      repo.emitInvalidation(BeaconRoomEntityType.roomMessage);
      await pumpEventQueue();

      expect(minted, 1, reason: 'one offer, from the pick only');
      expect(planRepo.fetchCount, fetches);
    });
  });

  group('createBatonPlanStep', () {
    Future<BatonPlanStepOffer> offer() async {
      await openRoom();
      final result = await cubit.batonSelect(
        batonId: _batonId,
        userId: 'u-boris',
      );
      return (result as BatonSelected).planStepOffer!;
    }

    test('appends the step to the plan, assigned to the taker', () async {
      final o = await offer();

      final ok = await cubit.createBatonPlanStep(o, title: ' Bring 4 straps ');

      expect(ok, isTrue);
      final saved = planRepo.saveCalls.single.$2;
      final step = saved[_stepId]!;
      expect(step.title, 'Bring 4 straps');
      expect(step.assigneeId, 'u-boris');
      expect(saved.length, 5, reason: 'the four steps plus the new one');
      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<BatonPlanStepCreatedMessage>()),
      );
    });

    test('a failed save can be retried with the same step id', () async {
      final o = await offer();
      planRepo.saveErrors.add(const PlanRateLimitedException());

      final first = await cubit.createBatonPlanStep(o, title: 'Bring straps');
      final second = await cubit.createBatonPlanStep(o, title: 'Bring straps');

      expect(first, isFalse);
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
      expect(second, isTrue);
      expect(planRepo.saveCalls, hasLength(2));
      expect(
        planRepo.saveCalls.map((c) => c.$2.ids.where((id) => id == _stepId)),
        everyElement(hasLength(1)),
      );
      expect(minted, 1);
    });

    test('a taker who left the discussion is reported', () async {
      final o = await offer();
      planRepo.saveErrors.add(const PlanAssigneeNotAdmittedException());

      final ok = await cubit.createBatonPlanStep(o, title: 'Bring straps');

      expect(ok, isFalse);
      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        contains(isA<BatonPlanStepAssigneeLeftMessage>()),
      );
    });

    test('an empty title saves nothing', () async {
      final o = await offer();

      expect(await cubit.createBatonPlanStep(o, title: '   '), isFalse);
      expect(planRepo.saveCalls, isEmpty);
    });
  });
}
