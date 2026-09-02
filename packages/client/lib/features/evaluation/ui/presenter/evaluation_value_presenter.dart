import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class EvaluationValuePresentation {
  const EvaluationValuePresentation(this.label, this.emoji);

  final String label;
  final String emoji;
}

EvaluationValuePresentation presentEvaluationValue(
  EvaluationValue value,
  L10n l10n,
) => switch (value) {
  EvaluationValue.pos2 => EvaluationValuePresentation(
    l10n.evaluationImpactHelpedALot,
    '🤩',
  ),
  EvaluationValue.pos1 => EvaluationValuePresentation(
    l10n.evaluationImpactHelpedSomewhat,
    '👍',
  ),
  EvaluationValue.zero => EvaluationValuePresentation(
    l10n.evaluationImpactNoRealEffect,
    '🤷',
  ),
  EvaluationValue.neg1 => EvaluationValuePresentation(
    l10n.evaluationImpactHurtSomewhat,
    '👎',
  ),
  EvaluationValue.neg2 => EvaluationValuePresentation(
    l10n.evaluationImpactHurtALot,
    '😠',
  ),
  EvaluationValue.noBasis => EvaluationValuePresentation(
    l10n.evaluationNoBasisLabel,
    '❔',
  ),
};

List<EvaluationValue> evaluationImpactValues() => const [
  EvaluationValue.pos2,
  EvaluationValue.pos1,
  EvaluationValue.zero,
  EvaluationValue.neg1,
  EvaluationValue.neg2,
];
