import 'package:tentura_server/domain/trust/trust_evidence.dart';

abstract class UserTrustEdgeRepositoryPort {
  Future<void> applyEvidence(TrustEvidenceBatch batch);

  /// Caller must already be inside an open DB transaction (no nesting).
  Future<void> applyEvidenceInTransaction(TrustEvidenceBatch batch);

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

  Future<void> forceRefreshStar(String sourceUserId);

  Future<void> forceRefreshAll();

  /// Seeds trust edges from vote_user, computes prev_sent_weight, reloads MR.
  Future<void> cutoverBackfillIfNeeded();
}
