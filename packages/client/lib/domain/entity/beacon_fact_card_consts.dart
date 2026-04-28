/// Mirrors server `beacon_fact_card.visibility` / `status`.
abstract final class BeaconFactCardVisibilityBits {
  static const public = 0;
  static const room = 1;
}

abstract final class BeaconFactCardStatusBits {
  static const active = 0;
  static const corrected = 1;
  static const removed = 2;
}
