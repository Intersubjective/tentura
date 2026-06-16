import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/enum.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class UserTrustEdgeCase extends UseCaseBase {
  UserTrustEdgeCase(
    this._userRepository,
    this._trustEdgeRepository, {
    required super.env,
    required super.logger,
  });

  final UserRepositoryPort _userRepository;
  final UserTrustEdgeRepositoryPort _trustEdgeRepository;

  Future<void> setUserVote({
    required String subjectUserId,
    required String objectUserId,
    required int amount,
  }) => _trustEdgeRepository.setVoteAmountAndApplyEvidence(
    subjectUserId: subjectUserId,
    objectUserId: objectUserId,
    newAmount: amount,
  );

  Future<void> forceRefreshStar({
    required String userId,
    required String sourceUserId,
    Iterable<UserRoles>? userRoles,
  }) async {
    await _ensureMrPrivilege(userId: userId, userRoles: userRoles);
    await _trustEdgeRepository.forceRefreshStar(sourceUserId);
  }

  Future<void> forceRefreshAll({
    required String userId,
    Iterable<UserRoles>? userRoles,
  }) async {
    await _ensureMrPrivilege(userId: userId, userRoles: userRoles);
    await _trustEdgeRepository.forceRefreshAll();
  }

  Future<void> cutoverBackfillIfNeeded() =>
      _trustEdgeRepository.cutoverBackfillIfNeeded();

  Future<void> _ensureMrPrivilege({
    required String userId,
    Iterable<UserRoles>? userRoles,
  }) async {
    if (userRoles != null && userRoles.contains(UserRoles.admin)) return;
    if ((await _userRepository.getById(userId)).hasPrivilege(
      UserPrivileges.mrInit,
    )) {
      return;
    }
    throw const UnauthorizedException();
  }
}
