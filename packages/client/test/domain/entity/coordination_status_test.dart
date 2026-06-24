import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

void main() {
  group('BeaconStatus.fromSmallint', () {
    test('maps open-family coordination values', () {
      expect(BeaconStatus.fromSmallint(0), BeaconStatus.open);
      expect(BeaconStatus.fromSmallint(7), BeaconStatus.needsMoreHelp);
      expect(BeaconStatus.fromSmallint(8), BeaconStatus.enoughHelp);
    });

    test('maps lifecycle values', () {
      expect(BeaconStatus.fromSmallint(3), BeaconStatus.draft);
      expect(BeaconStatus.fromSmallint(5), BeaconStatus.reviewOpen);
      expect(BeaconStatus.fromSmallint(6), BeaconStatus.closed);
    });

    test('maps legacy value 4 to closed', () {
      expect(BeaconStatus.fromSmallint(4), BeaconStatus.closed);
    });

    test('falls back to open for unknown values', () {
      expect(BeaconStatus.fromSmallint(99), BeaconStatus.open);
    });
  });
}
