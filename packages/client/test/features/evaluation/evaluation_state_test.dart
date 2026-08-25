import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/bloc/evaluation_state.dart';

void main() {
  test('live progress counts only submitted rows', () {
    const state = EvaluationState(
      beaconId: 'B1',
      participants: [
        EvaluationParticipant(
          userId: 'U1',
          displayName: 'A',
          role: EvaluationParticipantRole.author,
          contributionSummary: '',
          causalHint: '',
          currentValue: EvaluationValue.pos1,
          isSubmitted: true,
        ),
        EvaluationParticipant(
          userId: 'U2',
          displayName: 'B',
          role: EvaluationParticipantRole.committer,
          contributionSummary: '',
          causalHint: '',
          currentValue: EvaluationValue.pos1,
        ),
      ],
    );
    expect(state.reviewedCount, 1);
    expect(state.canFinalize, isFalse);
  });

  test('draft progress counts answered rows', () {
    const state = EvaluationState(
      beaconId: 'B1',
      isDraftMode: true,
      participants: [
        EvaluationParticipant(
          userId: 'U1',
          displayName: 'A',
          role: EvaluationParticipantRole.author,
          contributionSummary: '',
          causalHint: '',
          currentValue: EvaluationValue.noBasis,
        ),
      ],
    );
    expect(state.reviewedCount, 1);
    expect(state.canFinalize, isTrue);
  });

  test('live canFinalize requires every row ready', () {
    const state = EvaluationState(
      beaconId: 'B1',
      participants: [
        EvaluationParticipant(
          userId: 'U1',
          displayName: 'A',
          role: EvaluationParticipantRole.author,
          contributionSummary: '',
          causalHint: '',
          currentValue: EvaluationValue.pos1,
          isSubmitted: true,
        ),
        EvaluationParticipant(
          userId: 'U2',
          displayName: 'B',
          role: EvaluationParticipantRole.committer,
          contributionSummary: '',
          causalHint: '',
          currentValue: EvaluationValue.neg1,
          isSubmitted: true,
        ),
      ],
    );
    expect(state.reviewedCount, 2);
    expect(state.canFinalize, isTrue);
  });
}
