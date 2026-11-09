import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/enum.dart';
import 'package:tentura_server/domain/port/trust_maintenance_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';
import 'package:tentura_server/domain/port/witness_window_port.dart';
import 'package:tentura_server/domain/policy/witness_window_invalidation.dart';
import 'package:tentura_server/domain/policy/mr_privilege_policy.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/utils/id.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class UserTrustEdgeCase extends UseCaseBase {
  UserTrustEdgeCase(
    this._userRepository,
    this._trustEdgeRepository,
    this._trustMaintenance, {
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    WitnessWindowPort? witnessWindow,
    required super.env,
    required super.logger,
  }) : _attentionIntents = attentionIntents,
       _attention = attention,
       _witnessWindow = witnessWindow;

  final UserRepositoryPort _userRepository;
  final UserTrustEdgeRepositoryPort _trustEdgeRepository;
  final TrustMaintenancePort _trustMaintenance;
  final AttentionIntentCase? _attentionIntents;
  final TransactionalAttentionCase? _attention;
  final WitnessWindowPort? _witnessWindow;

  Future<void> setUserVote({
    required String subjectUserId,
    required String objectUserId,
    required int amount,
  }) {
    return _attention!.runAction<void>(
      actorUserId: subjectUserId,
      action: (transaction) async {
        final formed = await _trustEdgeRepository
            .setVoteAmountAndDetectMutualFormationInTransaction(
              subjectUserId: subjectUserId,
              objectUserId: objectUserId,
              newAmount: amount,
            );
        await invalidateWitnessWindowsForPair(
          _witnessWindow,
          subjectUserId,
          objectUserId,
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
    await ensureMrPrivilege(
      _userRepository,
      userId: userId,
      userRoles: userRoles,
    );
    await _trustEdgeRepository.forceRefreshStar(sourceUserId);
  }

  Future<void> forceRefreshAll({
    required String userId,
    Iterable<UserRoles>? userRoles,
  }) async {
    await ensureMrPrivilege(
      _userRepository,
      userId: userId,
      userRoles: userRoles,
    );
    await _trustMaintenance.forceRefreshAll();
  }
}
