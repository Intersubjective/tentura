import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/bloc/evaluation_state.dart';
import 'package:tentura/ui/bloc/state_base.dart';

void main() {
  test('reviewedCount counts answered cards', () {
    final s = EvaluationState(
      beaconId: 'B1',
      participants: [
        EvaluationParticipant(
          userId: 'U1',
          title: 'A',
          role: EvaluationParticipantRole.author,
          contributionSummary: '',
          causalHint: '',
          currentValue: EvaluationValue.pos1,
        ),
        EvaluationParticipant(
          userId: 'U2',
          title: 'B',
          role: EvaluationParticipantRole.committer,
          contributionSummary: '',
          causalHint: '',
        ),
      ],
      status: const StateIsSuccess(),
    );
    expect(s.reviewedCount, 1);
    expect(s.totalCount, 2);
  });
}
