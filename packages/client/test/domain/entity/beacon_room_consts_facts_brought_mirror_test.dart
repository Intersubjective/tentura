import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';

void main() {
  group('facts-brought chat marker mirrors the server literal', () {
    test('is semantic marker 20', () {
      expect(BeaconRoomSemanticMarker.factsBrought, 20);
    });
  });
}
