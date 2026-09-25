/// `beacon_fact_card.visibility`: broadcast vs room-only consumers.
abstract final class BeaconFactCardVisibilityBits {
  static const public = 0;
  static const room = 1;
}

/// `beacon_fact_card.status`
abstract final class BeaconFactCardStatusBits {
  static const active = 0;
  static const corrected = 1;
  static const removed = 2;
}

/// `beacon_fact_card_revision.kind`
abstract final class BeaconFactCardRevisionKindBits {
  static const created = 0;
  static const edited = 1;
  static const restored = 2;
  static const imported = 3;
}

/// Edits by the same actor within this window coalesce into one revision.
const kFactEditQuietWindow = Duration(minutes: 5);

/// Max length of a fact system-line text.
const kFactSystemLineTextMax = 160;

/// Page size for fact revision history.
const kFactHistoryPageSize = 50;
