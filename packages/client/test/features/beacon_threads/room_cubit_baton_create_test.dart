// «Who'll take it?» start on `RoomCubit.batonCreate`:
//  - sends the message id and `[{userId, tier}]` to the repository, then
//    refetches so the author's card appears on the message;
//  - when the repository fails, the error is surfaced as an effect.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

class _BatonStartRepository extends FakeBeaconThreadsRepository {
  _BatonStartRepository({required super.userId});

  final createCalls =
      <({String messageId, List<({String userId, int tier})> candidates})>[];
  Exception? error;

  @override
  Future<RoomBatonData?> batonCreate({
    required String messageId,
    required List<({String userId, int tier})> candidates,
  }) async {
    createCalls.add((messageId: messageId, candidates: candidates));
    final failure = error;
    if (failure != null) throw failure;
    final started = RoomBatonAuthorData(
      id: 'baton-1',
      status: RoomBatonStatus.collecting,
      candidates: [
        for (final c in candidates)
          RoomBatonCandidate(
            userId: c.userId,
            title: c.userId,
            tier: c.tier,
            response: RoomBatonResponse.waiting,
          ),
      ],
      allAnswered: false,
      eligibleCount: 0,
    );
    messages = [
      for (final m in messages)
        RoomMessage(
          id: m.id,
          beaconId: m.beaconId,
          authorId: m.authorId,
          body: m.body,
          createdAt: m.createdAt,
          baton: m.id == messageId ? started : m.baton,
        ),
    ];
    return started;
  }
}

void main() {
  late _BatonStartRepository repo;
  late FakeUiEffectPort effects;
  late RoomCubit cubit;

  Future<void> openRoom() async {
    registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
    repo = _BatonStartRepository(userId: kRoomCubitFakeMyUserId)
      ..messages = [
        RoomMessage(
          id: 'msg-1',
          beaconId: kRoomCubitFakeBeaconId,
          authorId: kRoomCubitFakeMyUserId,
          body: 'Who can drive?',
          createdAt: DateTime.utc(2026, 10, 3),
        ),
      ];
    effects = FakeUiEffectPort();
    cubit = roomCubitForTest(repo, effects: effects);
    addTearDown(cubit.close);
    await awaitRoomCubitLoad(cubit);
  }

  group('RoomCubit.batonCreate', () {
    test('sends the picked people with their tiers and shows the new '
        'card after a refetch', () async {
      await openRoom();
      final fetchesBefore = repo.fetchMessagesCallCount;

      await cubit.batonCreate(
        messageId: 'msg-1',
        candidates: const [
          (userId: 'u-boris', tier: 1),
          (userId: 'u-clara', tier: 2),
        ],
      );
      await pumpEventQueue();

      expect(repo.createCalls, hasLength(1));
      expect(repo.createCalls.single.messageId, 'msg-1');
      expect(repo.createCalls.single.candidates, [
        (userId: 'u-boris', tier: 1),
        (userId: 'u-clara', tier: 2),
      ]);
      expect(repo.fetchMessagesCallCount, greaterThan(fetchesBefore));
      final baton = cubit.state.messages.single.baton;
      expect(baton, isA<RoomBatonAuthorData>());
      expect(baton!.status, RoomBatonStatus.collecting);
      expect(effects.emitted, isEmpty);
    });

    test('surfaces the error and leaves the message without a baton', () async {
      await openRoom();
      repo.error = Exception('rate limited');

      await cubit.batonCreate(
        messageId: 'msg-1',
        candidates: const [(userId: 'u-boris', tier: 1)],
      );
      await pumpEventQueue();

      expect(repo.createCalls, hasLength(1));
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
      expect(cubit.state.messages.single.baton, isNull);
    });
  });
}
