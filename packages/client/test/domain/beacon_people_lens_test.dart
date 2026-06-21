import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_people_lens.dart';
import 'package:tentura/domain/entity/beacon_people_optimistic.dart';
import 'package:tentura/domain/entity/beacon_people_row.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';

Beacon _beacon({required String authorId}) {
  final t = DateTime.utc(2025);
  return Beacon(
    id: 'B1',
    title: 'Test',
    author: Profile(id: authorId, displayName: 'Author'),
    createdAt: t,
    updatedAt: t,
  );
}

BeaconParticipant _participant({
  required String userId,
  int roomAccess = RoomAccessBits.admitted,
  int role = BeaconParticipantRoleBits.helper,
}) {
  final t = DateTime.utc(2025, 1, 2);
  return BeaconParticipant(
    id: 'P-$userId',
    beaconId: 'B1',
    userId: userId,
    role: role,
    status: BeaconParticipantStatusBits.committed,
    roomAccess: roomAccess,
    createdAt: t,
    updatedAt: t,
    userTitle: 'User $userId',
  );
}

BeaconPeopleHelpOfferInput _offer({
  required String userId,
  CoordinationResponseType? response,
  int? roomAccess,
}) =>
    BeaconPeopleHelpOfferInput(
      userId: userId,
      profile: Profile(id: userId, displayName: userId),
      isWithdrawn: false,
      roomAccess: roomAccess,
      coordinationResponse: response,
    );

void main() {
  test('author is always first in active helpers', () {
    final sections = classifyBeaconPeopleSections(
      beacon: _beacon(authorId: 'auth'),
      helpOffers: const [],
      roomParticipants: const [],
      viewerUserId: 'viewer',
    );
    expect(sections.activeHelpers.length, 1);
    expect(sections.activeHelpers.first.isAuthor, isTrue);
    expect(sections.activeHelpers.first.userId, 'auth');
  });

  test('admitted via helpOffer.roomAccess lands in active helpers', () {
    final sections = classifyBeaconPeopleSections(
      beacon: _beacon(authorId: 'auth'),
      helpOffers: [
        _offer(userId: 'h1', roomAccess: RoomAccessBits.admitted),
      ],
      roomParticipants: const [],
      viewerUserId: 'viewer',
    );
    expect(sections.activeHelpers.map((r) => r.userId), ['auth', 'h1']);
    expect(sections.willingToHelp, isEmpty);
  });

  test('null response and not admitted → willing to help', () {
    final sections = classifyBeaconPeopleSections(
      beacon: _beacon(authorId: 'auth'),
      helpOffers: [_offer(userId: 'h1')],
      roomParticipants: const [],
      viewerUserId: 'viewer',
    );
    expect(sections.willingToHelp.single.userId, 'h1');
    expect(sections.notFitting, isEmpty);
  });

  test('response and not admitted → not fitting', () {
    final sections = classifyBeaconPeopleSections(
      beacon: _beacon(authorId: 'auth'),
      helpOffers: [
        _offer(
          userId: 'h1',
          response: CoordinationResponseType.notSuitable,
        ),
      ],
      roomParticipants: const [],
      viewerUserId: 'viewer',
    );
    expect(sections.notFitting.single.userId, 'h1');
    expect(sections.willingToHelp, isEmpty);
  });

  test('admitted participant with response stays in active helpers only', () {
    final sections = classifyBeaconPeopleSections(
      beacon: _beacon(authorId: 'auth'),
      helpOffers: [
        _offer(
          userId: 'h1',
          response: CoordinationResponseType.useful,
          roomAccess: RoomAccessBits.admitted,
        ),
      ],
      roomParticipants: [_participant(userId: 'h1')],
      viewerUserId: 'auth',
    );
    expect(sections.activeHelpers.map((r) => r.userId), ['auth', 'h1']);
    expect(sections.willingToHelp, isEmpty);
    expect(sections.notFitting, isEmpty);
  });

  test('applyCoordinationRoomParticipantPatch admits missing row', () {
    final patched = applyCoordinationRoomParticipantPatch(
      participants: const [],
      offerUserId: 'h1',
      inviteToRoom: true,
      removeFromRoom: false,
    );
    expect(patched.length, 1);
    expect(patched.single.userId, 'h1');
    expect(patched.single.roomAccess, RoomAccessBits.admitted);
  });
}
