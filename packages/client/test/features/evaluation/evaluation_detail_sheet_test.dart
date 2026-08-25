import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
    causalHint: 'via old request',
    maxAcknowledgedHelpTags: 3,
    acknowledgeableHelpTags: ['transport', 'food', 'tools'],
  );
  testWidgets('missing impact keeps sheet open and shows inline feedback', (
    tester,
  ) async {
    await pumpEvaluationDetailSheet(
      tester: tester,
      participant: participant,
      onSave: (_, __, ___) async => true,
    );
    await evaluationScrollAndTap(tester, evaluationSaveButton());
    expect(find.text('Choose an impact.'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('renders exactly five impact choices and no legacy authoring', (
    tester,
  ) async {
    await pumpEvaluationDetailSheet(
      tester: tester,
      participant: participant,
      onSave: (_, __, ___) async => true,
    );
    expect(
      find.byKey(
        TestIds.key(TestIds.evaluationImpact(EvaluationValue.pos2.name)),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        TestIds.key(TestIds.evaluationImpact(EvaluationValue.pos1.name)),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        TestIds.key(TestIds.evaluationImpact(EvaluationValue.zero.name)),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        TestIds.key(TestIds.evaluationImpact(EvaluationValue.neg1.name)),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        TestIds.key(TestIds.evaluationImpact(EvaluationValue.neg2.name)),
      ),
      findsOneWidget,
    );
    expect(find.text('No basis'), findsNothing);
    expect(find.textContaining('trust'), findsNothing);
    expect(find.textContaining('reason'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('saved noBasis opens with no impact selected', (tester) async {
    await pumpEvaluationDetailSheet(
      tester: tester,
      participant: participant.copyWith(currentValue: EvaluationValue.noBasis),
      onSave: (_, __, ___) async => true,
    );
    final semantics = tester.getSemantics(
      find.byKey(
        TestIds.key(TestIds.evaluationImpact(EvaluationValue.zero.name)),
      ),
    );
    expect(semantics.hasFlag(SemanticsFlag.isSelected), isFalse);
  });

  testWidgets('save omits reasons and returns note and acknowledgements', (
    tester,
  ) async {
    EvaluationValue? value;
    String? note;
    List<String>? ack;
    await pumpEvaluationDetailSheet(
      tester: tester,
      participant: participant,
      onSave: (v, n, a) async {
        value = v;
        note = n;
        ack = a;
        return true;
      },
    );
    await evaluationSelectImpact(tester, 'Helped somewhat');
    await tester.enterText(find.byType(TextField), 'A short note');
    await evaluationScrollAndTap(
      tester,
      find.byKey(TestIds.key(TestIds.evaluationCapabilityField)),
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await evaluationScrollAndTap(tester, evaluationSaveButton());
    expect(value, EvaluationValue.pos1);
    expect(note, 'A short note');
    expect(ack, isEmpty);
  });

  testWidgets('negative selection clears acknowledgement disclosure', (
    tester,
  ) async {
    await pumpEvaluationDetailSheet(
      tester: tester,
      participant: participant.copyWith(
        currentValue: EvaluationValue.pos1,
        isSubmitted: true,
        acknowledgedHelpTags: const ['transport'],
      ),
      onSave: (_, __, ___) async => true,
    );
    expect(
      find.byKey(TestIds.key(TestIds.evaluationCapabilityField)),
      findsOneWidget,
    );
    await evaluationSelectImpact(tester, 'Hurt somewhat');
    expect(
      find.byKey(TestIds.key(TestIds.evaluationCapabilityField)),
      findsNothing,
    );
  });

  testWidgets('failed save leaves sheet open and second tap is blocked', (
    tester,
  ) async {
    var calls = 0;
    final firstResult = Completer<bool>();
    final results = <Future<bool>>[
      firstResult.future,
      Future<bool>.value(true),
    ];
    await pumpEvaluationDetailSheet(
      tester: tester,
      participant: participant,
      onSave: (_, __, ___) async {
        calls++;
        return results.removeAt(0);
      },
    );
    await evaluationSelectImpact(tester, 'No real effect');
    await tester.tap(evaluationSaveButton());
    await tester.pump();
    expect(
      tester.widget<FilledButton>(evaluationSaveButton()).onPressed,
      isNull,
    );
    await tester.pump();
    expect(calls, 1);
    expect(
      tester.widget<FilledButton>(evaluationSaveButton()).onPressed,
      isNull,
    );
    await tester.tap(evaluationSaveButton(), warnIfMissed: false);
    expect(calls, 1);
    firstResult.complete(false);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      tester.widget<FilledButton>(evaluationSaveButton()).onPressed,
      isNotNull,
    );
    await tester.tap(evaluationSaveButton());
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(BottomSheet), findsNothing);
  });

  for (final change
      in <({String name, Future<void> Function(WidgetTester) edit})>[
        (
          name: 'impact',
          edit: (tester) => evaluationSelectImpact(tester, 'Helped a lot'),
        ),
        (
          name: 'capability',
          edit: (tester) async {
            await evaluationScrollAndTap(
              tester,
              find.byKey(TestIds.key(TestIds.evaluationCapabilityField)),
            );
            await evaluationScrollAndTap(tester, find.text('Logistics'));
            await evaluationScrollAndTap(
              tester,
              find.byKey(TestIds.key(TestIds.capabilityChip('transport'))),
            );
            await evaluationScrollAndTap(
              tester,
              find.byKey(TestIds.key(TestIds.evaluationCapabilityDone)),
            );
          },
        ),
        (
          name: 'note',
          edit: (tester) async {
            await tester.enterText(find.byType(TextField), 'A private note');
          },
        ),
      ]) {
    testWidgets('dirty ${change.name} dismissal requires confirmation', (
      tester,
    ) async {
      await pumpEvaluationDetailSheet(
        tester: tester,
        participant: participant.copyWith(currentValue: EvaluationValue.pos1),
        onSave: (_, __, ___) async => true,
      );
      await change.edit(tester);
      if (change.name == 'note') {
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(find.text('Return to editing'), findsOneWidget);
      await tester.tap(find.text('Return to editing'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      if (change.name == 'note') {
        expect(find.text('A private note'), findsOneWidget);
      }
    });
  }

  testWidgets('note field has exactly 280 character maximum', (tester) async {
    await pumpEvaluationDetailSheet(
      tester: tester,
      participant: participant,
      onSave: (_, __, ___) async => true,
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLength, 280);
    await tester.enterText(find.byType(TextField), 'x' * 400);
    expect(find.text('x' * 280), findsOneWidget);
    expect(find.text('x' * 281), findsNothing);
  });

  testWidgets(
    'keyboard inset and large text keep Save reachable without errors',
    (
      tester,
    ) async {
      await pumpEvaluationDetailSheet(
        tester: tester,
        participant: participant,
        size: const Size(320, 480),
        textScaler: const TextScaler.linear(2.0),
        viewInsets: const EdgeInsets.only(bottom: 280),
        onSave: (_, __, ___) async => true,
      );
      await evaluationScrollAndTap(tester, evaluationSaveButton());
      expect(find.text('Choose an impact.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final values in <({EvaluationValue saved, EvaluationValue chosen})>[
    (saved: EvaluationValue.pos1, chosen: EvaluationValue.pos2),
    (saved: EvaluationValue.pos2, chosen: EvaluationValue.pos1),
  ]) {
    testWidgets(
      'saved ${values.saved.name} changing to ${values.chosen.name} retains acknowledgements',
      (tester) async {
        EvaluationValue? result;
        List<String>? acknowledgements;
        await pumpEvaluationDetailSheet(
          tester: tester,
          participant: participant.copyWith(
            currentValue: values.saved,
            isSubmitted: true,
            acknowledgedHelpTags: const ['transport'],
          ),
          onSave: (value, _, tags) async {
            result = value;
            acknowledgements = tags;
            return true;
          },
        );
        await evaluationSelectImpact(
          tester,
          values.chosen == EvaluationValue.pos1
              ? 'Helped somewhat'
              : 'Helped a lot',
        );
        await evaluationScrollAndTap(tester, evaluationSaveButton());
        expect(result, values.chosen);
        expect(acknowledgements, ['transport']);
      },
    );
  }

  testWidgets(
    'saved positive changing to non-positive saves empty acknowledgements',
    (
      tester,
    ) async {
      List<String>? acknowledgements;
      await pumpEvaluationDetailSheet(
        tester: tester,
        participant: participant.copyWith(
          currentValue: EvaluationValue.pos1,
          isSubmitted: true,
          acknowledgedHelpTags: const ['transport'],
        ),
        onSave: (_, __, tags) async {
          acknowledgements = tags;
          return true;
        },
      );
      await evaluationSelectImpact(tester, 'No real effect');
      await evaluationScrollAndTap(tester, evaluationSaveButton());
      expect(acknowledgements, isEmpty);
    },
  );

  testWidgets(
    'capability Cancel keeps parent selection and Save returns original',
    (
      tester,
    ) async {
      List<String>? acknowledgements;
      await pumpEvaluationDetailSheet(
        tester: tester,
        participant: participant.copyWith(
          currentValue: EvaluationValue.pos1,
          isSubmitted: true,
          acknowledgedHelpTags: const ['transport'],
        ),
        onSave: (_, __, tags) async {
          acknowledgements = tags;
          return true;
        },
      );
      await evaluationScrollAndTap(
        tester,
        find.byKey(TestIds.key(TestIds.evaluationCapabilityField)),
      );
      await evaluationScrollAndTap(tester, find.text('Resources'));
      await evaluationScrollAndTap(
        tester,
        find.byKey(TestIds.key(TestIds.capabilityChip('food'))),
      );
      await evaluationScrollAndTap(
        tester,
        find.byKey(TestIds.key(TestIds.evaluationCapabilityCancel)),
      );
      expect(find.text('Transport'), findsOneWidget);
      await evaluationScrollAndTap(tester, evaluationSaveButton());
      expect(acknowledgements, ['transport']);
    },
  );

  testWidgets(
    'compact dirty sheet drag asks confirmation then can discard',
    (
      tester,
    ) async {
      var saveCalls = 0;
      await pumpEvaluationDetailSheet(
        tester: tester,
        participant: participant,
        size: const Size(320, 700),
        onSave: (_, __, ___) async {
          saveCalls++;
          return true;
        },
      );
      await evaluationSelectImpact(tester, 'Helped a lot');
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.enableDrag, isTrue);
      expect(sheet.showDragHandle, isTrue);

      // Content is scrollable; dismiss drag must start on the drag handle.
      final handle = find.bySemanticsLabel('Dismiss');
      expect(handle, findsWidgets);
      await tester.timedDrag(
        handle.first,
        const Offset(0, 500),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Return to editing'), findsOneWidget);
      expect(find.text('Leave and discard'), findsOneWidget);
      expect(
        tester
            .getSemantics(
              find.byKey(
                TestIds.key(
                  TestIds.evaluationImpact(EvaluationValue.pos2.name),
                ),
              ),
            )
            .hasFlag(SemanticsFlag.isSelected),
        isTrue,
      );
      expect(saveCalls, 0);

      await tester.tap(find.text('Leave and discard'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(saveCalls, 0);
    },
  );
}
