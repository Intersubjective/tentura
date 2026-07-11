import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_trust_selection.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_detail_sheet.dart';

import 'evaluation_sheet_test_support.dart';
import 'package:tentura/ui/test_ids.dart';

void main() {
  const participant = EvaluationParticipant(
    userId: 'u1',
    displayName: 'Alice',
    role: EvaluationParticipantRole.committer,
    contributionSummary: 'Helped with packing',
    causalHint: 'via request B1',
  );

  test('EvaluationTrustSelection maps to EvaluationValue', () {
    expect(
      EvaluationTrustSelectionX.fromEvaluationValue(null),
      EvaluationTrustSelection.unselected,
    );
    expect(
      EvaluationTrustSelection.pos2.evaluationValue,
      EvaluationValue.pos2,
    );
    expect(EvaluationTrustSelection.decreasePending.isComplete, isFalse);
    expect(EvaluationTrustSelection.pos1.showsReasonCard, isTrue);
  });

  testWidgets('save without selection shows category error', (tester) async {
    await pumpEvaluationDetailSheet(
      tester: tester,
      participant: participant,
      onSave: (_, __, ___, ____) async => true,
    );

    await evaluationScrollAndTap(tester, find.text('Save'));
    expect(
      find.text('Choose how this contribution affected your trust.'),
      findsOneWidget,
    );
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('pending intensity shows error on save', (tester) async {
    await pumpEvaluationDetailSheet(
      tester: tester,
      participant: participant,
      onSave: (_, __, ___, ____) async => true,
    );

    await evaluationScrollAndTap(
      tester,
      find.text('My trust in this person decreased'),
    );
    await evaluationScrollAndTap(tester, find.text('Save'));

    expect(
      find.text('Choose how much your trust changed.'),
      findsOneWidget,
    );
  });

  testWidgets('pos2 without reason shows validation error', (tester) async {
    await pumpEvaluationDetailSheet(
      tester: tester,
      participant: participant,
      onSave: (_, __, ___, ____) async => true,
    );

    await evaluationScrollAndTap(
      tester,
      find.text('My trust in this person increased'),
    );
    await evaluationScrollAndTap(tester, find.text('A lot (reason required)'));
    await evaluationScrollAndTap(tester, find.text('Save'));

    expect(find.text('Choose at least one reason.'), findsOneWidget);
  });

  testWidgets('changing pos2 to neg1 clears incompatible reason tags', (
    tester,
  ) async {
    List<String>? capturedTags;

    await pumpEvaluationDetailSheet(
      tester: tester,
      participant: participant,
      onSave: (_, tags, __, ___) async {
        capturedTags = tags;
        return true;
      },
    );

    await evaluationScrollAndTap(
      tester,
      find.text('My trust in this person increased'),
    );
    await evaluationScrollAndTap(tester, find.text('A lot (reason required)'));
    await evaluationScrollAndTap(tester, find.text('Very useful'));
    await evaluationScrollAndTap(
      tester,
      find.text('My trust in this person decreased'),
    );
    await evaluationScrollAndTap(tester, find.text('A little (reason required)'));
    await evaluationScrollAndTap(tester, find.text('Did not follow through'));
    await evaluationScrollAndTap(tester, find.text('Save'));

    expect(capturedTags, isNotNull);
    expect(capturedTags, contains('did_not_follow_through'));
    expect(capturedTags, isNot(contains('very_useful')));
  });

  testWidgets('neg1 to zero clears all reason tags', (tester) async {
    List<String>? capturedTags;
    EvaluationValue? capturedValue;

    await pumpEvaluationDetailSheet(
      tester: tester,
      participant: participant,
      onSave: (v, tags, __, ___) async {
        capturedValue = v;
        capturedTags = tags;
        return true;
      },
    );

    await evaluationScrollAndTap(
      tester,
      find.text('My trust in this person decreased'),
    );
    await evaluationScrollAndTap(tester, find.text('A little (reason required)'));
    await evaluationScrollAndTap(tester, find.text('Did not follow through'));
    await evaluationScrollAndTap(
      tester,
      find.text('This contribution did not change my trust'),
    );
    await evaluationScrollAndTap(tester, find.text('Save'));

    expect(capturedValue, EvaluationValue.zero);
    expect(capturedTags, isEmpty);
  });

  testWidgets('onSave returning false keeps sheet open', (tester) async {
    await pumpEvaluationDetailSheet(
      tester: tester,
      participant: participant,
      onSave: (_, __, ___, ____) async => false,
    );

    await evaluationSelectNoBasis(tester);
    await evaluationScrollAndTap(tester, find.text('Save'));

    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('onSave returning true closes sheet', (tester) async {
    await pumpEvaluationDetailSheet(
      tester: tester,
      participant: participant,
      onSave: (_, __, ___, ____) async => true,
    );

    await evaluationSelectNoBasis(tester);
    await evaluationScrollAndTap(tester, find.text('Save'));

    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('double submit is blocked while saving', (tester) async {
    var saveCalls = 0;

    await pumpEvaluationDetailSheet(
      tester: tester,
      participant: participant,
      onSave: (_, __, ___, ____) async {
        saveCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return true;
      },
    );

    await evaluationSelectNoBasis(tester);
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.byKey(TestIds.key(TestIds.evaluationSave)),
    );
    expect(button.onPressed, isNull);
    await tester.pumpAndSettle();

    expect(saveCalls, 1);
  });
}
