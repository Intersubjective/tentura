import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/beacon_plan.dart';
import '../../domain/entity/plan_conflict.dart';

part 'plan_edit_state.freezed.dart';

/// Client-side limits (server `BeaconPlanConsts`).
abstract final class PlanLimits {
  static const maxSteps = 100;
  static const maxTitleLength = 120;
  static const maxDescriptionLength = 1000;
  static const maxCommentLength = 280;
}

/// Why the draft cannot be saved yet.
enum PlanDraftError {
  titleRequired,
  titleTooLong,
  descriptionTooLong,
  endBeforeStart,
  tooManySteps,
  commentTooLong,
}

/// The draft was written: how.
@immutable
final class PlanEditSaved {
  const PlanEditSaved(this.outcome);

  final PlanSaveOutcome outcome;
}

@freezed
abstract class PlanEditState extends StateBase with _$PlanEditState {
  const factory PlanEditState({
    required String beaconId,

    /// The revision the draft is based on (taken when the editor opened,
    /// moved forward only by a conflict resolution).
    required int baseSeq,

    /// Content of [baseSeq].
    required PlanSnapshot base,

    /// The draft, in plan order.
    required List<PlanStepSnapshot> steps,
    @Default('') String comment,
    @Default(StateIsSuccess()) StateStatus status,

    /// Set while the user picks versions for conflicting steps.
    PlanConflict? conflict,
    @Default({}) Map<String, PlanConflictChoice> choices,

    /// Set once the draft is saved; the editor closes on it.
    PlanEditSaved? saved,

    /// Latest write error (not a conflict); [errorSeq] grows with each one.
    Object? error,
    @Default(0) int errorSeq,
  }) = _PlanEditState;

  const PlanEditState._();

  PlanSnapshot get draft => PlanSnapshot(steps);

  bool get isDirty => !draft.sameAs(base) || comment.trim().isNotEmpty;

  bool get isSaving => isLoading;

  /// First problem that blocks saving, or null.
  PlanDraftError? get validationError {
    if (steps.length > PlanLimits.maxSteps) return PlanDraftError.tooManySteps;
    if (comment.trim().length > PlanLimits.maxCommentLength) {
      return PlanDraftError.commentTooLong;
    }
    for (final s in steps) {
      final error = validatePlanStep(s);
      if (error != null) return error;
    }
    return null;
  }
}

/// Problems of one step, or null.
PlanDraftError? validatePlanStep(PlanStepSnapshot s) {
  final title = s.title.trim();
  if (title.isEmpty) return PlanDraftError.titleRequired;
  if (title.length > PlanLimits.maxTitleLength) {
    return PlanDraftError.titleTooLong;
  }
  if (s.description.length > PlanLimits.maxDescriptionLength) {
    return PlanDraftError.descriptionTooLong;
  }
  final start = s.startAt;
  final end = s.endAt;
  if (start != null && end != null && end.isBefore(start)) {
    return PlanDraftError.endBeforeStart;
  }
  return null;
}
