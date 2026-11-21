import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/port/capability_evidence_port.dart';

@Injectable(
  as: CapabilityEvidencePort,
  env: [Environment.test],
  order: 1,
)
class CapabilityEvidenceRepositoryMock implements CapabilityEvidencePort {
  @override
  Future<void> reconcileForwardReasons({
    required String forwardEdgeId,
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  }) => Future.value();

  @override
  Future<void> emitOutcomeEvidenceBatch({
    required String beaconId,
    required List<OutcomeEmission> emissions,
  }) => Future.value();

  @override
  Future<void> revokeOutcomeEvidence({
    required String beaconId,
    required String observerId,
    required String subjectId,
    required String slug,
  }) => Future.value();

  @override
  Future<void> upsertSeedAttestation({
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  }) => Future.value();

  @override
  Future<Set<String>> activeSeedSlugs({
    required String observerId,
    required String subjectId,
  }) => Future.value(const {});
}
