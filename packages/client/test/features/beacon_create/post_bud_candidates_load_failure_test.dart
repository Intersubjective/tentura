// The bud form's invite step when the Post's members cannot be loaded: a
// failed load must be shown as a failure (not an endless spinner) with a retry
// action that keeps what the budder typed, and the bud cannot be submitted
// while the membership is unavailable (loading or failed).
//
// The invite step is the shared Forward recipient picker, so the failure and
// its retry are the picker's own load-error panel.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_row.dart';
import 'package:tentura/features/forward/ui/widget/per_recipient_note_input.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

import 'post_bud_fakes.dart';

const _profiles = [
  Profile(id: 'writer', displayName: 'Writer Wanda'),
  Profile(id: 'silent', displayName: 'Silent Sam'),
  Profile(id: 'other', displayName: 'Other Olga'),
];

const _submitKey = Key('PostBud.SubmitButton');

final _en = lookupL10n(const Locale('en'));

Future<BudScreen> _pump(
  WidgetTester tester, {
  required void Function(FakePostBudPort port) seed,
}) {
  final h = BudHarness(parent: budPost(), profiles: _profiles);
  seed(h.port);
  return pumpBudCreateScreen(tester, h);
}

Future<void> _openInviteStep(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('PostBud.NextButton')));
  await settleBud(tester);
  expect(find.byType(ForwardRecipientPicker), findsOneWidget);
}

Finder _retry() => find.descendant(
  of: find.byType(ScreenLoadErrorPanel),
  matching: find.widgetWithText(FilledButton, _en.myWorkRetry),
);

Finder _rowOf(String id) => find.byWidgetPredicate(
  (w) => w is ForwardRecipientRow && w.candidate.id == id,
);

bool _ticked(WidgetTester tester, String id) =>
    tester.widget<ForwardRecipientRow>(_rowOf(id)).isSelected;

Finder _titleField() => find.byType(TextFormField).at(0);

Finder _descriptionField() => find.byType(TextFormField).at(1);

String _fieldText(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(
      find.descendant(of: field, matching: find.byType(TextField)),
    ).controller!.text;

bool _submitEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(_submitKey)).onPressed != null;

void main() {
  testWidgets(
    'a failed member load shows a retry action instead of a spinner and '
    'keeps submit disabled',
    (tester) async {
      final opened = await _pump(
        tester,
        seed: (port) => port
          ..candidatesError = Exception('offline')
          ..candidates = [budCandidate('silent', pretick: true)],
      );
      await _openInviteStep(tester);

      expect(find.byKey(const Key('PostBud.InviteStep')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_retry(), findsOneWidget);
      expect(_submitEnabled(tester), isFalse);

      await tester.tap(find.byKey(_submitKey), warnIfMissed: false);
      await settleBud(tester, rounds: 4);
      expect(opened.h.port.calls, isEmpty);
    },
  );

  testWidgets(
    'retrying after a failed member load shows the members with their '
    'ticks, keeps the typed form and then allows the bud',
    (tester) async {
      final opened = await _pump(
        tester,
        seed: (port) => port
          ..candidatesError = Exception('offline')
          ..candidates = [
            budCandidate('writer', hasWritten: true, pretick: true),
            budCandidate('silent', pretick: true),
            budCandidate('other'),
          ],
      );
      await tester.enterText(_titleField(), 'Ladder for Saturday');
      await tester.enterText(_descriptionField(), 'Needed from noon.');
      await _openInviteStep(tester);
      expect(_retry(), findsOneWidget);
      expect(_submitEnabled(tester), isFalse);
      await tester.tap(find.byKey(_submitKey), warnIfMissed: false);
      await settleBud(tester, rounds: 4);
      expect(opened.h.port.calls, isEmpty);

      opened.h.port.candidatesError = null;
      await tester.tap(_retry());
      await settleBud(tester);

      expect(opened.cubit.state.title, 'Ladder for Saturday');
      expect(opened.cubit.state.description, 'Needed from noon.');
      expect(_retry(), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Writer Wanda'), findsOneWidget);
      expect(find.text('Silent Sam'), findsOneWidget);
      expect(find.text('Other Olga'), findsOneWidget);
      expect(_ticked(tester, 'writer'), isTrue);
      expect(_ticked(tester, 'silent'), isTrue);
      expect(_ticked(tester, 'other'), isFalse);
      expect(
        find.byTooltip(_en.forwardAddPersonalNoteForName('Writer Wanda')),
        findsOneWidget,
      );
      expect(
        find.byTooltip(_en.forwardAddPersonalNoteForName('Other Olga')),
        findsNothing,
      );
      expect(_submitEnabled(tester), isTrue);

      // The form step still holds what was typed before the failure.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
      await settleBud(tester, rounds: 4);
      expect(_fieldText(tester, _titleField()), 'Ladder for Saturday');
      expect(_fieldText(tester, _descriptionField()), 'Needed from noon.');
      await _openInviteStep(tester);
      expect(_ticked(tester, 'writer'), isTrue);
      expect(_ticked(tester, 'silent'), isTrue);
      expect(_ticked(tester, 'other'), isFalse);
      expect(_submitEnabled(tester), isTrue);

      await tester.tap(
        find.byTooltip(_en.forwardAddPersonalNoteForName('Writer Wanda')),
      );
      await settleBud(tester, rounds: 4);
      await tester.enterText(
        find.descendant(
          of: find.byType(PerRecipientNoteInput),
          matching: find.byType(TextField),
        ),
        'You know the ladder',
      );
      final other = find.byKey(TestIds.key(TestIds.forwardRecipient('other')));
      await tester.ensureVisible(other);
      await tester.tap(other);
      await settleBud(tester, rounds: 4);
      expect(_ticked(tester, 'other'), isTrue);

      await tester.tap(find.byKey(_submitKey));
      await settleBud(tester);
      final call = opened.h.port.calls.single;
      expect(call.title, 'Ladder for Saturday');
      expect(call.description, 'Needed from noon.');
      expect(
        call.invitees.map((i) => i.userId),
        unorderedEquals(['silent', 'writer', 'other']),
      );
      expect(
        call.invitees.firstWhere((i) => i.userId == 'writer').note,
        'You know the ladder',
      );
    },
  );

  testWidgets('a retry that fails again keeps the retry action', (
    tester,
  ) async {
    final opened = await _pump(
      tester,
      seed: (port) => port
        ..candidatesError = Exception('offline')
        ..candidates = [budCandidate('silent', pretick: true)],
    );
    await _openInviteStep(tester);

    await tester.tap(_retry());
    await settleBud(tester);

    expect(opened.h.port.calls, isEmpty);
    expect(_retry(), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_submitEnabled(tester), isFalse);
  });

  testWidgets(
    'while the members are still loading the spinner shows, there is no '
    'retry action and submit is disabled',
    (tester) async {
      final opened = await _pump(
        tester,
        seed: (port) => port
          ..candidatesGate = Completer<void>()
          ..candidates = [budCandidate('silent', pretick: true)],
      );
      await _openInviteStep(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_retry(), findsNothing);
      expect(_submitEnabled(tester), isFalse);

      opened.h.port.candidatesGate!.complete();
      await settleBud(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        BlocProvider.of<ForwardCubit>(
          tester.element(find.byType(ForwardRecipientPicker)),
        ).state.selectedIds,
        {'silent'},
      );
      expect(_submitEnabled(tester), isTrue);
    },
  );
}
