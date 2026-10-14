import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/exception/beacon_plan_exceptions.dart';
import '../../domain/use_case/beacon_plan_case.dart';
import 'plan_edit_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'plan_edit_state.dart';

/// The plan editor: a client-side draft saved as one revision.
///
/// The base revision is taken when the editor opens (never at send time).
/// The server merges by step; on a real conflict (1336) the fresh plan is
/// loaded, the user's own edits are re-applied onto it, the steps someone
/// else also changed take that version, and the user is told which ones
/// before saving again.
class PlanEditCubit extends Cubit<PlanEditState> {
  PlanEditCubit({
    required BeaconPlan plan,
    BeaconPlanCase? planCase,
    String Function()? newStepId,
  }) : _case = planCase ?? GetIt.I<BeaconPlanCase>(),
       _newStepId = newStepId ?? newPlanStepId,
       super(
         PlanEditState(
           beaconId: plan.beaconId,
           baseSeq: plan.revisionSeq,
           base: plan.snapshot.chronological(),
           steps: plan.snapshot.chronological().steps,
         ),
       );

  final BeaconPlanCase _case;
  final String Function() _newStepId;

  /// A fresh, empty step (not yet in the draft), optionally starting at
  /// [startAt].
  PlanStepSnapshot newStep({DateTime? startAt}) =>
      PlanStepSnapshot(id: _newStepId(), title: '', startAt: startAt);

  /// Adds or replaces [step] and keeps the draft chronological. When that
  /// changes the step's place, its id is reported in `movedStepId`.
  void putStep(PlanStepSnapshot step) {
    final steps = [...state.steps];
    final at = steps.indexWhere((s) => s.id == step.id);
    final before = at < 0 ? steps.length : at;
    if (at < 0) {
      steps.add(step);
    } else {
      steps[at] = step;
    }
    final ordered = PlanSnapshot(steps).chronological().steps;
    final moved = ordered.indexWhere((s) => s.id == step.id) != before;
    emit(
      state.copyWith(
        steps: ordered,
        movedStepId: moved ? step.id : state.movedStepId,
        movedSeq: moved ? state.movedSeq + 1 : state.movedSeq,
      ),
    );
  }

  void removeStep(String id) => emit(
    state.copyWith(steps: [...state.steps]..removeWhere((s) => s.id == id)),
  );

  /// Moves the untimed step at [oldIndex] to [newIndex] (index after removal,
  /// as `ReorderableListView.onReorderItem` reports it). Timed steps stay
  /// put; an untimed step dropped between timed ones sticks to the one above.
  void reorder(int oldIndex, int newIndex) {
    final steps = [...state.steps];
    if (oldIndex < 0 || oldIndex >= steps.length) return;
    final moved = steps.removeAt(oldIndex);
    if (moved.startAt != null || moved.endAt != null) return;
    steps.insert(newIndex.clamp(0, steps.length), moved);
    emit(state.copyWith(steps: PlanSnapshot(steps).chronological().steps));
  }

  void setComment(String comment) => emit(state.copyWith(comment: comment));

  Future<void> save() async {
    if (state.isSaving || state.validationError != null) return;
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      final outcome = await _case.save(
        beaconId: state.beaconId,
        baseRevisionSeq: state.baseSeq,
        steps: state.draft,
        comment: state.comment,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          status: const StateIsSuccess(),
          saved: PlanEditSaved(outcome),
        ),
      );
    } on PlanEditConflictException {
      await _onConflict();
    } on Object catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: const StateIsSuccess(),
          error: e,
          errorSeq: state.errorSeq + 1,
        ),
      );
    }
  }

  Future<void> _onConflict() async {
    try {
      final rebase = await _case.rebaseAfterConflict(
        beaconId: state.beaconId,
        baseSeq: state.baseSeq,
        base: state.base,
        mine: state.draft,
      );
      if (isClosed) return;
      final conflicts = rebase.conflicts;
      emit(
        state.copyWith(
          status: const StateIsSuccess(),
          baseSeq: rebase.currentSeq,
          base: rebase.theirs.chronological(),
          steps: rebase.draft.chronological().steps,
          conflictSteps: conflicts,
          conflictSeq: conflicts.isEmpty
              ? state.conflictSeq
              : state.conflictSeq + 1,
        ),
      );
      // Merged locally (the server could not, e.g. its base was gone).
      if (conflicts.isEmpty) await save();
    } on Object catch (err) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: const StateIsSuccess(),
          error: err,
          errorSeq: state.errorSeq + 1,
        ),
      );
    }
  }
}
