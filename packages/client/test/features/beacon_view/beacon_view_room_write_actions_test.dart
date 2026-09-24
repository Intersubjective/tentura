import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_app_bar_overflow.dart';

class _FakeRoomCubit extends Mock implements RoomCubit {
  _FakeRoomCubit(this._state);

  final RoomState _state;

  @override
  RoomState get state => _state;

  @override
  bool get isClosed => false;
}

class _FakeBuildContext extends Fake implements BuildContext {}

void main() {
  BeaconParticipant admitted(String userId) => BeaconParticipant(
    id: 'p-$userId',
    beaconId: 'b1',
    userId: userId,
    role: BeaconParticipantRoleBits.helper,
    status: 0,
    roomAccess: RoomAccessBits.admitted,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  test('create poll / update plan null when discussion or plan locked', () {
    final locked = _FakeRoomCubit(
      RoomState(
        myUserId: 'me',
        beaconStatus: BeaconStatus.closed,
        participants: [admitted('me')],
      ),
    );
    expect(
      beaconViewRoomCreatePollAction(
        context: _FakeBuildContext(),
        roomCubit: locked,
        inRoomSurface: true,
      ),
      isNull,
    );
    expect(
      beaconViewRoomUpdatePlanAction(
        context: _FakeBuildContext(),
        roomCubit: locked,
        inRoomSurface: true,
      ),
      isNull,
    );
  });

  test('create poll non-null when writable; update plan gated by canUpdatePlan', () {
    final writable = _FakeRoomCubit(
      RoomState(
        myUserId: 'me',
        beaconStatus: BeaconStatus.open,
        participants: [admitted('me')],
      ),
    );
    expect(
      beaconViewRoomCreatePollAction(
        context: _FakeBuildContext(),
        roomCubit: writable,
        inRoomSurface: true,
      ),
      isNotNull,
    );
    // updatePlan needs L10n.of(context); gate itself is RoomState.canUpdatePlan.
    expect(writable.state.canUpdatePlan, isTrue);
    expect(
      _FakeRoomCubit(
        const RoomState(beaconStatus: BeaconStatus.open),
      ).state.canUpdatePlan,
      isFalse,
    );
  });
}
