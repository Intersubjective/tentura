import 'package:flutter/material.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class EvaluationValuePresentation {
  const EvaluationValuePresentation(this.label, this.icon);

  final String label;
  final IconData icon;
}

EvaluationValuePresentation presentEvaluationValue(
  EvaluationValue value,
  L10n l10n,
) => switch (value) {
  EvaluationValue.pos2 => EvaluationValuePresentation(
    l10n.evaluationImpactHelpedALot,
    Icons.keyboard_double_arrow_up_rounded,
  ),
  EvaluationValue.pos1 => EvaluationValuePresentation(
    l10n.evaluationImpactHelpedSomewhat,
    Icons.arrow_upward_rounded,
  ),
  EvaluationValue.zero => EvaluationValuePresentation(
    l10n.evaluationImpactNoRealEffect,
    Icons.remove_rounded,
  ),
  EvaluationValue.neg1 => EvaluationValuePresentation(
    l10n.evaluationImpactHurtSomewhat,
    Icons.arrow_downward_rounded,
  ),
  EvaluationValue.neg2 => EvaluationValuePresentation(
    l10n.evaluationImpactHurtALot,
    Icons.keyboard_double_arrow_down_rounded,
  ),
  EvaluationValue.noBasis => EvaluationValuePresentation(
    l10n.evaluationNoBasisLabel,
    Icons.help_outline_rounded,
  ),
};

List<EvaluationValue> evaluationImpactValues() => const [
  EvaluationValue.pos2,
  EvaluationValue.pos1,
  EvaluationValue.zero,
  EvaluationValue.neg1,
  EvaluationValue.neg2,
];
