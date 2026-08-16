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

  /// Provenance is the (inviter, invitee) pair, not an invitation id — the
  /// invitation row is deleted during acceptance (C4).
  Future<void> upsertSeedAttestation({
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  });

  /// Active seed-routing slugs for one (observer, subject) pair.
  /// Authz is the caller's job — [InviteSeedAttestationCase] only.
  Future<Set<String>> activeSeedSlugs({
    required String observerId,
    required String subjectId,
  });
}
