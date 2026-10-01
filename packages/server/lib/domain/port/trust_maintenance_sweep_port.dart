/// Keyset sweep over the trust pair universe for maintenance projection.
abstract interface class TrustMaintenanceSweepPort {
  /// Loads the next page of pairs after `(afterSubject, afterObject)`,
  /// projects each via `trust_project_pair` inside one transaction.
  /// Returns pairs in sort order; empty when the universe is exhausted.
  Future<List<(String subject, String object)>> projectNextBatch({
    required String afterSubject,
    required String afterObject,
    required int batchSize,
  });

  Future<void> bumpMrPublishEpoch();
}
