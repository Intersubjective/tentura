// #379: the request author has no beacon_participant row (the server only
// inserts helper / addressee rows), so RoomState.isPlanEditor never saw them
// and RoomCubit.updatePlan refused every save with "Request is not open."
// (DiscussionPlanUpdateBlockedMessage), even in Wrapping up where the server
// accepts it (updateRoomNowLine: allowsCoordination + author). The author is
// passed in with the lifecycle status: syncBeaconStatus(status, authorId:).

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/features/beacon_threads/ui/message/discussion_read_only_message.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

/// Counts NOW-line writes (the base fake does not implement them).
class _NowLineRoomRepository extends FakeBeaconThreadsRepository {
  _NowLineRoomRepository({required super.userId});

  final List<String> nowLineWrites = [];

  @override
  Future<BeaconRoomState> updateRoomNowLine({
    required String beaconId,
    required String text,
  }) async {
    nowLineWrites.add(text);
    return BeaconRoomState(
      beaconId: beaconId,
      currentLine: text,
      updatedAt: DateTime.utc(2026),
    );
  }
}

BeaconParticipant _participant(
  String userId, {
  int roomAccess = RoomAccessBits.admitted,
}) => BeaconParticipant(
  id: 'p-$userId',
  beaconId: kRoomCubitFakeBeaconId,
  userId: userId,
  role: BeaconParticipantRoleBits.helper,
  status: 0,
  roomAccess: roomAccess,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

bool _blockedMessageShown(FakeUiEffectPort effects) => effects.emitted
    .whereType<ShowMessage>()
    .any((e) => e.message is DiscussionPlanUpdateBlockedMessage);

void main() {
  group('#379 RoomCubit.updatePlan for the request author', () {
    // Production rows: peers only, never an author row for the viewer.
    Future<(RoomCubit, _NowLineRoomRepository, FakeUiEffectPort)> loaded({
      List<BeaconParticipant>? participants,
    }) async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final repo = _NowLineRoomRepository(userId: kRoomCubitFakeMyUserId)
        ..participants = participants ?? [_participant('peer-helper')];
      final effects = FakeUiEffectPort();
      final cubit = roomCubitForTest(repo, effects: effects);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
      return (cubit, repo, effects);
    }

    test('syncBeaconStatus stores the author id and makes them a plan '
        'editor', () async {
      final (cubit, _, _) = await loaded();

      cubit.syncBeaconStatus(
        BeaconStatus.reviewOpen,
        authorId: kRoomCubitFakeMyUserId,
      );

      expect(cubit.state.beaconAuthorId, kRoomCubitFakeMyUserId);
      expect(cubit.state.isPlanEditor, isTrue);
      expect(cubit.state.canUpdatePlan, isTrue);
    });

    for (final status in [BeaconStatus.reviewOpen, BeaconStatus.open]) {
      test('${status.name}: the author saves the plan (no "Request is not '
          'open.")', () async {
        final (cubit, repo, effects) = await loaded();
        cubit.syncBeaconStatus(status, authorId: kRoomCubitFakeMyUserId);

        await cubit.updatePlan('Bring the ladder', expectedLine: null);

        expect(repo.nowLineWrites, ['Bring the ladder']);
        expect(_blockedMessageShown(effects), isFalse);
      });
    }

    for (final status in [
      BeaconStatus.closed,
      BeaconStatus.cancelled,
      BeaconStatus.draft,
    ]) {
      test('${status.name}: even the author is refused', () async {
        final (cubit, repo, effects) = await loaded();
        cubit.syncBeaconStatus(status, authorId: kRoomCubitFakeMyUserId);
        expect(cubit.state.canUpdatePlan, isFalse);

        await cubit.updatePlan('Bring the ladder', expectedLine: null);

        expect(repo.nowLineWrites, isEmpty);
        expect(_blockedMessageShown(effects), isTrue);
      });
    }

    test('reviewOpen: a non-author who is not admitted is refused', () async {
      final (cubit, repo, effects) = await loaded(
        participants: [
          _participant('peer-helper'),
          _participant(
            kRoomCubitFakeMyUserId,
            roomAccess: RoomAccessBits.requested,
          ),
        ],
      );
      cubit.syncBeaconStatus(BeaconStatus.reviewOpen, authorId: 'someone-else');

      await cubit.updatePlan('Bring the ladder', expectedLine: null);

      expect(repo.nowLineWrites, isEmpty);
      expect(_blockedMessageShown(effects), isTrue);
    });

    test('reviewOpen: an admitted helper still saves', () async {
      final (cubit, repo, effects) = await loaded(
        participants: [
          _participant('peer-helper'),
          _participant(kRoomCubitFakeMyUserId),
        ],
      );
      cubit.syncBeaconStatus(BeaconStatus.reviewOpen, authorId: 'someone-else');

      await cubit.updatePlan('Bring the ladder', expectedLine: null);

      expect(repo.nowLineWrites, ['Bring the ladder']);
      expect(_blockedMessageShown(effects), isFalse);
    });
  });
}
