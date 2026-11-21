import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/port/capability_own_evidence_port.dart';

@Injectable(
  as: CapabilityOwnEvidencePort,
  env: [Environment.test],
  order: 1,
)
class CapabilityOwnEvidenceRepositoryMock implements CapabilityOwnEvidencePort {
  @override
  Future<List<OwnEvidenceRow>> fetchOwnEvidence({
    required String egoId,
    required List<String> subjectIds,
    required List<String> tagSlugs,
  }) => Future.value(const []);

  @override
  Future<List<TombstoneRef>> fetchTombstones({
    required String egoId,
    required List<String> subjectIds,
  }) => Future.value(const []);
}
