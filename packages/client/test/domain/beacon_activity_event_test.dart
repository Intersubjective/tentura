import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';

BeaconActivityEvent _event(int type) => BeaconActivityEvent(
  id: 'e1',
  beaconId: 'b1',
  visibility: 0,
  type: type,
  createdAt: DateTime(2026, 6, 18),
);

void main() {
  group('isCoordinationLogEvent', () {
    test('includes coordination semantic range 100-499', () {
      expect(_event(100).isCoordinationLogEvent, isTrue);
      expect(_event(301).isCoordinationLogEvent, isTrue);
      expect(_event(499).isCoordinationLogEvent, isTrue);
    });

    test('includes legacy milestone types including beaconPublished', () {
      expect(
        _event(BeaconActivityEventTypeBits.beaconPublished).isCoordinationLogEvent,
        isTrue,
      );
      expect(
        _event(BeaconActivityEventTypeBits.beaconLifecycleChanged)
            .isCoordinationLogEvent,
        isTrue,
      );
      expect(
        _event(BeaconActivityEventTypeBits.blockerOpened).isCoordinationLogEvent,
        isTrue,
      );
    });

    test('excludes unrelated types', () {
      expect(_event(0).isCoordinationLogEvent, isFalse);
      expect(_event(500).isCoordinationLogEvent, isFalse);
    });
  });
}
