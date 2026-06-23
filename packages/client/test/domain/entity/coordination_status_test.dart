import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/coordination_status.dart';

void main() {
  group('BeaconCoordinationStatus.fromSmallint', () {
    test('maps known coordination status values', () {
      expect(
        BeaconCoordinationStatus.fromSmallint(0),
        BeaconCoordinationStatus.neutral,
      );
      expect(
        BeaconCoordinationStatus.fromSmallint(2),
        BeaconCoordinationStatus.moreOrDifferentHelpNeeded,
      );
      expect(
        BeaconCoordinationStatus.fromSmallint(3),
        BeaconCoordinationStatus.enoughHelpOffered,
      );
    });

    test('maps legacy ACL value 1 to neutral', () {
      expect(
        BeaconCoordinationStatus.fromSmallint(1),
        BeaconCoordinationStatus.neutral,
      );
    });

    test('falls back to neutral for unknown values', () {
      expect(
        BeaconCoordinationStatus.fromSmallint(99),
        BeaconCoordinationStatus.neutral,
      );
    });
  });
}
