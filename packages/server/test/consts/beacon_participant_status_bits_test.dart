import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_participant_status_bits.dart';

void main() {
  group('BeaconParticipantStatusBits', () {
    test('defines participant status progression', () {
      expect(BeaconParticipantStatusBits.watching, 0);
      expect(BeaconParticipantStatusBits.offeredHelp, 1);
      expect(BeaconParticipantStatusBits.candidate, 2);
      expect(BeaconParticipantStatusBits.admitted, 3);
      expect(BeaconParticipantStatusBits.checking, 4);
      expect(BeaconParticipantStatusBits.committed, 5);
      expect(BeaconParticipantStatusBits.needsInfo, 6);
      expect(BeaconParticipantStatusBits.blocked, 7);
      expect(BeaconParticipantStatusBits.done, 8);
      expect(BeaconParticipantStatusBits.withdrawn, 9);
    });
  });
}
