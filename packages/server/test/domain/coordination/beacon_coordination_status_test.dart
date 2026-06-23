import 'package:test/test.dart';

import 'package:tentura_server/domain/coordination/beacon_coordination_status.dart';

void main() {
  group('BeaconCoordinationStatus.tryFromInt', () {
    test('maps known coordination status values', () {
      expect(
        BeaconCoordinationStatus.tryFromInt(0),
        BeaconCoordinationStatus.neutral,
      );
      expect(
        BeaconCoordinationStatus.tryFromInt(2),
        BeaconCoordinationStatus.moreOrDifferentHelpNeeded,
      );
      expect(
        BeaconCoordinationStatus.tryFromInt(3),
        BeaconCoordinationStatus.enoughHelpOffered,
      );
    });

    test('returns null for unknown values', () {
      expect(BeaconCoordinationStatus.tryFromInt(1), isNull);
      expect(BeaconCoordinationStatus.tryFromInt(99), isNull);
    });
  });
}
