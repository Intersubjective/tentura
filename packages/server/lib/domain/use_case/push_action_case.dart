import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/plan/push_action_token.dart';
import 'package:tentura_server/domain/port/beacon_plan_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_plan_case.dart';

import '_use_case_base.dart';

/// Result of a push notification button (plan §5.9).
enum PushActionOutcome {
  /// The step was ticked / the changes were confirmed.
  applied,

  /// Nothing left to do (already ticked or already confirmed).
  alreadyDone,

  /// The plan moved on: the step was reassigned or removed, a newer change
  /// waits, or the Request no longer allows coordination (`planActionStale`).
  stale,

  /// The token is forged, expired or malformed.
  invalid,
}

/// Applies a «Готово» / «Понятно» tapped on a plan push, authorized by the
/// signed action token alone (no session), through the same
/// [BeaconPlanCase.setDone] / [BeaconPlanCase.ack] as the app.
@Singleton(order: 2)
class PushActionCase extends UseCaseBase {
  PushActionCase(
    this._tokens,
    this._repo,
    this._plan, {
    required super.env,
    required super.logger,
  });

  final PushActionToken _tokens;
  final BeaconPlanRepositoryPort _repo;
  final BeaconPlanCase _plan;

  Future<PushActionOutcome> apply(String token) async {
    final claims = _tokens.verify(token);
    if (claims == null) return PushActionOutcome.invalid;
    if (!env.planEnabled) return PushActionOutcome.stale;
    try {
      return switch (claims.action) {
        PushAction.done => await _done(claims),
        PushAction.ack => await _ack(claims),
      };
    } on PlanStepNotFoundException {
      return PushActionOutcome.stale;
    } on PlanNotEditableException {
      return PushActionOutcome.stale;
    } on PlanActionStaleException {
      return PushActionOutcome.stale;
    } on BeaconNotRequestException {
      return PushActionOutcome.stale;
    } on UnauthorizedException {
      // No longer admitted (left, removed or blocked).
      return PushActionOutcome.stale;
    }
  }

  Future<PushActionOutcome> _done(PushActionClaims claims) async {
    final step = await _repo.getStep(claims.stepId!);
    if (step == null ||
        step.isRemoved ||
        step.beaconId != claims.beaconId ||
        step.assigneeId != claims.accountId) {
      return PushActionOutcome.stale;
    }
    if (step.isDone) return PushActionOutcome.alreadyDone;
    await _plan.setDone(actorId: claims.accountId, stepId: step.id, done: true);
    return PushActionOutcome.applied;
  }

  Future<PushActionOutcome> _ack(PushActionClaims claims) async {
    final seq = claims.seq!;
    final member = await _repo.getMember(claims.beaconId, claims.accountId);
    final pendingFrom = member?.pendingFromSeq;
    if (member == null || pendingFrom == null || member.ackedSeq >= seq) {
      return PushActionOutcome.alreadyDone;
    }
    // A change newer than the one the push showed waits: confirming the old
    // one would hide it.
    if (pendingFrom > seq) return PushActionOutcome.stale;
    final head = await _repo.getHead(claims.beaconId);
    if (head == null || seq > head.revisionSeq) return PushActionOutcome.stale;
    await _plan.ack(
      actorId: claims.accountId,
      beaconId: claims.beaconId,
      uptoSeq: seq,
    );
    return PushActionOutcome.applied;
  }
}
