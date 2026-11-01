// #742: a live admission line («U95a5d2e6d869 was admitted…») named a user
// the room's participant list did not have yet. The room re-reads the list
// once per such id, so the line re-renders with the person's name.
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_room_message_paint.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';

import '../../support/burst_coalescer_test_timing.dart';
import 'room_cubit_fakes.dart';

BeaconParticipant _participant(String userId, String title) =>
    BeaconParticipant(
      id: 'P-$userId',
      beaconId: kRoomCubitFakeBeaconId,
      userId: userId,
      role: BeaconParticipantRoleBits.helper,
      status: 0,
      roomAccess: RoomAccessBits.admitted,
      createdAt: DateTime.utc(2026, 10),
      updatedAt: DateTime.utc(2026, 10, 21),
      userTitle: title,
    );

RealtimeRoomMessagePaint _admitted(String id, String joinedUserId) =>
    RealtimeRoomMessagePaint(
      id: id,
      beaconId: kRoomCubitFakeBeaconId,
      authorId: kRoomCubitFakeMyUserId,
      body: '',
      createdAt: DateTime.utc(2026, 10, 24, 17, 30),
      semanticMarker: BeaconRoomSemanticMarker.participantJoined,
      systemPayload: {
        'joinedUserId': joinedUserId,
        'actorUserId': kRoomCubitFakeMyUserId,
      },
    );

void main() {
  test('a live admission of an unknown user re-reads the participants '
      'once, and the name is there after it resolves', () async {
    registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
    final fakeRoom = FakeBeaconThreadsRepository(
      userId: kRoomCubitFakeMyUserId,
    )..participants = [_participant('u-ann', 'Ann')];
    addTearDown(fakeRoom.dispose);
    final cubit = roomCubitForTest(fakeRoom);
    addTearDown(cubit.close);
    await awaitRoomCubitLoad(cubit);
    final loadedCalls = fakeRoom.fetchParticipantsCallCount;

    // Dave was just admitted; the server's list has him now.
    fakeRoom.participants = [
      _participant('u-ann', 'Ann'),
      _participant('u-dave', 'Dave GQ2'),
    ];
    void paint(RealtimeRoomMessagePaint p) => fakeRoom.emitInvalidation(
      BeaconRoomEntityType.roomMessage,
      operation: RealtimeOperation.insert,
      messageId: p.id,
      paint: p,
    );

    paint(_admitted('m-join', 'u-dave'));
    await pumpAfterHintBurst();

    expect(fakeRoom.fetchParticipantsCallCount, loadedCalls + 1);
    expect(
      cubit.state.participants.map((p) => p.userTitle),
      contains('Dave GQ2'),
    );

    // Once per id: a second line about Dave, or one about a known member,
    // does not re-read the list again.
    paint(_admitted('m-join-2', 'u-dave'));
    paint(_admitted('m-join-ann', 'u-ann'));
    await pumpAfterHintBurst();
    expect(fakeRoom.fetchParticipantsCallCount, loadedCalls + 1);
  });
}
