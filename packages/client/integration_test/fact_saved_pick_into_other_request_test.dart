// Fact continuity, saved facts (plan docs/plans/fact-continuity-architecture.md
// §8 web integration; D19, D20, §6.3).
//
// Alice pins a discussion-only fact in Request A. Bob, admitted to A, saves
// it through the fact actions sheet. In his own Request B (Carol admitted
// only so B's chat is open) he opens the composer's fact picker, picks the
// fact from the «Saved» tab and sends a message: B now lists a copy with the
// origin line, the chat shows the «brought a fact» line and the message
// quotes the copy. Picking it again reuses that copy. Bob then leaves A; the
// saved row turns «No longer available» while B's copy stays.
//
// Assumption — the Request leave action: for an admitted helper, leaving a
// Request is «Withdraw» on their own offer (People tab). The server withdraw
// revokes room access and posts the participantLeft line («an admitted helper
// withdrew and left the room»). «Leave post» / «Leave chat» exist only for
// Posts and former Post members; the leave step checks that A's overflow
// menu offers Bob no such item, and that his room access is gone afterwards.
//
// The viewer's own name in a chat line reads «You», so Bob's chat shows
// «You brought a fact from another Request»; the line's author is Bob.
//
// Save, pick, send and leave are UI gestures. Every assertion reads what
// the app loaded from the local server.
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/util/beacon_pinned_facts.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_picker_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_provenance_line.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_fact_quote.dart';
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

const _pinnedText = 'The community hall key is in the blue box by the door';
const _firstQuoteBody = 'Bringing the key note over from the other Request';
const _secondQuoteBody = 'Quoting the key note once more';

late L10n _l10n;

/// `beacon_participant.room_access` for an admitted member.
const _roomAccessAdmitted = 3;

Finder _action(String label) => find.widgetWithText(ListTile, label).last;

Finder _pinnedFactCard(String factId) => find.byWidgetPredicate(
  (w) => w is BeaconPinnedFactCard && w.fact.id == factId,
);

Finder _originLineOn(Finder card) => find.descendant(
  of: card,
  matching: find.text(_l10n.beaconRoomFactOriginFromRequest),
);

Finder _tileWithBody(String body) => find.byWidgetPredicate(
  (w) =>
      w is RoomMessageTile &&
      w.message.body == body &&
      !w.message.id.startsWith('local:'),
);

Finder get _broughtLineTiles => find.byWidgetPredicate(
  (w) =>
      w is RoomMessageTile &&
      w.message.semanticMarker == BeaconRoomSemanticMarker.factsBrought,
);

/// The «`actor` brought a fact from another Request» text inside a chat
/// line, never anywhere else on screen.
Finder _broughtLineText(String actor) => find.descendant(
  of: _broughtLineTiles,
  matching: find.text(
    _l10n.beaconRoomFactsBroughtOneFromRequest(actor),
    findRichText: true,
  ),
);

/// Exactly one «brought a fact» chat line, by [authorId], reading [actor].
void _expectOneBroughtLine({
  required WidgetTester tester,
  required String actor,
  required String authorId,
}) {
  expect(_broughtLineTiles, findsOneWidget);
  expect(
    tester.widget<RoomMessageTile>(_broughtLineTiles).message.author.id,
    authorId,
  );
  expect(_broughtLineText(actor), findsOneWidget);
}

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

BeaconFactCard? _loadedFact(WidgetTester tester, String factId) => _viewCubit(
  tester,
).state.factCards.where((f) => f.id == factId).firstOrNull;

RoomCubit _roomCubit(WidgetTester tester) => tester
    .element(find.byKey(TestIds.key(TestIds.roomMessageInput)).first)
    .read<RoomCubit>();

/// Live facts in the open room copied into [beaconId] with [text].
List<BeaconFactCard> _liveCopies(
  WidgetTester tester, {
  required String beaconId,
  required String sourceId,
  required String text,
}) => activePinnedFacts(_roomCubit(tester).state.factCards)
    .where(
      (f) => f.beaconId == beaconId && f.id != sourceId && f.factText == text,
    )
    .toList();

Future<void> _settleFor(WidgetTester tester, Duration window) async {
  final end = DateTime.now().add(window);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    drainTesterExceptions(tester);
  }
}

bool _anySheetOpen() =>
    find.byType(Material).evaluate().any((e) => ModalRoute.of(e) is PopupRoute);

Future<void> _closeSheets(WidgetTester tester) async {
  for (var i = 0; i < 6 && _anySheetOpen(); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpSettleBounded(tester);
  }
  expect(_anySheetOpen(), isFalse, reason: 'sheets left open over the page');
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

/// Opens the Request at [beaconId] and its pinned facts sheet.
Future<void> _openFactsOf(WidgetTester tester, String beaconId) async {
  await _openRequest(tester, beaconId);
  await tapAndSettle(tester, find.byKey(TestIds.key(TestIds.beaconTabNow)));
  final open = find.byKey(TestIds.key(TestIds.beaconFactsOpen));
  await pumpUntilVisible(tester, open);
  await tester.ensureVisible(open);
  await tapAndSettle(tester, open);
}

/// Opens the chat of the Request at [beaconId].
Future<void> _openChatOf(WidgetTester tester, String beaconId) async {
  await _openRequest(tester, beaconId);
  // The chat tab mounts once the viewer's membership has loaded.
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

/// Opens [card]'s actions the way a desktop web user does (hover «More»,
/// secondary click, or a plain tap where the card is touch-driven).
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

/// Composer attach menu → «Fact» → «Saved» tab of the picker.
Future<void> _openSavedTab(WidgetTester tester) async {
  await tapAndSettle(tester, find.byKey(const ValueKey('attach')).first);
  await tapAndSettle(tester, find.text(_l10n.beaconRoomAttachPickFact).last);
  await pumpUntilVisible(tester, _pickerSheet, label: 'fact picker');
  final savedTab = _inPicker(find.text(_l10n.beaconRoomFactPickerTabSaved));
  await pumpUntilVisible(tester, savedTab, label: 'Saved tab');
  await tapAndSettle(tester, savedTab);
}

Finder get _savedRowWithText =>
    _inPicker(find.widgetWithText(ListTile, _pinnedText));

/// Picks the saved fact from the Saved tab; the picker closes.
Future<void> _pickSavedFact(WidgetTester tester) async {
  await _openSavedTab(tester);
  await pumpUntilVisible(tester, _savedRowWithText, label: 'saved row');
  await tapAndSettle(tester, _savedRowWithText);
  await pumpUntil(
    tester,
    () => !finderHasMatch(_pickerSheet),
    label: 'picker closed after pick',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a fact saved in one Request is brought into another from the Saved '
    'tab, quoted once, and reads «No longer available» after leaving the '
    'source',
    (tester) async {
      _l10n = await L10n.delegate.load(const Locale('en'));
      // The shipped wordings, so a wrong key cannot pass.
      expect(_l10n.beaconRoomFactCardActionSave, 'Save to my facts');
      expect(_l10n.beaconRoomFactCardActionUnsave, 'Remove from my facts');
      expect(
        _l10n.beaconRoomFactOriginFromRequest,
        'Brought from another Request',
      );
      expect(
        _l10n.beaconRoomFactsBroughtOneFromRequest('X'),
        'X brought a fact from another Request',
      );
      expect(_l10n.beaconRoomFactPickerSavedUnavailable, 'No longer available');
      await launchApp(app.main);
      await pumpSettleBounded(tester);

      final runId = uniqueRunId('fact-saved');
      final fixture = await bootstrapFixture(runId: runId);
      final aliceId = fixture.authorUserId;
      final bobId = fixture.helperUserId;
      final titleA = uniqueRequestTitle('IT saved fact source A');
      final titleB = uniqueRequestTitle('IT saved fact target B');

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
      late String factA;
      await runE2eStep('Alice pins a discussion-only fact in A', () async {
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
        await tapAndSettle(tester, _action(_l10n.beaconRoomPinFactRoomOnly));
        await pumpUntil(
          tester,
          () => _roomCubit(
            tester,
          ).state.factCards.any((f) => f.factText == _pinnedText),
          label: 'fact pinned in A',
        );
        final fact = _roomCubit(
          tester,
        ).state.factCards.firstWhere((f) => f.factText == _pinnedText);
        factA = fact.id;
        beaconA = fact.beaconId;
      });

      // Request B: Bob's own, with Carol admitted so its chat is open.
      final bc = await bootstrapFixture(
        runId: '$runId-b',
        authorEmail: fixture.helperEmail,
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

      await runE2eStep('Bob saves the fact in A', () async {
        _expectSignedInAs(bobId, 'Bob');
        await _openFactsOf(tester, beaconA);
        await _openFactActions(tester, _pinnedFactCard(factA));
        await tapAndSettle(
          tester,
          _action(_l10n.beaconRoomFactCardActionSave),
        );
        // The tile flips once the server confirms the save.
        await pumpUntilVisible(
          tester,
          find.widgetWithText(ListTile, _l10n.beaconRoomFactCardActionUnsave),
          label: 'Save tile flipped to Remove',
        );
        await _closeSheets(tester);
        // Opened again, the sheet reads what the fact list now reports.
        await _openFactsOf(tester, beaconA);
        await _openFactActions(tester, _pinnedFactCard(factA));
        await _settleFor(tester, const Duration(seconds: 2));
        expect(
          _loadedFact(tester, factA)?.savedByMe,
          isTrue,
          reason: 'the fact list reports savedByMe after saving',
        );
        expect(
          find.widgetWithText(ListTile, _l10n.beaconRoomFactCardActionUnsave),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(ListTile, _l10n.beaconRoomFactCardActionSave),
          findsNothing,
        );
      });

      late String copyB;
      await runE2eStep(
        "B's picker lists the saved fact and picking brings a copy",
        () async {
          await _openChatOf(tester, beaconB);
          expect(_broughtLineTiles, findsNothing);
          await _openSavedTab(tester);
          await pumpUntilVisible(
            tester,
            _savedRowWithText,
            label: 'saved fact listed with its text',
          );
          await tapAndSettle(tester, _savedRowWithText);
          await pumpUntil(
            tester,
            () => _liveCopies(
              tester,
              beaconId: beaconB,
              sourceId: factA,
              text: _pinnedText,
            ).isNotEmpty,
            label: 'copy listed in B',
          );
          final copies = _liveCopies(
            tester,
            beaconId: beaconB,
            sourceId: factA,
            text: _pinnedText,
          );
          expect(copies, hasLength(1));
          final copy = copies.single;
          copyB = copy.id;
          expect(copy.id, isNot(factA));
          expect(copy.originBeaconKind, BeaconKind.request.value);
          expect(
            _roomCubit(tester).state.pendingQuotedFact?.factCardId,
            copyB,
            reason: "the composer quotes B's copy, not the source",
          );
        },
      );

      await runE2eStep('the sent message quotes the copy', () async {
        final sent = await sendRoomMessage(tester, _firstQuoteBody);
        expect(sent.quotedFact?.factCardId, copyB);
        final tile = _tileWithBody(_firstQuoteBody);
        expect(
          find.descendant(
            of: find.descendant(
              of: tile,
              matching: find.byType(RoomMessageFactQuote),
            ),
            matching: find.textContaining(_pinnedText, findRichText: true),
          ),
          findsWidgets,
        );
        // The viewer sees their own name as «You».
        await pumpUntilVisible(
          tester,
          _broughtLineText(_l10n.labelYou),
          label: 'brought-a-fact line',
        );
        _expectOneBroughtLine(
          tester: tester,
          actor: _l10n.labelYou,
          authorId: bobId,
        );
      });

      await runE2eStep('picking it again reuses the same copy', () async {
        await _pickSavedFact(tester);
        await pumpUntil(
          tester,
          () => _roomCubit(tester).state.pendingQuotedFact != null,
          label: 'pending quote after re-pick',
        );
        expect(
          _roomCubit(tester).state.pendingQuotedFact?.factCardId,
          copyB,
        );
        await _settleFor(tester, const Duration(seconds: 3));
        final copies = _liveCopies(
          tester,
          beaconId: beaconB,
          sourceId: factA,
          text: _pinnedText,
        );
        expect(copies.map((f) => f.id), [copyB]);
        // The re-pick alone adds no second line.
        _expectOneBroughtLine(
          tester: tester,
          actor: _l10n.labelYou,
          authorId: bobId,
        );
        final sent = await sendRoomMessage(tester, _secondQuoteBody);
        expect(sent.quotedFact?.factCardId, copyB);
        await _settleFor(tester, const Duration(seconds: 3));
        _expectOneBroughtLine(
          tester: tester,
          actor: _l10n.labelYou,
          authorId: bobId,
        );
      });

      await runE2eStep("B's fact list shows the copy's origin line", () async {
        await _openFactsOf(tester, beaconB);
        final card = _pinnedFactCard(copyB);
        await pumpUntilVisible(tester, card, label: 'copy in B fact list');
        final copy = tester.widget<BeaconPinnedFactCard>(card).fact;
        expect(copy.factText, _pinnedText);
        expect(copy.originBeaconKind, BeaconKind.request.value);
        expect(_originLineOn(card), findsOneWidget);
        // After the first pick and the re-pick, B's fact list holds exactly
        // one live copy of the source: the first copy.
        final listed = activePinnedFacts(_viewCubit(tester).state.factCards)
            .where((f) => f.id != factA && f.factText == _pinnedText)
            .map((f) => f.id)
            .toList();
        expect(listed, [copyB]);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is BeaconPinnedFactCard &&
                w.fact.beaconId == beaconB &&
                w.fact.factText == _pinnedText,
          ),
          findsOneWidget,
        );
      });

      await runE2eStep('Bob leaves Request A', () async {
        await _openRequest(tester, beaconA);
        // No separate «Leave» item for a Request helper in the overflow menu.
        final overflow = find.descendant(
          of: find.byType(BeaconViewScreen).last,
          matching: find.byKey(TestIds.key(TestIds.beaconOverflowMenu)),
        );
        if (await tryPumpUntilVisible(tester, overflow)) {
          await tapAndSettle(tester, overflow.first);
          expect(find.text(_l10n.postMenuLeave), findsNothing);
          expect(find.text(_l10n.postOriginLeaveChat), findsNothing);
          await _closeSheets(tester);
        }
        await tapAndSettle(
          tester,
          find.byKey(TestIds.key(TestIds.beaconTabPeople)),
        );
        final withdraw = find.widgetWithText(
          TenturaTextAction,
          _l10n.helpOffersTabActionWithdraw,
        );
        await pumpUntilVisible(tester, withdraw, label: 'own Withdraw action');
        await tester.ensureVisible(withdraw.first);
        await tapAndSettle(tester, withdraw.first);
        final reason = find.widgetWithText(FilterChip, _l10n.withdrawCantDoIt);
        await pumpUntilVisible(tester, reason, label: 'withdraw reasons');
        await tapAndSettle(tester, reason);
        await tapAndSettle(
          tester,
          find.byKey(TestIds.key(TestIds.helpOfferSubmit)),
        );
        await pumpUntil(
          tester,
          () => !_viewCubit(tester).state.isHelpOffered,
          label: 'offer withdrawn',
        );
        // Left: no longer an admitted room member of A.
        expect(
          await fetchParticipantRoomAccess(
            beaconId: beaconA,
            userId: bobId,
            asEmail: fixture.helperEmail,
            restoreEmail: fixture.helperEmail,
          ),
          isNot(_roomAccessAdmitted),
        );
      });

      await runE2eStep(
        'the saved row reads «No longer available» in B',
        () async {
          await _openChatOf(tester, beaconB);
          await _openSavedTab(tester);
          await pumpUntilVisible(
            tester,
            _inPicker(find.text(_l10n.beaconRoomFactPickerSavedUnavailable)),
            label: 'unavailable saved row',
          );
          expect(
            _inPicker(find.text(_l10n.beaconRoomFactPickerSavedUnavailable)),
            findsOneWidget,
          );
          expect(_inPicker(find.textContaining(_pinnedText)), findsNothing);
          await _closeSheets(tester);
        },
      );

      await runE2eStep("B's copy is unaffected by leaving A", () async {
        await _openFactsOf(tester, beaconB);
        final card = _pinnedFactCard(copyB);
        await pumpUntilVisible(tester, card, label: 'copy still in B');
        final copy = tester.widget<BeaconPinnedFactCard>(card).fact;
        expect(copy.factText, _pinnedText);
        expect(_originLineOn(card), findsOneWidget);
      });
    },
  );
}
