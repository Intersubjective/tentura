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
          rowStatus: 1,
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
          rowStatus: 1,
        ),
        EvaluationParticipant(
          userId: 'U2',
          displayName: 'B',
          role: EvaluationParticipantRole.committer,
          contributionSummary: '',
          causalHint: '',
          currentValue: EvaluationValue.neg1,
          isSubmitted: true,
          rowStatus: 1,
        ),
      ],
    );
    expect(state.reviewedCount, 2);
    expect(state.canFinalize, isTrue);
  });

  test('canFinalize ignores optional targets', () {
    const state = EvaluationState(
      beaconId: 'B1',
      participants: [
        EvaluationParticipant(
          userId: 'U1',
          displayName: 'A',
          role: EvaluationParticipantRole.committer,
          rowStatus: 1,
        ),
        EvaluationParticipant(
          userId: 'U2',
          displayName: 'B',
          role: EvaluationParticipantRole.formerCommitter,
          isOptional: true,
          rowStatus: -1,
        ),
      ],
    );
    expect(state.requiredParticipants.map((p) => p.userId), ['U1']);
    expect(state.optionalParticipants.map((p) => p.userId), ['U2']);
    expect(state.canFinalize, isTrue);
  });

  test('a package of only optional targets is finalizable unanswered', () {
    const state = EvaluationState(
      beaconId: 'B1',
      participants: [
        EvaluationParticipant(
          userId: 'U2',
          displayName: 'B',
          role: EvaluationParticipantRole.formerCommitter,
          isOptional: true,
        ),
      ],
    );
    expect(state.canFinalize, isTrue);
  });

  test('canFinalize still requires every required target', () {
    const state = EvaluationState(
      beaconId: 'B1',
      participants: [
        EvaluationParticipant(
          userId: 'U1',
          displayName: 'A',
          role: EvaluationParticipantRole.committer,
          rowStatus: 2,
        ),
        EvaluationParticipant(
          userId: 'U2',
          displayName: 'B',
          role: EvaluationParticipantRole.committer,
          rowStatus: -1,
        ),
      ],
    );
    expect(state.canFinalize, isFalse);
  });

  test('empty participants are not finalizable', () {
    const state = EvaluationState(beaconId: 'B1');
    expect(state.canFinalize, isFalse);
    const draft = EvaluationState(beaconId: 'B1', isDraftMode: true);
    expect(draft.canFinalize, isFalse);
  });

  test('hasAnswer covers draft, submitted and final only', () {
    const base = EvaluationParticipant(
      userId: 'U1',
      displayName: 'A',
      role: EvaluationParticipantRole.committer,
    );
    expect(base.copyWith(rowStatus: 0).hasAnswer, isTrue);
    expect(base.copyWith(rowStatus: 1).hasAnswer, isTrue);
    expect(base.copyWith(rowStatus: 2).hasAnswer, isTrue);
    expect(base.copyWith(rowStatus: -1).hasAnswer, isFalse);
    expect(base.copyWith(rowStatus: 3).hasAnswer, isFalse);
    expect(base.copyWith(rowStatus: 4).hasAnswer, isFalse);
  });
}
