// The «Закрыть пост…» choice of a Post→Request bud must never close the Post
// on people the budder did not invite: its default follows the whole effective
// membership and the selection in the invite step's Forward picker, stays off
// while that membership is unknown, the budder's own choice wins, and the bud
// cannot be submitted until the invite candidates have loaded.
//
// Driven through the bud create screen: the invite step is the shared
// ForwardRecipientPicker over a real ForwardCase and the fake bud port.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/post_bud_invite_outcome.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'post_bud_fakes.dart';

final _en = lookupL10n(const Locale('en'));

Finder _closePostBox() => find.widgetWithText(
  CheckboxListTile,
  _en.postBudClosePost,
  skipOffstage: false,
);

bool? _closePostValue(WidgetTester tester) =>
    tester.widget<CheckboxListTile>(_closePostBox()).value;

Finder _submitButton() => find.byKey(const Key('PostBud.SubmitButton'));

/// Opens the bud screen and goes to the invite step.
Future<BudScreen> _openInviteStep(
  WidgetTester tester,
  BudHarness h, {
  bool expectLoaded = true,
}) async {
  final screen = await pumpBudCreateScreen(tester, h);
  await tester.tap(find.byKey(const Key('PostBud.NextButton')));
  await settleBud(tester);
  if (expectLoaded) {
    expect(
      find.byType(ForwardRecipientPicker),
      findsOneWidget,
      reason: 'the invite step is the Forward recipient picker',
    );
  }
  return screen;
}

ForwardCubit _forward(WidgetTester tester) => BlocProvider.of<ForwardCubit>(
  tester.element(find.byType(ForwardRecipientPicker)),
);

Future<void> _tapRow(WidgetTester tester, String id) async {
  final row = find.byKey(TestIds.key(TestIds.forwardRecipient(id)));
  await tester.ensureVisible(row);
  await tester.tap(row);
  await settleBud(tester, rounds: 4);
}

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(_submitButton());
  await tester.tap(_submitButton());
  await settleBud(tester);
}

void main() {
  group('close-Post default follows the whole effective membership', () {
    testWidgets(
      'off when a member who is not invitable would be left outside the bud',
      (tester) async {
        final h = BudHarness();
        h.port.candidates = [
          budCandidate('a', pretick: true),
          budCandidate('b', pretick: true),
          budCandidate('paused', outcome: PostBudInviteOutcome.notEligible),
        ];
        await _openInviteStep(tester, h);

        expect(_forward(tester).state.selectedIds, {'a', 'b'});
        expect(_closePostValue(tester), isFalse);

        await _submit(tester);
        expect(h.port.calls.single.closePost, isFalse);
      },
    );

    testWidgets(
      'off when every invitable member is ticked but a blocked one remains',
      (tester) async {
        final h = BudHarness();
        h.port.candidates = [
          budCandidate('a', pretick: true),
          budCandidate('b', pretick: true),
          budCandidate('blocked', outcome: PostBudInviteOutcome.blocked),
        ];
        await _openInviteStep(tester, h);
        expect(_closePostValue(tester), isFalse);
      },
    );

    testWidgets('on when every member of the Post is ticked in the picker, '
        'off once one is unticked', (tester) async {
      final h = BudHarness();
      h.port.candidates = [
        budCandidate('a', pretick: true),
        budCandidate('b', pretick: true),
        budCandidate('c', pretick: true),
      ];
      await _openInviteStep(tester, h);
      expect(_closePostValue(tester), isTrue);

      await _tapRow(tester, 'c');
      expect(_forward(tester).state.selectedIds, {'a', 'b'});
      expect(_closePostValue(tester), isFalse);
    });

    testWidgets("the budder's own choice wins over the default", (
      tester,
    ) async {
      final h = BudHarness();
      h.port.candidates = [budCandidate('only')];
      await _openInviteStep(tester, h);
      expect(_closePostValue(tester), isTrue, reason: 'two-member Post');

      await tester.ensureVisible(_closePostBox());
      await tester.tap(_closePostBox());
      await settleBud(tester, rounds: 4);
      expect(_closePostValue(tester), isFalse);

      await _submit(tester);
      expect(h.port.calls.single.closePost, isFalse);
    });
  });

  // #666: only the Post's author may close it. A member who did not start
  // the Post never gets the choice.
  group('a member who is not the Post author', () {
    testWidgets('is never offered «Закрыть пост…» and never sends it', (
      tester,
    ) async {
      final h = BudHarness(parent: budPost(authorId: 'a'));
      h.port.candidates = [
        budCandidate('a', pretick: true),
        budCandidate('b', pretick: true),
      ];
      final screen = await _openInviteStep(tester, h);
      expect(_forward(tester).state.selectedIds, {'a', 'b'});
      expect(_closePostBox(), findsNothing);

      screen.cubit.setBudClosePost(true);
      await settleBud(tester, rounds: 2);
      expect(_closePostBox(), findsNothing);

      await _submit(tester);
      expect(h.port.calls.single.closePost, isFalse);
    });
  });

  group('bud before the invite candidates are known', () {
    testWidgets('close-Post stays off and submit sends nothing while the '
        'picker loads', (tester) async {
      final h = BudHarness();
      h.port.candidatesGate = Completer<void>();
      h.port.candidates = [
        budCandidate('a', pretick: true),
        budCandidate('b', pretick: true),
        budCandidate('c'),
      ];
      await _openInviteStep(tester, h, expectLoaded: false);
      expect(find.byType(ForwardRecipientPicker), findsOneWidget);

      // The budder started the Post, so the choice is offered; with the
      // membership still unknown its default is off.
      expect(_closePostBox(), findsOneWidget);
      expect(_closePostValue(tester), isFalse);
      expect(tester.widget<FilledButton>(_submitButton()).onPressed, isNull);
      await tester.tap(_submitButton(), warnIfMissed: false);
      await settleBud(tester, rounds: 4);
      expect(h.port.calls, isEmpty);

      h.port.candidatesGate!.complete();
      await settleBud(tester);
      expect(_forward(tester).state.selectedIds, {'a', 'b'});
      expect(
        tester.widget<FilledButton>(_submitButton()).onPressed,
        isNotNull,
      );
      await _submit(tester);
      expect(h.port.calls, hasLength(1));
      expect(h.port.calls.single.closePost, isFalse);
    });

    testWidgets(
      'a failed candidate load keeps submit blocked until a retry succeeds',
      (tester) async {
        final h = BudHarness();
        h.port
          ..candidatesError = Exception('offline')
          ..candidates = [
            budCandidate('a', pretick: true),
            budCandidate('b'),
            budCandidate('c'),
          ];
        await _openInviteStep(tester, h, expectLoaded: false);
        expect(find.byType(ForwardRecipientPicker), findsOneWidget);

        expect(tester.widget<FilledButton>(_submitButton()).onPressed, isNull);
        await tester.tap(_submitButton(), warnIfMissed: false);
        await settleBud(tester, rounds: 4);
        expect(h.port.calls, isEmpty);

        h.port.candidatesError = null;
        await tester.runAsync(_forward(tester).retryLoadCandidates);
        await settleBud(tester);
        expect(_forward(tester).state.selectedIds, {'a'});
        await _submit(tester);
        expect(h.port.calls, hasLength(1));
        expect(h.port.calls.single.closePost, isFalse);
      },
    );
  });
}
