import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_state.dart';

void main() {
  group('RoomState.canWriteDiscussion', () {
    test('locks when beaconStatus is unknown', () {
      expect(const RoomState().canWriteDiscussion, isFalse);
    });

    test('follows allowsDiscussionWrites when status is set', () {
      expect(
        const RoomState(beaconStatus: BeaconStatus.open).canWriteDiscussion,
        isTrue,
      );
      expect(
        const RoomState(
          beaconStatus: BeaconStatus.reviewOpen,
        ).canWriteDiscussion,
        isTrue,
      );
      expect(
        const RoomState(beaconStatus: BeaconStatus.closed).canWriteDiscussion,
        isFalse,
      );
      expect(
        const RoomState(
          beaconStatus: BeaconStatus.cancelled,
        ).canWriteDiscussion,
        isFalse,
      );
    });
  });

  group('RoomState.canUpdatePlan', () {
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

    test('locks when status unknown even if viewer is plan editor', () {
      final s = RoomState(
        myUserId: 'me',
        participants: [admitted('me')],
      );
      expect(s.isPlanEditor, isTrue);
      expect(s.canUpdatePlan, isFalse);
    });

    test('true for open + plan editor; false for closed', () {
      final open = RoomState(
        myUserId: 'me',
        beaconStatus: BeaconStatus.open,
        participants: [admitted('me')],
      );
      final closed = open.copyWith(beaconStatus: BeaconStatus.closed);
      expect(open.canUpdatePlan, isTrue);
      expect(closed.canUpdatePlan, isFalse);
    });

    test('true for reviewOpen when viewer is plan editor', () {
      final s = RoomState(
        myUserId: 'me',
        beaconStatus: BeaconStatus.reviewOpen,
        participants: [admitted('me')],
      );
      expect(s.canUpdatePlan, isTrue);
    });
  });
}
