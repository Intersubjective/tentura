// Fact continuity, copy chain (plan docs/plans/fact-continuity-architecture.md
// §8 web integration row; D1, D6, D7, D10).
//
// Alice pins a fact in Request A. Bob — admitted to A, author of B and D —
// copies it A → B through «Use in another Request». Alice and Bob then edit
// their own fact and the texts stay apart; Alice unpins the original and
// Bob's copy is untouched. Bob copies his copy B → D, then walks D → B by the
// origin line. The hop B → (unpinned) A says «The original isn't available to
// you» both for Bob (a member of A) and for Carol (a member of B who was never
// in A). Carol, another member of B, edits the copy; D's copy keeps Bob's
// text.
//
// Bob's copies, every origin-line tap and Carol's edit are UI gestures.
// Alice's own edit and unpin of the original stand in for her own browser
// through [postGraphQlAsUser], as in fact_pin_edit_quote_test.dart. Every
// assertion reads what the app loaded from the local server.
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon_threads/data/gql/_g/beacon_fact_card_correct.req.gql.dart';
import 'package:tentura/features/beacon_threads/data/gql/_g/beacon_fact_card_remove.req.gql.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_provenance_line.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

const _pinnedText = 'Spare keys are with the caretaker in flat 4';
const _aliceEditText = 'Spare keys are with the caretaker in flat 5';
const _bobEditText = 'Spare keys are in the lockbox by the back door';
const _carolEditText = 'Spare keys are in the lockbox, code from Bob';

late L10n _l10n;

Finder _action(String label) => find.widgetWithText(ListTile, label).last;

Finder _pinnedFactCard(String factId) => find.byWidgetPredicate(
  (w) => w is BeaconPinnedFactCard && w.fact.id == factId,
);

Finder _pinnedFactCardWithText(String beaconId, String text) =>
    find.byWidgetPredicate(
      (w) =>
          w is BeaconPinnedFactCard &&
          w.fact.beaconId == beaconId &&
          w.fact.factText == text,
    );

Finder _originLineOn(Finder card) => find.descendant(
  of: card,
  matching: find.text(_l10n.beaconRoomFactOriginFromRequest),
);

// Snackbars render their message as RichText.
Finder get _originUnavailable =>
    find.text(_l10n.beaconRoomFactOriginUnavailable, findRichText: true);

Finder _tileWithBody(String body) => find.byWidgetPredicate(
  (w) =>
      w is RoomMessageTile &&
      w.message.body == body &&
      !w.message.id.startsWith('local:'),
);

void _expectSignedInAs(String userId, String who) => expect(
  GetIt.I<ProfileCubit>().state.profile.id,
  userId,
  reason: 'expected to be signed in as $who',
);

Future<void> _switchTo(
  WidgetTester tester, {
  required String email,
  required String userId,
  required String who,
}) async {
  await logout(tester);
  await loginAs(tester, email);
  await pumpUntil(
    tester,
    () => GetIt.I<ProfileCubit>().state.profile.id == userId,
    label: 'profile switched to $who',
  );
}

BeaconViewCubit _viewCubit(WidgetTester tester) =>
    tester.element(find.byType(BeaconViewScreen).last).read<BeaconViewCubit>();

BeaconFactCard? _loadedFact(WidgetTester tester, String factId) => _viewCubit(
  tester,
).state.factCards.where((f) => f.id == factId).firstOrNull;

String _currentPath() => Uri.parse(currentAppUrl()).path;

String? _focusFactParam() =>
    Uri.parse(currentAppUrl()).queryParameters[kQueryFocusFact];

/// Keeps the app running for [window] so a late async answer (an origin
/// lookup, a navigation) lands before a negative or "stays put" assertion.
Future<void> _settleFor(WidgetTester tester, Duration window) async {
  final end = DateTime.now().add(window);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    drainTesterExceptions(tester);
  }
}

const _hopSettleWindow = Duration(seconds: 4);

/// Fact [factId] shown on screen with its provenance — in the page body or
/// in a sheet over it, whichever way the arrival brings the fact into focus.
List<FactProvenanceLine> _shownFact(String factId) => [
  for (final e
      in find
          .byWidgetPredicate(
            (w) => w is FactProvenanceLine && w.fact.id == factId,
          )
          .evaluate())
    e.widget as FactProvenanceLine,
];

bool _anySheetOpen() =>
    find.byType(Material).evaluate().any((e) => ModalRoute.of(e) is PopupRoute);

/// Closes the sheets over the current page with Escape, as a desktop user
/// does before moving on, so a sheet left open here cannot reappear later
/// and pass for an arrival focus.
Future<void> _closeSheets(WidgetTester tester) async {
  for (var i = 0; i < 6 && _anySheetOpen(); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpSettleBounded(tester);
  }
  expect(_anySheetOpen(), isFalse, reason: 'sheets left open over the page');
}

/// Opens the Request at [beaconId] and its pinned facts sheet.
Future<void> _openFactsOf(WidgetTester tester, String beaconId) async {
  await _closeSheets(tester);
  await goToPath(tester, '$kPathBeaconView/$beaconId');
  await pumpUntil(
    tester,
    () =>
        finderHasMatch(find.byType(BeaconViewScreen)) &&
        _viewCubit(tester).state.beacon.id == beaconId,
    label: 'Request $beaconId open',
  );
  await tapAndSettle(tester, find.byKey(TestIds.key(TestIds.beaconTabNow)));
  final open = find.byKey(TestIds.key(TestIds.beaconFactsOpen));
  await pumpUntilVisible(tester, open);
  await tester.ensureVisible(open);
  await tapAndSettle(tester, open);
}

/// Opens [card]'s actions the way a desktop web user does: the hover «More»
/// button when the card offers one, a secondary click otherwise, and a plain
/// tap where the card is touch-driven.
Future<void> _openFactActions(WidgetTester tester, Finder card) async {
  await pumpUntilVisible(tester, card);
  await tester.ensureVisible(card);
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: tester.getCenter(card));
  await pumpSettleBounded(tester);
  final more = find.descendant(
    of: card,
    matching: find.widgetWithIcon(IconButton, Icons.more_horiz),
  );
  final sheetTitle = find.text(_l10n.beaconRoomFactManageSheetTitle);
  if (finderHasMatch(more)) {
    await tester.tap(more);
    await mouse.removePointer();
    await pumpSettleBounded(tester);
  } else {
    await mouse.removePointer();
    final provenance = find.descendant(
      of: card,
      matching: find.byType(FactProvenanceLine),
    );
    await tester.tap(
      provenance,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await pumpSettleBounded(tester);
    if (!await tryPumpUntilVisible(tester, sheetTitle)) {
      await tester.tap(provenance);
      await pumpSettleBounded(tester);
    }
  }
  await pumpUntilVisible(tester, sheetTitle, label: 'fact actions sheet');
}

/// «Use in another Request» on [card], then the destination titled
/// [destinationTitle]; expects the «Copied to …» snackbar.
Future<void> _copyThroughUi(
  WidgetTester tester, {
  required Finder card,
  required String destinationTitle,
}) async {
  await _openFactActions(tester, card);
  await tapAndSettle(
    tester,
    _action(_l10n.beaconRoomFactCardActionUseElsewhere),
  );
  await tapAndSettle(
    tester,
    find.widgetWithText(ListTile, destinationTitle).last,
  );
  await pumpUntilVisible(
    tester,
    find.text(
      _l10n.beaconFactCopyCopiedTo(destinationTitle),
      findRichText: true,
    ),
    label: 'Copied to $destinationTitle snackbar',
  );
}

/// The fact Edit action on [card]: replaces [from] with [to] and saves.
Future<void> _editThroughUi(
  WidgetTester tester, {
  required Finder card,
  required String from,
  required String to,
}) async {
  await _openFactActions(tester, card);
  await tapAndSettle(tester, _action(_l10n.beaconRoomFactCardActionEdit));
  final input = find.byWidgetPredicate(
    (w) => w is TextField && w.controller?.text == from,
  );
  await pumpUntilVisible(tester, input);
  await tester.enterText(input, to);
  await pumpSettleBounded(tester);
  await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Save').last);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a fact copied A → B → D keeps independent texts, survives unpinning '
    'the original and walks back by its origin line',
    (tester) async {
      _l10n = await L10n.delegate.load(const Locale('en'));
      // The origin line's shipped wording, so a wrong key cannot pass.
      expect(
        _l10n.beaconRoomFactOriginFromRequest,
        'Brought from another Request',
      );
      expect(
        _l10n.beaconRoomFactOriginUnavailable,
        "The original isn't available to you",
      );
      await launchApp(app.main);
      await pumpSettleBounded(tester);

      final runId = uniqueRunId('fact-copy');
      // Alice (author of A) ↔ Bob (helper in A).
      final ab = await bootstrapFixture(runId: runId);
      final aliceEmail = ab.authorEmail;
      final aliceId = ab.authorUserId;
      final bobEmail = ab.helperEmail;
      final bobId = ab.helperUserId;
      // Bob (author of B) ↔ Carol (helper in B, never in A).
      final bc = await bootstrapFixture(
        runId: '$runId-c',
        authorEmail: bobEmail,
        helperEmail: 'it-carol-$runId@test.tentura.local',
      );
      final carolEmail = bc.helperEmail;
      final carolId = bc.helperUserId;
      expect(bc.authorUserId, bobId);

      final titleA = uniqueRequestTitle('IT fact source A');
      final titleB = uniqueRequestTitle('IT fact copy B');
      final titleD = uniqueRequestTitle('IT fact copy D');

      // Request A: Alice → Bob, Bob admitted.
      await logout(tester);
      await createAndForwardRequest(tester, fixture: ab, title: titleA);
      await logout(tester);
      await offerHelpFromInbox(tester, fixture: ab, requestTitle: titleA);
      await logout(tester);
      await acceptHelpOffer(tester, fixture: ab, requestTitle: titleA);

      late String beaconA;
      late String factA;
      await runE2eStep('Alice pins a fact in A', () async {
        _expectSignedInAs(aliceId, 'Alice');
        await enterChatIfNeeded(tester);
        await sendRoomMessage(tester, _pinnedText);
        final tile = _tileWithBody(_pinnedText);
        await pumpUntilVisible(tester, tile);
        await tester.ensureVisible(tile);
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await mouse.addPointer(
          location: tester.getCenter(
            find.descendant(
              of: tile,
              matching: find.byType(RoomMessageTextBody),
            ),
          ),
        );
        await pumpSettleBounded(tester);
        final more = find.descendant(
          of: tile,
          matching: find.widgetWithIcon(IconButton, Icons.more_horiz),
        );
        await pumpUntilVisible(tester, more);
        await tester.tap(more);
        await mouse.removePointer();
        await pumpSettleBounded(tester);
        await tapAndSettle(tester, _action(_l10n.beaconRoomActionPinFact));
        await tapAndSettle(tester, _action(_l10n.beaconRoomPinFactPublic));
        RoomCubit room() => tester
            .element(find.byType(RoomMessageTile).first)
            .read<RoomCubit>();
        await pumpUntil(
          tester,
          () => room().state.factCards.any((f) => f.factText == _pinnedText),
          label: 'fact pinned in A',
        );
        final fact = room().state.factCards.firstWhere(
          (f) => f.factText == _pinnedText,
        );
        factA = fact.id;
        beaconA = fact.beaconId;
      });

      // Requests B and D: Bob's own. Carol is admitted to B only.
      await logout(tester);
      await createAndForwardRequest(tester, fixture: bc, title: titleB);
      await logout(tester);
      await offerHelpFromInbox(tester, fixture: bc, requestTitle: titleB);
      await logout(tester);
      await acceptHelpOffer(tester, fixture: bc, requestTitle: titleB);
      _expectSignedInAs(bobId, 'Bob');
      final beaconB = _viewCubit(tester).state.beacon.id;
      final beaconD = await createPublishedBeacon(title: titleD);

      late String copyB;
      await runE2eStep("Bob copies Alice's fact from A into B", () async {
        _expectSignedInAs(bobId, 'Bob');
        await _openFactsOf(tester, beaconA);
        await _copyThroughUi(
          tester,
          card: _pinnedFactCard(factA),
          destinationTitle: titleB,
        );

        await _openFactsOf(tester, beaconB);
        final card = _pinnedFactCardWithText(beaconB, _pinnedText);
        await pumpUntilVisible(tester, card, label: 'copy listed in B');
        final copy = tester.widget<BeaconPinnedFactCard>(card).fact;
        copyB = copy.id;
        expect(copy.id, isNot(factA));
        expect(copy.factText, _pinnedText);
        expect(copy.revisionSeq, 1);
        expect(copy.pinnedBy, bobId);
        expect(copy.originBeaconKind, BeaconKind.request.value);
        expect(_originLineOn(card), findsOneWidget);
      });

      await runE2eStep('Bob edits the copy in B', () async {
        await _editThroughUi(
          tester,
          card: _pinnedFactCard(copyB),
          from: _pinnedText,
          to: _bobEditText,
        );
        await pumpUntil(
          tester,
          () => _loadedFact(tester, copyB)?.revisionSeq == 2,
          label: "Bob's edit saved",
        );
      });

      await runE2eStep('Alice edits the original in A', () async {
        await postGraphQlAsUser(
          email: aliceEmail,
          restoreEmail: bobEmail,
          request: GBeaconFactCardCorrectReq(
            (b) => b.vars
              ..beaconId = beaconA
              ..factCardId = factA
              ..newText = _aliceEditText
              ..baseRevisionSeq = 1,
          ),
        );
      });

      await runE2eStep('the two edits stay apart', () async {
        await _openFactsOf(tester, beaconA);
        await pumpUntil(
          tester,
          () => _loadedFact(tester, factA)?.factText == _aliceEditText,
          label: "A shows Alice's text",
        );
        expect(_loadedFact(tester, factA)!.revisionSeq, 2);
        await _openFactsOf(tester, beaconB);
        await pumpUntil(
          tester,
          () => _loadedFact(tester, copyB) != null,
          label: 'B loaded',
        );
        final copy = _loadedFact(tester, copyB)!;
        expect(copy.factText, _bobEditText);
        expect(copy.revisionSeq, 2);
      });

      await runE2eStep('Alice unpins the original; the copy stays', () async {
        await postGraphQlAsUser(
          email: aliceEmail,
          restoreEmail: bobEmail,
          request: GBeaconFactCardRemoveReq(
            (b) => b.vars
              ..beaconId = beaconA
              ..factCardId = factA,
          ),
        );
        await _openFactsOf(tester, beaconB);
        final card = _pinnedFactCardWithText(beaconB, _bobEditText);
        await pumpUntilVisible(tester, card, label: 'copy still in B');
        final copy = tester.widget<BeaconPinnedFactCard>(card).fact;
        expect(copy.id, copyB);
        expect(copy.factText, _bobEditText);
        expect(copy.revisionSeq, 2);
      });

      late String copyD;
      await runE2eStep('Bob copies his copy from B into D', () async {
        await _copyThroughUi(
          tester,
          card: _pinnedFactCard(copyB),
          destinationTitle: titleD,
        );
        await _openFactsOf(tester, beaconD);
        final card = _pinnedFactCardWithText(beaconD, _bobEditText);
        await pumpUntilVisible(tester, card, label: 'copy listed in D');
        final copy = tester.widget<BeaconPinnedFactCard>(card).fact;
        copyD = copy.id;
        expect(copy.id, isNot(copyB));
        expect(copy.revisionSeq, 1);
        expect(_originLineOn(card), findsOneWidget);
      });

      await runE2eStep('Bob walks D → B by the origin line', () async {
        // Nothing shows B's copy before the walk: whatever shows it after
        // the tap was brought up by the arrival.
        expect(_shownFact(copyB), isEmpty);
        await tapAndSettle(tester, _originLineOn(_pinnedFactCard(copyD)));
        await pumpUntil(
          tester,
          () => _currentPath().endsWith('/$beaconB'),
          label: 'arrived at B',
        );
        expect(_focusFactParam(), copyB);
        await pumpUntil(
          tester,
          () => _shownFact(copyB).isNotEmpty,
          label: "B's copy in focus",
        );
        expect(_shownFact(copyB).first.fact.factText, _bobEditText);
        await _settleFor(tester, _hopSettleWindow);
        expect(_currentPath(), endsWith('/$beaconB'));
        expect(_originUnavailable, findsNothing);
      });

      await runE2eStep(
        'B → unpinned original is unavailable to Bob, a member of A',
        () async {
          await _openFactsOf(tester, beaconB);
          final urlBefore = currentAppUrl();
          await tapAndSettle(tester, _originLineOn(_pinnedFactCard(copyB)));
          await pumpUntilVisible(
            tester,
            _originUnavailable,
            label: 'unavailable snackbar for Bob',
          );
          await _settleFor(tester, _hopSettleWindow);
          expect(_currentPath(), endsWith('/$beaconB'));
          expect(currentAppUrl(), urlBefore);
        },
      );

      await _switchTo(
        tester,
        email: carolEmail,
        userId: carolId,
        who: 'Carol',
      );

      await runE2eStep(
        'B → original is unavailable to Carol, never in A',
        () async {
          _expectSignedInAs(carolId, 'Carol');
          await _openFactsOf(tester, beaconB);
          final urlBefore = currentAppUrl();
          await tapAndSettle(tester, _originLineOn(_pinnedFactCard(copyB)));
          await pumpUntilVisible(
            tester,
            _originUnavailable,
            label: 'unavailable snackbar for Carol',
          );
          await _settleFor(tester, _hopSettleWindow);
          expect(_currentPath(), endsWith('/$beaconB'));
          expect(currentAppUrl(), urlBefore);
        },
      );

      await runE2eStep('Carol edits the copy in B', () async {
        await _openFactsOf(tester, beaconB);
        await _editThroughUi(
          tester,
          card: _pinnedFactCard(copyB),
          from: _bobEditText,
          to: _carolEditText,
        );
        await pumpUntil(
          tester,
          () => _loadedFact(tester, copyB)?.revisionSeq == 3,
          label: "Carol's edit saved",
        );
        final copy = _loadedFact(tester, copyB)!;
        expect(copy.factText, _carolEditText);
        expect(copy.lastEditedBy, carolId);
      });

      await _switchTo(tester, email: bobEmail, userId: bobId, who: 'Bob');

      await runE2eStep("D's copy keeps Bob's text", () async {
        await _openFactsOf(tester, beaconD);
        await pumpUntilVisible(tester, _pinnedFactCard(copyD));
        final copy = tester
            .widget<BeaconPinnedFactCard>(_pinnedFactCard(copyD))
            .fact;
        expect(copy.factText, _bobEditText);
        expect(copy.revisionSeq, 1);
      });
    },
  );
}
