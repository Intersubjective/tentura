import 'package:tentura_server/domain/capability/capability_evidence_models.dart';

abstract interface class CapabilityOwnEvidencePort {
  Future<List<OwnEvidenceRow>> fetchOwnEvidence({
    required String egoId,
    required List<String> subjectIds,
    required List<String> tagSlugs,
  });

  Future<List<TombstoneRef>> fetchTombstones({
    required String egoId,
    required List<String> subjectIds,
  });
}
