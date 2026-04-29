/// Outward-facing status from `beacon.public_status` (`smallint`).
abstract final class BeaconPublicStatusBits {
  static const open = 0;
  static const coordinating = 1;
  static const moreHelpNeeded = 2;
  static const enoughHelp = 3;
  static const closed = 4;
}
