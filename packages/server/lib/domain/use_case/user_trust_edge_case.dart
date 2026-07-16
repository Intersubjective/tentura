import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/enum.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/utils/id.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class UserTrustEdgeCase extends UseCaseBase {
  UserTrustEdgeCase(
    this._userRepository,
    this._trustEdgeRepository, {
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    required super.env,
    required super.logger,
  }) : _attentionIntents = attentionIntents,
       _attention = attention;

  final UserRepositoryPort _userRepository;
  final UserTrustEdgeRepositoryPort _trustEdgeRepository;
  final AttentionIntentCase? _attentionIntents;
  final TransactionalAttentionCase? _attention;

  Future<void> setUserVote({
    required String subjectUserId,
    required String objectUserId,
    required int amount,
  }) {
    if (!env.attentionV1NewProducersEnabled) {
      return _trustEdgeRepository.setVoteAmountAndApplyEvidence(
        subjectUserId: subjectUserId,
        objectUserId: objectUserId,
        newAmount: amount,
      );
    }
    return _attention!.runAction<void>(
      actorUserId: subjectUserId,
      action: (transaction) async {
        final formed = await _trustEdgeRepository
            .setVoteAmountAndDetectMutualFormationInTransaction(
              subjectUserId: subjectUserId,
              objectUserId: objectUserId,
              newAmount: amount,
            );
        if (!formed) return;
        await transaction.record(
          await _attentionIntents!.mutualConnectionFormed(
            actorUserId: subjectUserId,
            counterpartUserId: objectUserId,
            sourceEventKey: 'mutual_connection:${generateId('A')}',
          ),
        );
      },
    );
  }

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
