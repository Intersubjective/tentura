abstract interface class PairBlockQueryPort {
  /// One batch query for every blocked pair among [userIds] (ego↔witness and
  /// witness↔subject in projection). Avoids per-user N+1 round trips.
  Future<Set<(String, String)>> blockedPairsAmong({
    required Set<String> userIds,
  });
}
