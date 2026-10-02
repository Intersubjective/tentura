// tentura-pt83: client lifecycle wires must match server closureOpened /
// closureExpired.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';

void main() {
  group('BeaconLifecycleChangeReason closure wires (tentura-pt83)', () {
    test('closureOpened wire matches server emission', () {
      expect(BeaconLifecycleChangeReason.closureOpened, 'closureOpened');
    });

    test('closureExpired wire matches server emission', () {
      expect(BeaconLifecycleChangeReason.closureExpired, 'closureExpired');
    });
  });
}
