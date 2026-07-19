abstract class UserTrustEdgeRepositoryPort {
  Future<void> setVoteAmountAndApplyEvidence({
    required String subjectUserId,
    required String objectUserId,
    required int newAmount,
  });

  Future<void> setVoteAmountAndApplyEvidenceInTransaction({
    required String subjectUserId,
    required String objectUserId,
    required int newAmount,
  });

  /// Applies the vote while serializing the unordered user pair and returns
  /// whether this exact transition changed the relationship to reciprocal.
  Future<bool> setVoteAmountAndDetectMutualFormationInTransaction({
    required String subjectUserId,
    required String objectUserId,
    required int newAmount,
  });

  Future<void> forceRefreshStar(String sourceUserId);

  /// Seeds trust edges from vote_user, computes prev_sent_weight, reloads MR.
  Future<void> cutoverBackfillIfNeeded();
}
