import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_blocker_consts.dart';

void main() {
  group('BeaconBlockerStatusBits', () {
    test('defines blocker lifecycle states', () {
      expect(BeaconBlockerStatusBits.open, 0);
      expect(BeaconBlockerStatusBits.resolved, 1);
      expect(BeaconBlockerStatusBits.cancelled, 2);
    });
  });
}
