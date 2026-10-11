// «Who'll take it?» start on `RoomCubit.batonCreate`:
//  - sends the room, the ask, the optional reply target and
//    `[{userId, tier}]` to the repository, then refetches so the new baton
//    message appears at the end of the room;
//  - when the repository fails, the error is surfaced as an effect.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

typedef _CreateCall = ({
  String beaconId,
  String text,
  String? replyToMessageId,
  List<({String userId, int tier})> candidates,
});

class _BatonStartRepository extends FakeBeaconThreadsRepository {
  _BatonStartRepository({required super.userId});

  final createCalls = <_CreateCall>[];
  Exception? error;

  @override
  Future<String> batonCreate({
    required String beaconId,
    required String text,
    required List<({String userId, int tier})> candidates,
    String? replyToMessageId,
  }) async {
    createCalls.add((
      beaconId: beaconId,
      text: text,
      replyToMessageId: replyToMessageId,
      candidates: candidates,
    ));
    final failure = error;
    if (failure != null) throw failure;
    messages = [
      ...messages,
      RoomMessage(
        id: 'msg-baton',
        beaconId: beaconId,
        authorId: kRoomCubitFakeMyUserId,
        body: text,
        createdAt: DateTime.utc(2026, 10, 3, 1),
        semanticMarker: BeaconRoomSemanticMarker.baton,
        replyToMessageId: replyToMessageId,
        baton: RoomBatonAuthorData(
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
        ),
      ),
    ];
    return 'msg-baton';
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
    test('posts the ask as a reply with the picked people and their tiers, '
        'and shows the new message at the end after a refetch', () async {
      await openRoom();
      final fetchesBefore = repo.fetchMessagesCallCount;

      await cubit.batonCreate(
        text: 'Friday, 9:00',
        replyToMessageId: 'msg-1',
        candidates: const [
          (userId: 'u-boris', tier: 1),
          (userId: 'u-clara', tier: 2),
        ],
      );
      await pumpEventQueue();

      expect(repo.createCalls, hasLength(1));
      final call = repo.createCalls.single;
      expect(call.beaconId, kRoomCubitFakeBeaconId);
      expect(call.text, 'Friday, 9:00');
      expect(call.replyToMessageId, 'msg-1');
      expect(call.candidates, [
        (userId: 'u-boris', tier: 1),
        (userId: 'u-clara', tier: 2),
      ]);
      expect(repo.fetchMessagesCallCount, greaterThan(fetchesBefore));
      // The source message is untouched; the baton is a new last message.
      expect(cubit.state.messages.first.baton, isNull);
      final last = cubit.state.messages.last;
      expect(last.id, 'msg-baton');
      expect(last.replyToMessageId, 'msg-1');
      expect(last.baton, isA<RoomBatonAuthorData>());
      expect(effects.emitted, isEmpty);
    });

    test('posts a standalone ask without a reply target', () async {
      await openRoom();

      await cubit.batonCreate(
        text: 'Who can drive?',
        candidates: const [(userId: 'u-boris', tier: 1)],
      );
      await pumpEventQueue();

      expect(repo.createCalls.single.replyToMessageId, isNull);
      expect(cubit.state.messages.last.baton, isA<RoomBatonAuthorData>());
    });

    test('surfaces the error and posts nothing', () async {
      await openRoom();
      repo.error = Exception('rate limited');

      await cubit.batonCreate(
        text: 'Who can drive?',
        candidates: const [(userId: 'u-boris', tier: 1)],
      );
      await pumpEventQueue();

      expect(repo.createCalls, hasLength(1));
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
      expect(cubit.state.messages.single.baton, isNull);
    });
  });
}
