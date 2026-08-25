import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/ui/test_ids.dart';

import 'evaluation_sheet_test_support.dart';

void main() {
  const participant = EvaluationParticipant(
    userId: 'u1',
    displayName: 'Alice',
    role: EvaluationParticipantRole.committer,
    contributionSummary: 'Helped with packing',
    causalHint: '',
    isSubmitted: true,
    currentValue: EvaluationValue.pos1,
    acknowledgedHelpTags: ['transport'],
    acknowledgeableHelpTags: ['transport', 'food', 'tools', 'writing'],
    maxAcknowledgedHelpTags: 3,
  );

  testWidgets('positive live row preloads and filters acknowledgement picker', (
    tester,
  ) async {
    await pumpEvaluationDetailSheet(
      tester: tester,
      participant: participant,
      onSave: (_, __, ___) async => true,
    );
    expect(
      find.byKey(TestIds.key(TestIds.evaluationCapabilityField)),
      findsOneWidget,
    );
    await evaluationScrollAndTap(
      tester,
      find.byKey(TestIds.key(TestIds.evaluationCapabilityField)),
    );
    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('Food'), findsNothing);
    expect(find.text('Writing'), findsNothing);
  });

  testWidgets('draft and non-positive rows hide acknowledgement field', (
    tester,
  ) async {
    for (final value in [EvaluationValue.zero, EvaluationValue.neg1]) {
      await pumpEvaluationDetailSheet(
        tester: tester,
        participant: participant.copyWith(currentValue: value),
        onSave: (_, __, ___) async => true,
      );
      expect(
        find.byKey(TestIds.key(TestIds.evaluationCapabilityField)),
        findsNothing,
      );
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
    }
  });
}
