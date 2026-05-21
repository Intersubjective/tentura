import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/bloc/evaluation_state.dart';

void main() {
  test('reviewedCount counts answered cards', () {
    const s = EvaluationState(
      beaconId: 'B1',
      participants: [
        EvaluationParticipant(
          userId: 'U1',
          displayName: 'A',
          role: EvaluationParticipantRole.author,
          contributionSummary: '',
          causalHint: '',
          currentValue: EvaluationValue.pos1,
        ),
        EvaluationParticipant(
          userId: 'U2',
          displayName: 'B',
          role: EvaluationParticipantRole.committer,
          contributionSummary: '',
          causalHint: '',
        ),
      ],
    );
    expect(s.reviewedCount, 1);
    expect(s.totalCount, 2);
  });
}
