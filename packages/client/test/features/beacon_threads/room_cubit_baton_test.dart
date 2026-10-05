// «Who'll take it?» author actions on `RoomCubit`:
//  - `batonSelect` sends the chosen user id (or null for «Pick for me») for the
//    baton to the repository, then refetches so the card shows the new state;
//  - `batonCancel` sends the cancel for the baton, then refetches;
//  - when the repository fails, the error is surfaced and the card keeps its
//    previous state.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

const _batonId = 'baton-1';

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
    RoomBatonCandidate(
      userId: 'u-clara',
      title: 'Clara Pending',
      tier: 1,
      response: RoomBatonResponse.waiting,
    ),
  ],
  allAnswered: false,
  eligibleCount: 1,
);

/// Serves one message carrying the author's baton, records the author's
/// actions and applies them to the served message like the server would.
class _BatonAuthorRepository extends FakeBeaconThreadsRepository {
  _BatonAuthorRepository({required super.userId});

  final selectCalls = <({String batonId, String? userId})>[];
  final cancelCalls = <String>[];
  Exception? error;

  @override
  Future<RoomBatonData?> batonSelect({
    required String batonId,
    String? userId,
  }) async {
    selectCalls.add((batonId: batonId, userId: userId));
    final failure = error;
    if (failure != null) throw failure;
    final taken = RoomBatonAuthorData(
      id: batonId,
      status: RoomBatonStatus.taken,
      candidates: _collecting.candidates,
      allAnswered: false,
      eligibleCount: 1,
      taker: const RoomBatonTaker(id: 'u-boris', title: 'Boris Driver'),
      selectionMode: userId == null
          ? RoomBatonSelectionMode.auto
          : RoomBatonSelectionMode.manual,
    );
    _serve(taken);
    return taken;
  }

  @override
  Future<bool> batonCancel({required String batonId}) async {
    cancelCalls.add(batonId);
    final failure = error;
    if (failure != null) throw failure;
    _serve(null);
    return true;
  }

  void _serve(RoomBatonData? baton) {
    messages = [
      for (final m in messages)
        RoomMessage(
          id: m.id,
          beaconId: m.beaconId,
          authorId: m.authorId,
          body: m.body,
          createdAt: m.createdAt,
          baton: baton,
        ),
    ];
  }
}

void main() {
  late _BatonAuthorRepository repo;
  late FakeUiEffectPort effects;
  late RoomCubit cubit;

  Future<void> openRoom() async {
    registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
    repo = _BatonAuthorRepository(userId: kRoomCubitFakeMyUserId)
      ..messages = [
        RoomMessage(
          id: 'msg-1',
          beaconId: kRoomCubitFakeBeaconId,
          authorId: kRoomCubitFakeMyUserId,
          body: 'Who can drive?',
          createdAt: DateTime.utc(2026, 10, 3),
          baton: _collecting,
        ),
      ];
    effects = FakeUiEffectPort();
    cubit = roomCubitForTest(repo, effects: effects);
    addTearDown(cubit.close);
    await awaitRoomCubitLoad(cubit);
  }

  RoomBatonData? shownBaton() =>
      cubit.state.messages.firstWhere((m) => m.id == 'msg-1').baton;

  group('RoomCubit.batonSelect', () {
    test('sends the chosen user and shows the taken baton after a '
        'refetch', () async {
      await openRoom();
      final fetchesBefore = repo.fetchMessagesCallCount;

      await cubit.batonSelect(batonId: _batonId, userId: 'u-boris');
      await pumpEventQueue();

      expect(repo.selectCalls, [(batonId: _batonId, userId: 'u-boris')]);
      expect(repo.fetchMessagesCallCount, greaterThan(fetchesBefore));
      final baton = shownBaton();
      expect(baton, isA<RoomBatonAuthorData>());
      expect(baton!.status, RoomBatonStatus.taken);
      expect((baton as RoomBatonAuthorData).taker?.id, 'u-boris');
      expect(effects.emitted, isEmpty);
    });

    test('sends no user id for «Pick for me»', () async {
      await openRoom();
      final fetchesBefore = repo.fetchMessagesCallCount;

      await cubit.batonSelect(batonId: _batonId);
      await pumpEventQueue();

      expect(repo.selectCalls, [(batonId: _batonId, userId: null)]);
      expect(repo.fetchMessagesCallCount, greaterThan(fetchesBefore));
      expect(shownBaton()!.status, RoomBatonStatus.taken);
    });

    test('surfaces the error and keeps the card as it was', () async {
      await openRoom();
      repo.error = Exception('nobody can take it');

      await cubit.batonSelect(batonId: _batonId, userId: 'u-boris');
      await pumpEventQueue();

      expect(repo.selectCalls, [(batonId: _batonId, userId: 'u-boris')]);
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
      expect(shownBaton()!.status, RoomBatonStatus.collecting);
    });
  });

  group('RoomCubit.batonCancel', () {
    test('sends the cancel and refetches the message without a baton', () async {
      await openRoom();
      final fetchesBefore = repo.fetchMessagesCallCount;

      await cubit.batonCancel(batonId: _batonId);
      await pumpEventQueue();

      expect(repo.cancelCalls, [_batonId]);
      expect(repo.fetchMessagesCallCount, greaterThan(fetchesBefore));
      expect(shownBaton(), isNull);
      expect(effects.emitted, isEmpty);
    });

    test('surfaces the error and keeps the card as it was', () async {
      await openRoom();
      repo.error = Exception('offline');

      await cubit.batonCancel(batonId: _batonId);
      await pumpEventQueue();

      expect(repo.cancelCalls, [_batonId]);
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
      expect(shownBaton()!.status, RoomBatonStatus.collecting);
    });
  });
}
