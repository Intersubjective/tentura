import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/beacon_plan.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '_use_case_base.dart';

/// Request plan («либретто», #220): attention side effects of plan writes.
///
/// `BeaconPlanCase` calls one hook per write, inside the write's transaction
/// and under the plan lock. Each hook records notifications and reconciles
/// the plan obligations of the people the write touched.
@Singleton(order: 2)
class PlanAttentionCase extends UseCaseBase {
  PlanAttentionCase({
    required super.env,
    required super.logger,
  });

  /// A revision was written (save, restore, «Не успеваю», leave).
  Future<void> afterRevision({
    required AttentionTransaction transaction,
    required PlanRequestInfo request,
    required String? actorId,
    required PlanRevisionRecord revision,
  }) async {}

  /// A step was ticked ([done]) or unticked.
  Future<void> afterTick({
    required AttentionTransaction transaction,
    required PlanRequestInfo request,
    required String actorId,
    required PlanStepRecord step,
    required bool done,
  }) async {}

  /// [userId] confirmed plan changes up to [uptoSeq].
  Future<void> afterAck({
    required AttentionTransaction transaction,
    required PlanRequestInfo request,
    required String userId,
    required int uptoSeq,
  }) async {}

  /// «Не успеваю» by the assignee ([actorId]) of [step].
  Future<void> afterCantMake({
    required AttentionTransaction transaction,
    required PlanRequestInfo request,
    required String actorId,
    required PlanStepRecord step,
    required String option,
    required int revisionSeq,
    String excerpt = '',
  }) async {}
}
