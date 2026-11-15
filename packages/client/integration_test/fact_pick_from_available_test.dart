// Facts: global search in the pickers and «Pick from available» (plan
// docs/plans/fact-pick-from-available-1288.md; D1–D20 of
// docs/plans/fact-continuity-architecture.md stay binding).
//
// Alice pins a discussion-only fact «blue door key» in Request A (Bob
// admitted) and a fact in Request C, which Bob does not belong to. In his own
// Request B Bob opens Facts → «Add fact» → «Pick from available» → «All my
// facts», types «blue door» and picks the fact: B's Facts sheet lists the copy
// with the origin line and B's chat shows the «brought a fact» line; picking
// it again answers «Already there». C's fact text finds nothing. In a Post Bob
// belongs to, the chat composer «Fact» → «All my facts» → the A fact copies it
// into the Post and the composer quotes the copy.
//
// Seeding the facts is a direct API call; the searches, picks and every
// assertion are the app's own UI paths over the local server.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/util/beacon_pinned_facts.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_picker_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

late L10n _l10n;

Finder _factCard(String factId) => find.byWidgetPredicate(
  (w) => w is BeaconPinnedFactCard && w.fact.id == factId,
);

Finder get _broughtLineTiles => find.byWidgetPredicate(
  (w) =>
      w is RoomMessageTile &&
      w.message.semanticMarker == BeaconRoomSemanticMarker.factsBrought,
);

Finder get _pickerSheet => find.byType(FactPickerSheet);

Finder _inPicker(Finder matching) =>
    find.descendant(of: _pickerSheet, matching: matching);

void _expectSignedInAs(String userId, String who) => expect(
  GetIt.I<ProfileCubit>().state.profile.id,
  userId,
  reason: 'expected to be signed in as $who',
);

BeaconViewCubit _viewCubit(WidgetTester tester) =>
    tester.element(find.byType(BeaconViewScreen).last).read<BeaconViewCubit>();

RoomCubit _roomCubit(WidgetTester tester) => tester
    .element(find.byKey(TestIds.key(TestIds.roomMessageInput)).first)
    .read<RoomCubit>();

bool _anySheetOpen() =>
    find.byType(Material).evaluate().any((e) => ModalRoute.of(e) is PopupRoute);

Future<void> _closeSheets(WidgetTester tester) async {
  for (var i = 0; i < 6 && _anySheetOpen(); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpSettleBounded(tester);
  }
  expect(_anySheetOpen(), isFalse, reason: 'sheets left open over the page');
}

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

Future<void> _openRequest(WidgetTester tester, String beaconId) async {
  await _closeSheets(tester);
  await goToPath(tester, '$kPathBeaconView/$beaconId');
  await pumpUntil(
    tester,
    () =>
        finderHasMatch(find.byType(BeaconViewScreen)) &&
        _viewCubit(tester).state.beacon.id == beaconId,
    label: 'Request $beaconId open',
  );
}

Future<void> _openFactsOf(WidgetTester tester, String beaconId) async {
  await _openRequest(tester, beaconId);
  await tapAndSettle(tester, find.byKey(TestIds.key(TestIds.beaconTabNow)));
  final open = find.byKey(TestIds.key(TestIds.beaconFactsOpen));
  await pumpUntilVisible(tester, open);
  await tester.ensureVisible(open);
  await tapAndSettle(tester, open);
}

Future<void> _openChatOf(WidgetTester tester, String beaconId) async {
  await _openRequest(tester, beaconId);
  await pumpUntil(
    tester,
    () =>
        finderHasMatch(find.byKey(TestIds.key(TestIds.roomMessageInput))) ||
        finderHasMatch(find.byKey(TestIds.key(TestIds.beaconTabRoom))),
    label: 'chat of $beaconId reachable',
  );
  await enterChatIfNeeded(tester);
  await pumpUntil(
    tester,
    () => _roomCubit(tester).state.canWriteDiscussion,
    label: 'chat of $beaconId writable',
  );
}

/// Pins [text] as a discussion-only fact of [beaconId] as the signed-in user,
/// through the app's own fact repository (the same call the pin UI makes).
Future<void> _pinFact({
  required String beaconId,
  required String text,
}) => GetIt.I<BeaconFactCardRepository>().pin(
  beaconId: beaconId,
  factText: text,
  visibility: BeaconFactCardVisibilityBits.room,
);

/// Facts sheet → «Add fact» → «Pick from available» → «All my facts», then
/// types [query] into the picker's search field.
Future<void> _searchFromAddFact(WidgetTester tester, String query) async {
  final add = find.byKey(TestIds.key(TestIds.beaconFactsAdd));
  await pumpUntilVisible(tester, add, label: 'Add fact button');
  await tapAndSettle(tester, add);
  final pick = find.byKey(TestIds.key(TestIds.beaconFactsAddPick));
  await pumpUntilVisible(tester, pick, label: 'Pick from available item');
  await tapAndSettle(tester, pick);
  await pumpUntilVisible(tester, _pickerSheet, label: 'fact picker');
  await _searchAllScope(tester, query);
}

Future<void> _searchAllScope(WidgetTester tester, String query) async {
  final allTab = _inPicker(find.text(_l10n.factPickerTabAll));
  await pumpUntilVisible(tester, allTab, label: 'All my facts scope');
  await tapAndSettle(tester, allTab);
  await tester.enterText(_inPicker(find.byType(TextField)), query);
  await pumpSettleBounded(tester);
}

/// A picker row whose title is exactly [text] (not a longer string holding it).
Finder _hitRow(String text) => _inPicker(
  find.byWidgetPredicate((w) {
    if (w is! ListTile) return false;
    final title = w.title;
    return title is Text && title.data == text;
  }),
);

/// The search finished: no loading indicator is left in the picker.
Future<void> _awaitSearchDone(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await pumpUntil(
    tester,
    () => !finderHasMatch(_inPicker(find.byType(TenturaCircularProgress))),
    label: 'picker search finished',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a fact found by global search is brought into a Request from «Pick from '
    'available» and into a Post from the chat quote picker; a fact of a '
    'Request the viewer is outside of is not found',
    (tester) async {
      _l10n = await L10n.delegate.load(const Locale('en'));
      expect(_l10n.beaconFactsAddMenuPick, 'Pick from available');
      expect(_l10n.factPickerTabAll, 'All my facts');
      expect(_l10n.beaconFactCopyAlreadyThere, 'Already there');
      expect(_l10n.factPickerFactAdded, 'Fact added');
      await launchApp(app.main);
      await pumpSettleBounded(tester);
      // The app's whole viewport is a phone: the runner must give this target
      // a 375x806 browser window (headless toolbar takes 139 px).
      expect(
        tester.view.physicalSize / tester.view.devicePixelRatio,
        const Size(375, 667),
        reason: 'the app viewport must be 375x667 (a 375x806 window)',
      );

      final runId = uniqueRunId('fact-avail');
      final fixture = await bootstrapFixture(runId: runId);
      final aliceId = fixture.authorUserId;
      final aliceEmail = fixture.authorEmail;
      final bobId = fixture.helperUserId;
      final bobEmail = fixture.helperEmail;
      final titleA = uniqueRequestTitle('IT avail fact source A');
      final titleB = uniqueRequestTitle('IT avail fact target B');
      final titleC = uniqueRequestTitle('IT avail fact hidden C');
      final tag = runId.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
      final textA = 'blue door key $tag';
      final textC = 'green gate code $tag';

      // Request A: Alice → Bob, Bob admitted.
      await logout(tester);
      await createAndForwardRequest(tester, fixture: fixture, title: titleA);
      await logout(tester);
      await offerHelpFromInbox(
        tester,
        fixture: fixture,
        requestTitle: titleA,
      );
      await logout(tester);
      await acceptHelpOffer(tester, fixture: fixture, requestTitle: titleA);

      late String beaconA;
      late String factIdA;
      await runE2eStep('Alice pins a fact in A and one in C', () async {
        _expectSignedInAs(aliceId, 'Alice');
        beaconA = _viewCubit(tester).state.beacon.id;
        await _pinFact(beaconId: beaconA, text: textA);
        // A's own fact id, as the server stored it.
        await _viewCubit(tester).refreshFactCards();
        final sources = activePinnedFacts(
          _viewCubit(tester).state.factCards,
        ).where((f) => f.beaconId == beaconA && f.factText == textA).toList();
        expect(sources, hasLength(1), reason: "A's pinned fact is loaded");
        factIdA = sources.single.id;
        // Request C: Alice's own; Bob has no part in it.
        final beaconC = await createPublishedBeacon(title: titleC);
        await _pinFact(beaconId: beaconC, text: textC);
      });

      // Request B: Bob's own, Carol admitted so its chat is open.
      final bc = await bootstrapFixture(
        runId: '$runId-b',
        authorEmail: bobEmail,
        helperEmail: 'it-carol-$runId@test.tentura.local',
      );
      expect(bc.authorUserId, bobId);
      await logout(tester);
      await createAndForwardRequest(tester, fixture: bc, title: titleB);
      await logout(tester);
      await offerHelpFromInbox(tester, fixture: bc, requestTitle: titleB);
      await logout(tester);
      await acceptHelpOffer(tester, fixture: bc, requestTitle: titleB);
      _expectSignedInAs(bobId, 'Bob');
      final beaconB = _viewCubit(tester).state.beacon.id;

      late String copyB;
      await runE2eStep(
        'Pick from available brings the A fact into B',
        () async {
          await _openFactsOf(tester, beaconB);
          await _searchFromAddFact(tester, 'blue door');
          await pumpUntilVisible(
            tester,
            _hitRow(textA),
            label: 'search hit for the A fact',
          );
          await tapAndSettle(tester, _hitRow(textA));
          await pumpUntil(
            tester,
            () => !finderHasMatch(_pickerSheet),
            label: 'picker closed after pick',
          );
          await pumpUntilVisible(
            tester,
            find.text(_l10n.factPickerFactAdded, findRichText: true),
            label: 'Fact added snackbar',
          );
          await pumpUntil(
            tester,
            () => activePinnedFacts(_viewCubit(tester).state.factCards).any(
              (f) => f.beaconId == beaconB && f.factText == textA,
            ),
            label: 'copy listed in B',
          );
          final copies = activePinnedFacts(
            _viewCubit(tester).state.factCards,
          ).where((f) => f.beaconId == beaconB && f.factText == textA).toList();
          expect(copies, hasLength(1));
          copyB = copies.single.id;
          expect(copies.single.beaconId, beaconB);
          expect(copies.single.id, isNot(factIdA));
          final card = _factCard(copyB);
          await pumpUntilVisible(tester, card, label: 'copy card in B');
          expect(
            find.descendant(
              of: card,
              matching: find.text(_l10n.beaconRoomFactOriginFromRequest),
            ),
            findsOneWidget,
          );
        },
      );

      await runE2eStep('picking it again answers «Already there»', () async {
        await _closeSheets(tester);
        await _openFactsOf(tester, beaconB);
        await _searchFromAddFact(tester, 'blue door');
        await pumpUntilVisible(tester, _hitRow(textA));
        await tapAndSettle(tester, _hitRow(textA));
        await pumpUntilVisible(
          tester,
          find.text(_l10n.beaconFactCopyAlreadyThere, findRichText: true),
          label: 'Already there snackbar',
        );
        await pumpUntil(
          tester,
          () => !finderHasMatch(_pickerSheet),
          label: 'picker closed after re-pick',
        );
        final copies =
            activePinnedFacts(
                  _viewCubit(tester).state.factCards,
                )
                .where((f) => f.beaconId == beaconB && f.factText == textA)
                .map((f) => f.id)
                .toList();
        expect(copies, [copyB]);
      });

      await runE2eStep("B's chat shows the «brought a fact» line", () async {
        await _openChatOf(tester, beaconB);
        await pumpUntilVisible(
          tester,
          _broughtLineTiles,
          label: 'brought-a-fact line',
        );
        expect(_broughtLineTiles, findsOneWidget);
        expect(
          tester.widget<RoomMessageTile>(_broughtLineTiles).message.author.id,
          bobId,
        );
      });

      await runE2eStep(
        "a fact of a Request Bob is outside of isn't found",
        () async {
          await _openFactsOf(tester, beaconB);
          await _searchFromAddFact(tester, 'green gate');
          await _awaitSearchDone(tester);
          expect(_inPicker(find.byType(ListTile)), findsNothing);
          expect(_inPicker(find.textContaining(textC)), findsNothing);
          // Positive control: the same picker does find a fact Bob may read.
          await tester.enterText(
            _inPicker(find.byType(TextField)),
            'blue door',
          );
          await pumpUntilVisible(
            tester,
            _hitRow(textA),
            label: 'control search hit in the same picker',
          );
          await _closeSheets(tester);
        },
      );

      // A Post Alice sends to Bob.
      await _switchTo(
        tester,
        email: aliceEmail,
        userId: aliceId,
        who: 'Alice',
      );
      final rootBody = uniqueRequestTitle('IT avail fact post root');
      final postId = await createPublishedPost(
        body: rootBody,
        recipientIds: [bobId],
      );
      await _switchTo(tester, email: bobEmail, userId: bobId, who: 'Bob');

      await runE2eStep(
        'the Post chat quote picker copies the A fact and quotes the copy',
        () async {
          await _closeSheets(tester);
          await goToDeepLink(tester, '$kPathBeaconView/$postId');
          await pumpUntilVisible(
            tester,
            find.textContaining(rootBody).first,
            label: 'Post conversation loaded',
          );
          final composer = find.byKey(TestIds.key(TestIds.roomMessageInput));
          await pumpUntilVisible(tester, composer, label: 'composer');
          await tapAndSettle(
            tester,
            find.byTooltip(_l10n.beaconRoomAttachMenuTooltip).first,
          );
          await tapAndSettle(
            tester,
            find.text(_l10n.beaconRoomAttachPickFact).last,
          );
          await pumpUntilVisible(tester, _pickerSheet, label: 'fact picker');
          await _searchAllScope(tester, 'blue door');
          // Bob can read two rows with this text here: his copy in B (newer)
          // and A's original (older); results run newest first.
          await pumpUntil(
            tester,
            () => _hitRow(textA).evaluate().length == 2,
            label: "search hits for A's fact and Bob's copy of it",
          );
          await tapAndSettle(tester, _hitRow(textA).last);
          await pumpUntil(
            tester,
            () => !finderHasMatch(_pickerSheet),
            label: 'picker closed after pick',
          );
          await pumpUntil(
            tester,
            () => _roomCubit(tester).state.pendingQuotedFact != null,
            label: 'composer quotes the copy',
          );
          final room = _roomCubit(tester);
          final quoted = room.state.pendingQuotedFact!;
          final copy = room.state.factCards.firstWhere(
            (f) => f.id == quoted.factCardId,
          );
          expect(copy.beaconId, postId);
          expect(copy.id, isNot(factIdA));
          expect(quoted.factCardId, isNot(factIdA));
          expect(copy.factText, textA);
        },
      );
    },
  );
}
