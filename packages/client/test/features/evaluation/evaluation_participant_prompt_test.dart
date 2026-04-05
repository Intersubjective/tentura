import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';

void main() {
  test('promptVariant handoff is preserved on participant', () {
    const p = EvaluationParticipant(
      userId: 'u',
      title: 't',
      role: EvaluationParticipantRole.committer,
      contributionSummary: '',
      causalHint: '',
      promptVariant: 'handoff',
    );
    expect(p.promptVariant, 'handoff');
    expect(p.hasAnswered, false);
  });

  test('default promptVariant is full', () {
    const p = EvaluationParticipant(
      userId: 'u',
      title: 't',
      role: EvaluationParticipantRole.author,
      contributionSummary: '',
      causalHint: '',
      currentValue: EvaluationValue.pos1,
    );
    expect(p.promptVariant, 'full');
  });
}
