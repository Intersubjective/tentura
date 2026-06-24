import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';

void main() {
  group('beacon status domain range', () {
    test('allows all persisted BeaconStatus smallints including open-family 7, 8', () {
      for (final s in [0, 1, 2, 3, 5, 6, 7, 8]) {
        expect(isAllowedBeaconStatusSmallint(s), isTrue, reason: 'status $s');
      }
    });

    test('rejects out-of-range statuses', () {
      expect(isAllowedBeaconStatusSmallint(-1), isFalse);
      expect(isAllowedBeaconStatusSmallint(4), isFalse);
      expect(isAllowedBeaconStatusSmallint(9), isFalse);
    });
  });
}
