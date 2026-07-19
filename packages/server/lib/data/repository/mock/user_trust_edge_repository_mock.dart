import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';

@Injectable(
  as: UserTrustEdgeRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class UserTrustEdgeRepositoryMock implements UserTrustEdgeRepositoryPort {
  const UserTrustEdgeRepositoryMock();

  @override
  Future<void> cutoverBackfillIfNeeded() async {}

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

  @override
  Future<bool> setVoteAmountAndDetectMutualFormationInTransaction({
    required String subjectUserId,
    required String objectUserId,
    required int newAmount,
  }) async => false;
}
