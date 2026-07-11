import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';

import 'evaluation_sheet_test_support.dart';

void main() {
  const participant = EvaluationParticipant(
    userId: 'u1',
    displayName: 'Alice',
    role: EvaluationParticipantRole.committer,
    contributionSummary: 'Helped with packing',
    causalHint: 'via beacon B1',
  );

  testWidgets(
    'close-ack section is visible inside the sheet',
    (tester) async {
      await pumpEvaluationDetailSheet(
        tester: tester,
        participant: participant,
        onSave: (_, __, ___, ____) async => true,
      );

      await evaluationSelectNoChange(tester);

      await tester.ensureVisible(
        find.text('What did this person actually help with?'),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('What did this person actually help with?'),
        findsOneWidget,
      );

      await tester.tap(find.text('Logistics'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Transport').first);
      await tester.pumpAndSettle();
      expect(find.text('Transport'), findsWidgets);
    },
  );

  testWidgets(
    'tapping a capability chip and saving passes acknowledgedHelpTags',
    (tester) async {
      List<String>? capturedAckTags;

      await pumpEvaluationDetailSheet(
        tester: tester,
        participant: participant,
        onSave: (v, tags, note, ackTags) async {
          capturedAckTags = ackTags;
          return true;
        },
      );

      await evaluationSelectNoChange(tester);
      await evaluationScrollAndTap(tester, find.text('Logistics'));
      await evaluationScrollAndTap(tester, find.text('Transport').first);
      await evaluationScrollAndTap(tester, find.text('Save'));

      expect(capturedAckTags, isNotNull);
      expect(capturedAckTags, contains('transport'));
    },
  );

  testWidgets(
    'saving with no chip selected passes empty acknowledgedHelpTags',
    (tester) async {
      List<String>? capturedAckTags;

      await pumpEvaluationDetailSheet(
        tester: tester,
        participant: participant,
        onSave: (v, tags, note, ackTags) async {
          capturedAckTags = ackTags;
          return true;
        },
      );

      await evaluationSelectNoChange(tester);
      await evaluationScrollAndTap(tester, find.text('Save'));

      expect(capturedAckTags, isNotNull);
      expect(capturedAckTags, isEmpty);
    },
  );

  testWidgets(
    'multiple chip selections are all forwarded in acknowledgedHelpTags',
    (tester) async {
      List<String>? capturedAckTags;

      await pumpEvaluationDetailSheet(
        tester: tester,
        participant: participant,
        onSave: (v, tags, note, ackTags) async {
          capturedAckTags = ackTags;
          return true;
        },
      );

      await evaluationSelectNoChange(tester);
      await evaluationScrollAndTap(tester, find.text('Logistics'));
      await evaluationScrollAndTap(tester, find.text('Transport').first);
      await evaluationScrollAndTap(tester, find.text('Resources'));
      await evaluationScrollAndTap(tester, find.text('Money').first);
      await evaluationScrollAndTap(tester, find.text('Save'));

      expect(capturedAckTags, isNotNull);
      expect(capturedAckTags, containsAll(['transport', 'money']));
      expect(capturedAckTags!.length, 2);
    },
  );

  testWidgets(
    'deselecting a chip removes it from acknowledgedHelpTags',
    (tester) async {
      List<String>? capturedAckTags;

      await pumpEvaluationDetailSheet(
        tester: tester,
        participant: participant,
        onSave: (v, tags, note, ackTags) async {
          capturedAckTags = ackTags;
          return true;
        },
      );

      await evaluationSelectNoChange(tester);
      await evaluationScrollAndTap(tester, find.text('Logistics'));
      await evaluationScrollAndTap(tester, find.text('Transport').first);
      await evaluationScrollAndTap(tester, find.text('Transport').first);
      await evaluationScrollAndTap(tester, find.text('Save'));

      expect(capturedAckTags, isNotNull);
      expect(capturedAckTags, isNot(contains('transport')));
    },
  );
}
