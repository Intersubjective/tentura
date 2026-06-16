import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';
import 'package:tentura_server/domain/trust/trust_evidence.dart';

@Injectable(
  as: UserTrustEdgeRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class UserTrustEdgeRepositoryMock implements UserTrustEdgeRepositoryPort {
  const UserTrustEdgeRepositoryMock();

  @override
  Future<void> applyEvidence(TrustEvidenceBatch batch) async {}

  @override
  Future<void> applyEvidenceInTransaction(TrustEvidenceBatch batch) async {}

  @override
  Future<void> cutoverBackfillIfNeeded() async {}

  @override
  Future<void> forceRefreshAll() async {}

  @override
  Future<void> forceRefreshStar(String sourceUserId) async {}

  @override
  Future<void> setVoteAmountAndApplyEvidence({
    required String subjectUserId,
    required String objectUserId,
    required int newAmount,
  }) async {}

  @override
  Future<void> setVoteAmountAndApplyEvidenceInTransaction({
    required String subjectUserId,
    required String objectUserId,
    required int newAmount,
  }) async {}
}
