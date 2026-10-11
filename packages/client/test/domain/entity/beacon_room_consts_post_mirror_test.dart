import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';

void main() {
  group('post room consts mirror server literals', () {
    test('addressee participant role', () {
      expect(BeaconParticipantRoleBits.addressee, 6);
    });

    test('converted-to-request system message kind', () {
      expect(BeaconRoomSystemMessageKind.convertedToRequest, 4);
    });

    test('post-closed system message kind (budding)', () {
      expect(BeaconRoomSystemMessageKind.postClosed, 5);
    });

    test('baton taken semantic marker', () {
      expect(BeaconRoomSemanticMarker.batonTaken, 12);
    });
  });
}
