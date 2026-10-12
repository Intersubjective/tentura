import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/use_case/beacon_plan_case.dart';
import 'plan_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'plan_state.dart';

/// The Plan tab of one Request: the plan, the filter, optimistic ticks with
/// rollback, «Понятно» and «Не успеваю». Refetches on realtime `beacon_plan`.
class PlanCubit extends Cubit<PlanState> {
  PlanCubit({
    required String beaconId,
    required String viewerId,
    BeaconPlanCase? planCase,
    DateTime Function()? clock,
  }) : _case = planCase ?? GetIt.I<BeaconPlanCase>(),
       _clock = clock ?? DateTime.now,
       super(PlanState(beaconId: beaconId, viewerId: viewerId)) {
    _changesSub = _case
        .changesFor(beaconId)
        .listen((_) => unawaited(refresh()));
  }

  final BeaconPlanCase _case;
  final DateTime Function() _clock;

  late final StreamSubscription<String> _changesSub;

  /// stepId → requested done value, kept over refetches until the server
  /// answers so a racing refetch never flips the box back.
  final _pendingTicks = <String, bool>{};

  int _fetchEpoch = 0;

  @override
  Future<void> close() async {
    await _changesSub.cancel();
    return super.close();
  }

  Future<void> load() async {
    emit(state.copyWith(status: const StateIsLoading(), loadError: null));
    await refresh();
  }

  /// Silent refetch (realtime, after writes).
  Future<void> refresh() async {
    final epoch = ++_fetchEpoch;
    try {
      final plan = await _case.fetch(state.beaconId);
      if (isClosed || epoch != _fetchEpoch) return;
      emit(
        state.copyWith(
          plan: _overlayPending(plan),
          status: const StateIsSuccess(),
          loadError: null,
        ),
      );
    } on Object catch (e) {
      if (isClosed || epoch != _fetchEpoch) return;
      emit(state.copyWith(status: const StateIsSuccess(), loadError: e));
    }
  }

  void setFilter(PlanFilter filter) {
    if (filter == state.filter) return;
    emit(state.copyWith(filter: filter));
  }

  /// Ticks or unticks [stepId] optimistically; rolls back on failure.
  Future<void> toggleDone(String stepId) async {
    final plan = state.plan;
    final step = plan?.stepById(stepId);
    if (plan == null || step == null || !plan.tickable) return;
    if (state.busyStepIds.contains(stepId)) return;
    final done = !step.isDone;
    _pendingTicks[stepId] = done;
    emit(
      state.copyWith(
        plan: plan.withStepDone(
          stepId,
          done: done,
          actorId: state.viewerId,
          now: _clock(),
        ),
        busyStepIds: {...state.busyStepIds, stepId},
      ),
    );
    try {
      await _case.setDone(stepId: stepId, done: done);
      _pendingTicks.remove(stepId);
      if (isClosed) return;
      emit(
        state.copyWith(
          busyStepIds: {...state.busyStepIds}..remove(stepId),
        ),
      );
      unawaited(refresh());
    } on Object catch (e) {
      _pendingTicks.remove(stepId);
      if (isClosed) return;
      final current = state.plan;
      emit(
        state.copyWith(
          plan: current?.withSteps([
            for (final s in current.steps)
              if (s.id == stepId)
                s.withDone(doneAt: step.doneAt, doneById: step.doneById)
              else
                s,
          ]),
          busyStepIds: {...state.busyStepIds}..remove(stepId),
          notice: PlanNoticeError(e, tickFailed: true),
          noticeSeq: state.noticeSeq + 1,
        ),
      );
    }
  }

  /// «Понятно»: confirms every change up to the head the viewer has seen.
  Future<void> ack() async {
    final plan = state.plan;
    final pending = plan?.viewerPending;
    if (plan == null || pending == null) return;
    final upto = pending.headSeq > 0 ? pending.headSeq : plan.revisionSeq;
    emit(state.copyWith(plan: plan.withoutViewerPending()));
    try {
      await _case.ack(beaconId: state.beaconId, uptoSeq: upto);
    } on Object catch (e) {
      if (isClosed) return;
      _emitError(e);
    }
    if (!isClosed) unawaited(refresh());
  }

  /// «Не успеваю» by the assignee. Returns true when the server took it.
  Future<bool> cantMake({
    required String stepId,
    required PlanCantMakeOption option,
    DateTime? newStartAt,
    DateTime? newEndAt,
    String? toUserId,
    String? excerpt,
  }) async {
    final plan = state.plan;
    if (plan == null) return false;
    try {
      await _case.cantMake(
        stepId: stepId,
        option: option,
        baseRevisionSeq: plan.revisionSeq,
        newStartAt: newStartAt,
        newEndAt: newEndAt,
        toUserId: toUserId,
        excerpt: excerpt,
      );
    } on Object catch (e) {
      if (isClosed) return false;
      _emitError(e);
      unawaited(refresh());
      return false;
    }
    if (!isClosed) unawaited(refresh());
    return true;
  }

  void _emitError(Object e) => emit(
    state.copyWith(
      notice: PlanNoticeError(e),
      noticeSeq: state.noticeSeq + 1,
    ),
  );

  BeaconPlan _overlayPending(BeaconPlan plan) {
    if (_pendingTicks.isEmpty) return plan;
    final now = _clock();
    var next = plan;
    for (final MapEntry(key: id, value: done) in _pendingTicks.entries) {
      final step = next.stepById(id);
      if (step == null || step.isDone == done) continue;
      next = next.withStepDone(
        id,
        done: done,
        actorId: state.viewerId,
        now: now,
      );
    }
    return next;
  }
}
