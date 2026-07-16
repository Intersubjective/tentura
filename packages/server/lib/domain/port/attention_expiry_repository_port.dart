abstract class AttentionExpiryRepositoryPort {
  /// Locks and returns currently open review windows whose deadline has passed.
  /// The caller owns the surrounding system transaction.
  Future<List<String>> lockExpiredReviewWindowBeaconIds(DateTime now);
}
