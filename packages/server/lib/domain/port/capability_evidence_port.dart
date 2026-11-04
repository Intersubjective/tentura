import 'package:tentura_server/domain/capability/capability_evidence_models.dart';

abstract interface class CapabilityEvidencePort {
  Future<void> reconcileForwardReasons({
    required String forwardEdgeId,
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  });

  Future<void> emitOutcomeEvidenceBatch({
    required String beaconId,
    required List<OutcomeEmission> emissions,
  });

  Future<void> revokeOutcomeEvidence({
    required String beaconId,
    required String observerId,
    required String subjectId,
    required String slug,
  });

  /// Replaces [observerId]'s complete tag set for [subjectId]: the one write
  /// path for private labels (ADR 0012 D5 — every label is a routing seed),
  /// used by the profile and the invite-accepted sheet alike. Legacy
  /// `seedRoutingAttestation` rows outside the set are retired with it.
  Future<void> upsertSeedAttestation({
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  });

  /// Active tags (labels and legacy seed attestations) for one
  /// (observer, subject) pair. Authz is the caller's job.
  Future<Set<String>> activeSeedSlugs({
    required String observerId,
    required String subjectId,
  });
}
