import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_tile.dart';

void main() {
  test('participantJoinedPayload parses join metadata', () {
    final message = RoomMessage(
      id: 'R1',
      beaconId: 'B1',
      authorId: 'Uauth',
      body: '',
      createdAt: DateTime.utc(2025),
      semanticMarker: BeaconRoomSemanticMarker.participantJoined,
      systemPayloadJson:
          '{"joinedUserId":"Uhelper","admissionReason":"autoAdmit","actorUserId":"Uauth"}',
      author: Profile(id: 'Uauth', displayName: 'Author'),
    );

    expect(RoomMessageTile.isParticipantJoinedNotification(message), isTrue);
    expect(
      RoomMessageTile.participantJoinedPayload(message),
      {
        'joinedUserId': 'Uhelper',
        'admissionReason': 'autoAdmit',
      },
    );
  });
}
