import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';

void main() {
  group('BeaconFactCardVisibilityBits', () {
    test('defines public and room visibility', () {
      expect(BeaconFactCardVisibilityBits.public, 0);
      expect(BeaconFactCardVisibilityBits.room, 1);
    });
  });

  group('BeaconFactCardStatusBits', () {
    test('defines fact card lifecycle states', () {
      expect(BeaconFactCardStatusBits.active, 0);
      expect(BeaconFactCardStatusBits.corrected, 1);
      expect(BeaconFactCardStatusBits.removed, 2);
    });
  });
}
