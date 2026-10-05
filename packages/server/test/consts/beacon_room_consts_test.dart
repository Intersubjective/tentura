import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';

void main() {
  group('BeaconRoomSemanticMarker', () {
    test('assigns stable marker ids', () {
      expect(BeaconRoomSemanticMarker.updatePlan, 1);
      expect(BeaconRoomSemanticMarker.pinFactPublic, 2);
      expect(BeaconRoomSemanticMarker.pinFactPrivate, 3);
      expect(BeaconRoomSemanticMarker.participantStatusChanged, 4);
      expect(BeaconRoomSemanticMarker.blocker, 5);
      expect(BeaconRoomSemanticMarker.needInfo, 6);
      expect(BeaconRoomSemanticMarker.done, 7);
      expect(BeaconRoomSemanticMarker.poll, 8);
      expect(BeaconRoomSemanticMarker.participantJoined, 9);
      expect(BeaconRoomSemanticMarker.factEdited, 10);
      expect(BeaconRoomSemanticMarker.factUnpinned, 11);
      expect(BeaconRoomSemanticMarker.batonTaken, 12);
    });
  });

  group('room attachment limits', () {
    test('caps attachments and bytes per message', () {
      expect(kMaxRoomMessageAttachments, 10);
      expect(kMaxRoomMessageAttachmentBytes, 10 * 1024 * 1024);
      expect(kBeaconRoomCurrentLineMaxLength, 60);
    });
  });

  group('BeaconParticipantRoleBits', () {
    test('addressee is the role admitted by an inbound forward', () {
      expect(BeaconParticipantRoleBits.forwarder, 5);
      expect(BeaconParticipantRoleBits.addressee, 6);
    });
  });

  group('BeaconRoomSystemMessageKind', () {
    test('converted-to-request notice has its own kind', () {
      expect(BeaconRoomSystemMessageKind.closureStory, 3);
      expect(BeaconRoomSystemMessageKind.convertedToRequest, 4);
    });
  });

  group('RoomAccessBits', () {
    test('defines ordered access states', () {
      expect(RoomAccessBits.none, 0);
      expect(RoomAccessBits.requested, 1);
      expect(RoomAccessBits.invited, 2);
      expect(RoomAccessBits.admitted, 3);
      expect(RoomAccessBits.muted, 4);
      expect(RoomAccessBits.left, 5);
    });
  });
}
