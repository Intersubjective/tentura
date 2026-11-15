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
  static const copied = 4;
}

/// Edits by the same actor within this window coalesce into one revision.
const kFactEditQuietWindow = Duration(minutes: 5);

/// Max length of a fact system-line text.
const kFactSystemLineTextMax = 160;

/// Page size for fact revision history.
const kFactHistoryPageSize = 50;

/// Max distinct source facts one copy call accepts (plan §5.2 step 8).
const kMaxFactCopySourcesPerCall = 20;

/// Max images one copy call re-stores (plan §5.2 step 8).
const kMaxFactCopyImagesPerCall = 40;

/// Most Requests `BeaconFactCopyDestinations` returns.
const kMaxFactCopyDestinations = 100;

/// Most saved facts one user keeps (plan D20).
const kSavedFactCap = 200;

/// Most rows one fact search returns (plan #1288 P5).
const kMaxFactSearchResults = 30;
