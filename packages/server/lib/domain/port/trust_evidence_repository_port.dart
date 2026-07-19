import 'package:tentura_server/domain/trust/trust_evidence.dart';

abstract interface class TrustEvidenceRepositoryPort {
  /// Ledger-insert + source-apply + effective-rebuild for the whole batch.
  ///
  /// Call inside an open unit of work so the episode commits atomically.
  /// Idempotency conflicts skip the item; any other failure aborts the
  /// caller's transaction.
  Future<void> record(TrustEvidenceBatch batch);

  /// Defense-in-depth: whether any forward-context ledger row exists.
  Future<bool> hasForwardEvidenceForRequest(String requestId);
}
