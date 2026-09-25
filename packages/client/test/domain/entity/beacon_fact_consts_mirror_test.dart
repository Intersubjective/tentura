import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';

void main() {
  group('fact consts mirror server literals', () {
    test('revision kinds', () {
      expect(BeaconFactCardRevisionKindBits.created, 0);
      expect(BeaconFactCardRevisionKindBits.edited, 1);
      expect(BeaconFactCardRevisionKindBits.restored, 2);
      expect(BeaconFactCardRevisionKindBits.imported, 3);
    });

    test('activity types', () {
      expect(BeaconActivityEventTypeBits.factEdited, 19);
      expect(BeaconActivityEventTypeBits.factRemoved, 20);
    });

    test('room semantic markers', () {
      expect(BeaconRoomSemanticMarker.factEdited, 10);
      expect(BeaconRoomSemanticMarker.factUnpinned, 11);
    });

    test('isCoordinationLogEventType is true for 19 and 20', () {
      expect(isCoordinationLogEventType(19), isTrue);
      expect(isCoordinationLogEventType(20), isTrue);
      expect(isCoordinationLogEventType(0), isFalse);
    });
  });
}
