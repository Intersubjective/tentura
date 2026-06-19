import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';

void main() {
  group('isCoordinationLogEventType', () {
    test('includes coordination semantic range 100-499', () {
      expect(isCoordinationLogEventType(100), isTrue);
      expect(isCoordinationLogEventType(301), isTrue);
      expect(isCoordinationLogEventType(499), isTrue);
    });

    test('includes beaconPublished and legacy milestones', () {
      expect(
        isCoordinationLogEventType(BeaconActivityEventTypeBits.beaconPublished),
        isTrue,
      );
      expect(
        isCoordinationLogEventType(BeaconActivityEventTypeBits.blockerOpened),
        isTrue,
      );
    });

    test('excludes unrelated types', () {
      expect(isCoordinationLogEventType(0), isFalse);
      expect(isCoordinationLogEventType(500), isFalse);
    });
  });
}
