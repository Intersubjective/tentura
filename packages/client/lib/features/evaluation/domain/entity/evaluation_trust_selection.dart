import 'evaluation_value.dart';

/// UI selection state for the contribution-grounded trust control.
enum EvaluationTrustSelection {
  unselected,
  noBasis,
  zero,
  decreasePending,
  neg1,
  neg2,
  increasePending,
  pos1,
  pos2,
}

extension EvaluationTrustSelectionX on EvaluationTrustSelection {
  bool get isComplete => switch (this) {
        EvaluationTrustSelection.unselected ||
        EvaluationTrustSelection.decreasePending ||
        EvaluationTrustSelection.increasePending =>
          false,
        _ => true,
      };

  bool get showsReasonCard => switch (this) {
        EvaluationTrustSelection.neg1 ||
        EvaluationTrustSelection.neg2 ||
        EvaluationTrustSelection.pos1 ||
        EvaluationTrustSelection.pos2 =>
          true,
        _ => false,
      };

  bool get isDecreaseDirection => switch (this) {
        EvaluationTrustSelection.decreasePending ||
        EvaluationTrustSelection.neg1 ||
        EvaluationTrustSelection.neg2 =>
          true,
        _ => false,
      };

  bool get isIncreaseDirection => switch (this) {
        EvaluationTrustSelection.increasePending ||
        EvaluationTrustSelection.pos1 ||
        EvaluationTrustSelection.pos2 =>
          true,
        _ => false,
      };

  EvaluationValue? get evaluationValue => switch (this) {
        EvaluationTrustSelection.noBasis => EvaluationValue.noBasis,
        EvaluationTrustSelection.zero => EvaluationValue.zero,
        EvaluationTrustSelection.neg1 => EvaluationValue.neg1,
        EvaluationTrustSelection.neg2 => EvaluationValue.neg2,
        EvaluationTrustSelection.pos1 => EvaluationValue.pos1,
        EvaluationTrustSelection.pos2 => EvaluationValue.pos2,
        _ => null,
      };

  static EvaluationTrustSelection fromEvaluationValue(EvaluationValue? value) {
    if (value == null) {
      return EvaluationTrustSelection.unselected;
    }
    return switch (value) {
      EvaluationValue.noBasis => EvaluationTrustSelection.noBasis,
      EvaluationValue.zero => EvaluationTrustSelection.zero,
      EvaluationValue.neg1 => EvaluationTrustSelection.neg1,
      EvaluationValue.neg2 => EvaluationTrustSelection.neg2,
      EvaluationValue.pos1 => EvaluationTrustSelection.pos1,
      EvaluationValue.pos2 => EvaluationTrustSelection.pos2,
    };
  }
}
