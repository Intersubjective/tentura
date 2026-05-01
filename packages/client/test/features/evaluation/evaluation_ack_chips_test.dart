import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_detail_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Scrolls to [finder] inside the bottom sheet's [SingleChildScrollView],
/// then taps it.
Future<void> _scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Helper: pump a minimal app that opens [showEvaluationDetailSheet]
/// immediately via an [ElevatedButton].
Future<void> _pumpSheet({
  required WidgetTester tester,
  required EvaluationParticipant participant,
  required Future<void> Function(
    EvaluationValue,
    List<String>,
    String,
    List<String>,
  ) onSave,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 900)),
        child: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              key: const Key('open_sheet'),
              onPressed: () => showEvaluationDetailSheet(
                context: context,
                participant: participant,
                onSave: onSave,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.byKey(const Key('open_sheet')));
  await tester.pumpAndSettle();
}

void main() {
  const participant = EvaluationParticipant(
    userId: 'u1',
    title: 'Alice',
    role: EvaluationParticipantRole.committer,
    contributionSummary: 'Helped with packing',
    causalHint: 'via beacon B1',
  );

  testWidgets(
    'close-ack section is visible inside the sheet',
    (tester) async {
      await _pumpSheet(
        tester: tester,
        participant: participant,
        onSave: (v, tags, note, ackTags) async {},
      );

      // Scroll to the ack prompt so it is in view.
      await tester.ensureVisible(
        find.text('What did this person actually help with?'),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('What did this person actually help with?'),
        findsOneWidget,
      );

      // The CapabilityChipSet renders FilterChips for every CapabilityTag.
      // "Transport" (first logistics chip) must be present somewhere in the tree.
      await tester.ensureVisible(find.text('Transport').first);
      await tester.pumpAndSettle();
      expect(find.text('Transport'), findsWidgets);
    },
  );

  testWidgets(
    'tapping a capability chip and saving passes acknowledgedHelpTags',
    (tester) async {
      List<String>? capturedAckTags;

      await _pumpSheet(
        tester: tester,
        participant: participant,
        onSave: (v, tags, note, ackTags) async {
          capturedAckTags = ackTags;
        },
      );

      // Scroll to Transport chip and tap it.
      await _scrollAndTap(tester, find.text('Transport').first);

      // Scroll to the Save button and tap it.
      await _scrollAndTap(tester, find.text('Save'));

      expect(capturedAckTags, isNotNull);
      expect(capturedAckTags, contains('transport'));
    },
  );

  testWidgets(
    'saving with no chip selected passes empty acknowledgedHelpTags',
    (tester) async {
      List<String>? capturedAckTags;

      await _pumpSheet(
        tester: tester,
        participant: participant,
        onSave: (v, tags, note, ackTags) async {
          capturedAckTags = ackTags;
        },
      );

      // No chip tapped — go straight to Save.
      await _scrollAndTap(tester, find.text('Save'));

      expect(capturedAckTags, isNotNull);
      expect(capturedAckTags, isEmpty);
    },
  );

  testWidgets(
    'multiple chip selections are all forwarded in acknowledgedHelpTags',
    (tester) async {
      List<String>? capturedAckTags;

      await _pumpSheet(
        tester: tester,
        participant: participant,
        onSave: (v, tags, note, ackTags) async {
          capturedAckTags = ackTags;
        },
      );

      await _scrollAndTap(tester, find.text('Transport').first);
      await _scrollAndTap(tester, find.text('Money').first);
      await _scrollAndTap(tester, find.text('Save'));

      expect(capturedAckTags, isNotNull);
      expect(capturedAckTags, containsAll(['transport', 'money']));
      expect(capturedAckTags!.length, 2);
    },
  );

  testWidgets(
    'deselecting a chip removes it from acknowledgedHelpTags',
    (tester) async {
      List<String>? capturedAckTags;

      await _pumpSheet(
        tester: tester,
        participant: participant,
        onSave: (v, tags, note, ackTags) async {
          capturedAckTags = ackTags;
        },
      );

      // Select then deselect Transport.
      await _scrollAndTap(tester, find.text('Transport').first);
      await _scrollAndTap(tester, find.text('Transport').first);

      await _scrollAndTap(tester, find.text('Save'));

      expect(capturedAckTags, isNotNull);
      expect(capturedAckTags, isNot(contains('transport')));
    },
  );
}
