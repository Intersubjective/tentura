// Baton together: when the author picks a confirmed pair, the pick's result
// carries both people (taker A, co-taker X) and the single plan-step offer is
// still assigned to the taker. A solo pick has no co-taker.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';

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

const _takenPair = RoomBatonAuthorData(
  id: _batonId,
  status: RoomBatonStatus.taken,
  candidates: [],
  allAnswered: true,
  eligibleCount: 1,
  taker: RoomBatonTaker(id: 'u-boris', title: 'Boris Driver'),
  coTaker: RoomBatonTaker(id: 'u-xenia', title: 'Xenia Partner'),
  selectionMode: RoomBatonSelectionMode.manual,
);

const _takenSolo = RoomBatonAuthorData(
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

  /// What the server answers; [_takenPair] by default.
  RoomBatonData? answer = _takenPair;

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
  late RoomCubit cubit;

  Future<void> openRoom() async {
    registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
    repo = _Repository(userId: kRoomCubitFakeMyUserId)
      ..messages = [
        RoomMessage(
          id: 'msg-1',
          beaconId: kRoomCubitFakeBeaconId,
          authorId: kRoomCubitFakeMyUserId,
          body: 'Bring straps',
          createdAt: DateTime.utc(2026, 10, 3),
          baton: _collecting,
        ),
      ];
    planRepo = FakeBeaconPlanRepository(
      BeaconPlan.decode(planJson()),
    );
    cubit = roomCubitForTest(
      repo,
      effects: FakeUiEffectPort(),
      planCase: planCaseFor(planRepo),
      newPlanStepId: () => _stepId,
    );
    addTearDown(cubit.close);
    await awaitRoomCubitLoad(cubit);
  }

  group('batonSelect for a pair', () {
    test('returns the taker and the co-taker, offering one step for the '
        'taker', () async {
      await openRoom();

      final result = await cubit.batonSelect(
        batonId: _batonId,
        userId: 'u-boris',
      );

      expect(result, isA<BatonSelected>());
      final selected = result as BatonSelected;
      expect(selected.taker?.id, 'u-boris');
      final coTaker = selected.coTaker;
      expect(coTaker?.id, 'u-xenia');
      expect(coTaker?.title, 'Xenia Partner');
      expect(selected.planStepOffer?.assigneeId, 'u-boris');
    });

    test('a solo pick has no co-taker', () async {
      await openRoom();
      repo.answer = _takenSolo;

      final result = await cubit.batonSelect(
        batonId: _batonId,
        userId: 'u-boris',
      );

      final selected = result as BatonSelected;
      expect(selected.taker?.id, 'u-boris');
      expect(selected.coTaker, isNull);
    });
  });
}
