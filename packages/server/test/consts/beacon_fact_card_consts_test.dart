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

  group('BeaconFactCardRevisionKindBits', () {
    test('defines revision kinds', () {
      expect(BeaconFactCardRevisionKindBits.created, 0);
      expect(BeaconFactCardRevisionKindBits.edited, 1);
      expect(BeaconFactCardRevisionKindBits.restored, 2);
      expect(BeaconFactCardRevisionKindBits.imported, 3);
    });
  });

  group('fact edit limits', () {
    test('quiet window, system line max, history page size', () {
      expect(kFactEditQuietWindow, const Duration(minutes: 5));
      expect(kFactSystemLineTextMax, 160);
      expect(kFactHistoryPageSize, 50);
    });
  });
}
