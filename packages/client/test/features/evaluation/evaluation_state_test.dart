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
    expect(s.canFinalize, isFalse);
  });

  test('reviewedCount is zero when no participant answered', () {
    const s = EvaluationState(
      beaconId: 'B1',
      participants: [
        EvaluationParticipant(
          userId: 'U1',
          displayName: 'A',
          role: EvaluationParticipantRole.author,
          contributionSummary: '',
          causalHint: '',
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
    expect(s.reviewedCount, 0);
    expect(s.canFinalize, isFalse);
  });

  test('canFinalize when every participant answered', () {
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
          currentValue: EvaluationValue.neg1,
        ),
      ],
    );
    expect(s.reviewedCount, 2);
    expect(s.canFinalize, isTrue);
  });
}
