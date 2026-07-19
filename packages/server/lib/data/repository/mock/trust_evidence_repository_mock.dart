import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/trust/trust_evidence.dart';

@LazySingleton(
  as: TrustEvidenceRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class TrustEvidenceRepositoryMock implements TrustEvidenceRepositoryPort {
  const TrustEvidenceRepositoryMock();

  @override
  Future<void> record(TrustEvidenceBatch batch) async {}

  @override
  Future<bool> hasForwardEvidenceForRequest(String requestId) async => false;
}
