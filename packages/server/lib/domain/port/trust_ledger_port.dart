import 'package:tentura_server/domain/trust/ledger_evidence.dart';

/// Trust evidence ledger. No transaction parameter: callers wrap calls in
/// `MutatingUnitOfWorkPort.run`.
abstract interface class TrustLedgerPort {
  Future<void> record(List<LedgerEvidence> evidence);

  Future<void> retract(String sourceKey);

  Future<void> unretract(String sourceKey);

  Future<bool> exists(String sourceKey);

  Future<bool> hasLiveUsefulForwardSince(
    String subjectId,
    String objectId,
    DateTime since,
  );

  Future<void> lockPair(String subjectId, String objectId);

  Future<void> project(List<(String, String)> pairs);
}
