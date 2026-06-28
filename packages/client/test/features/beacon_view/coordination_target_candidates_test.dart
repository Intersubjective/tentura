import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_view/ui/widget/coordination_target_candidates.dart';

BeaconParticipant _participant({required String userId}) {
  final t = DateTime.utc(2025, 1, 2);
  return BeaconParticipant(
    id: 'P-$userId',
    beaconId: 'B1',
    userId: userId,
    role: BeaconParticipantRoleBits.helper,
    status: BeaconParticipantStatusBits.committed,
    roomAccess: RoomAccessBits.admitted,
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  const myUserId = 'Ume0000000001';
  const authorId = 'Uauthor000001';
  const otherId = 'Uother0000001';

  test('askTargetUserIds excludes myUserId', () {
    final ids = askTargetUserIds(
      beaconAuthorId: authorId,
      participants: [
        _participant(userId: myUserId),
        _participant(userId: otherId),
      ],
      myUserId: myUserId,
    );
    expect(ids, contains(authorId));
    expect(ids, contains(otherId));
    expect(ids, isNot(contains(myUserId)));
  });

  test('hasPublishedAskTargets false when only self would qualify', () {
    expect(
      hasPublishedAskTargets(
        beaconAuthorId: myUserId,
        participants: [_participant(userId: myUserId)],
        myUserId: myUserId,
      ),
      isFalse,
    );
  });

  test('hasPublishedAskTargets true when another participant exists', () {
    expect(
      hasPublishedAskTargets(
        beaconAuthorId: myUserId,
        participants: [_participant(userId: otherId)],
        myUserId: myUserId,
      ),
      isTrue,
    );
  });
}
