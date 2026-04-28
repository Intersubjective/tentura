/// [beacon_fact_card.visibility]: broadcast vs room-only consumers.
abstract final class BeaconFactCardVisibilityBits {
  static const public = 0;
  static const room = 1;
}

/// [beacon_fact_card.status]
abstract final class BeaconFactCardStatusBits {
  static const active = 0;
  static const corrected = 1;
  static const removed = 2;
}
