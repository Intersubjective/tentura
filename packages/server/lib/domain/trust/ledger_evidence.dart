import 'trust_evidence_kind.dart';

/// One immutable row of the `trust_evidence` ledger (m0202).
class LedgerEvidence {
  const LedgerEvidence({
    required this.subjectId,
    required this.objectId,
    required this.kind,
    required this.count,
    required this.sourceKey,
    this.beaconId,
    this.epoch,
    this.relatedUserId,
    this.occurredAt,
    this.metadata = const {},
  }) : assert(subjectId != objectId, 'subject and object must differ'),
       assert(count > 0, 'count must be positive');

  final String subjectId;
  final String objectId;
  final TrustEvidenceKind kind;
  final double count;
  final String sourceKey;
  final String? beaconId;
  final int? epoch;
  final String? relatedUserId;
  final DateTime? occurredAt;
  final Map<String, Object?> metadata;
}
