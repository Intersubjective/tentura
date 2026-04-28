/// [beacon_participant.status]
abstract final class BeaconParticipantStatusBits {
  static const watching = 0;
  static const offeredHelp = 1;
  static const candidate = 2;
  static const admitted = 3;
  static const checking = 4;
  static const committed = 5;
  static const needsInfo = 6;
  static const blocked = 7;
  static const done = 8;
  static const withdrawn = 9;
}
