/// Mirrors server `beacon_fact_card.visibility` / `status`.
abstract final class BeaconFactCardVisibilityBits {
  static const public = 0;
  static const room = 1;

  /// A Post's facts have one visibility, discussion-only (plan D5).
  static const post = room;
}

abstract final class BeaconFactCardStatusBits {
  static const active = 0;
  static const corrected = 1;
  static const removed = 2;
}

/// Mirrors server `BeaconFactCardRevisionKindBits`.
abstract final class BeaconFactCardRevisionKindBits {
  static const created = 0;
  static const edited = 1;
  static const restored = 2;
  static const imported = 3;
  static const copied = 4;
}
