import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_threads/ui/util/admitted_chat_members.dart';

BeaconParticipant _participant({
  required String userId,
  required int roomAccess,
  int role = BeaconParticipantRoleBits.helper,
  String userTitle = '',
}) =>
    BeaconParticipant(
      id: 'P-$userId',
      beaconId: 'B1',
      userId: userId,
      role: role,
      status: 0,
      roomAccess: roomAccess,
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
      userTitle: userTitle,
    );

void main() {
  test('includes admitted helpers and author when author not admitted row', () {
    final members = admittedChatMembers(
      participants: [
        _participant(userId: 'helper', roomAccess: RoomAccessBits.admitted),
        _participant(
          userId: 'author',
          roomAccess: RoomAccessBits.none,
          role: BeaconParticipantRoleBits.author,
          userTitle: 'Author',
        ),
      ],
      beaconAuthorId: 'author',
    );

    expect(members.map((p) => p.userId).toList(), ['author', 'helper']);
  });

  test('deduplicates author when already admitted', () {
    final members = admittedChatMembers(
      participants: [
        _participant(
          userId: 'author',
          roomAccess: RoomAccessBits.admitted,
          role: BeaconParticipantRoleBits.author,
        ),
        _participant(userId: 'helper', roomAccess: RoomAccessBits.admitted),
      ],
      beaconAuthorId: 'author',
    );

    expect(members.length, 2);
  });
}
