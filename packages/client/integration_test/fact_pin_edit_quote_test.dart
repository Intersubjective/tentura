// tentura-617.38 (plan §11 U16): two accounts in one Request.
//   A pins a message → B edits the fact → A's card shows "A · edited by B"
//   and the history sheet lists both versions with both authors →
//   B quotes the fact in the discussion → A edits it again → B's bubble
//   shows "Changed since quoted" without a reload.
//
// A's second edit goes through [postGraphQlAsUser] while B keeps the room
// open, standing in for A's own browser. Controls are found by their l10n
// labels and widget types, so the test drives the shipped UI as-is.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_history_entry.dart';
import 'package:tentura/features/beacon_threads/data/gql/_g/beacon_fact_card_correct.req.gql.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/fact_history_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_provenance_line.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_fact_quote.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

const _pinnedText = 'Meet at the north gate at 9';
const _bEditText = 'Meet at the north gate at 10';
const _aSecondEditText = 'Meet at the south gate at 10';
const _quoteBody = 'Quoting the meeting point';

Finder _tileWithBody(String body) => find.byWidgetPredicate(
  (w) =>
      w is RoomMessageTile &&
      w.message.body == body &&
      !w.message.id.startsWith('local:'),
);

late L10n _l10n;

/// The version a history row's [Text] shows: its plain text, minus the
/// struck-through (removed) spans of a word diff.
String? _renderedVersion(Text text) {
  if (text.data != null) return text.data;
  final span = text.textSpan;
  if (span == null) return null;
  final buffer = StringBuffer();
  span.visitChildren((child) {
    if (child is TextSpan &&
        child.text != null &&
        child.style?.decoration != TextDecoration.lineThrough) {
      buffer.write(child.text);
    }
    return true;
  });
  return buffer.toString();
}

Finder _action(String label) => find.widgetWithText(ListTile, label).last;

Finder _pinnedFactCard(String factId) => find.byWidgetPredicate(
  (w) => w is BeaconPinnedFactCard && w.fact.id == factId,
);

/// The session the UI is rendering for, so per-account assertions cannot
/// silently run in the other account's session.
void _expectSignedInAs(String userId, String who) => expect(
  GetIt.I<ProfileCubit>().state.profile.id,
  userId,
  reason: 'expected to be signed in as $who',
);

RoomCubit _roomCubit(WidgetTester tester) =>
    tester.element(find.byType(RoomMessageTile).first).read<RoomCubit>();

BeaconFactCard? _liveFact(WidgetTester tester, String factId) =>
    _roomCubit(tester).state.factCards.where((f) => f.id == factId).firstOrNull;

/// Desktop web: SelectionArea claims long-press on selectable text, so open
/// actions the way a mouse user does — hover [hoverOn], tap "More" in
/// [within]'s hover toolbar.
Future<void> _hoverAndTapMore(
  WidgetTester tester, {
  required Finder within,
  required Finder hoverOn,
}) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: tester.getCenter(hoverOn));
  await pumpSettleBounded(tester);
  final more = find.descendant(
    of: within,
    matching: find.widgetWithIcon(IconButton, Icons.more_horiz),
  );
  await pumpUntilVisible(tester, more);
  await tester.tap(more);
  await mouse.removePointer();
  await pumpSettleBounded(tester);
}

Future<void> _openMessageActions(WidgetTester tester, Finder tile) async {
  await pumpUntilVisible(tester, tile);
  await tester.ensureVisible(tile);
  await _hoverAndTapMore(
    tester,
    within: tile,
    hoverOn: find.descendant(
      of: tile,
      matching: find.byType(RoomMessageTextBody),
    ),
  );
}

Future<void> _openFactFromSourceMessage(WidgetTester tester) async {
  await enterChatIfNeeded(tester);
  await _openMessageActions(tester, _tileWithBody(_pinnedText));
  await tapAndSettle(
    tester,
    _action(_l10n.beaconRoomActionViewPinnedFact),
  );
}

Future<void> _openPinnedFactsCard(WidgetTester tester, String factId) async {
  await tapAndSettle(tester, find.byKey(TestIds.key(TestIds.beaconTabNow)));
  final open = find.byKey(TestIds.key(TestIds.beaconFactsOpen));
  await pumpUntilVisible(tester, open);
  await tester.ensureVisible(open);
  await tapAndSettle(tester, open);
  await pumpUntilVisible(tester, _pinnedFactCard(factId));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pin → edit by other → history → quote → changed since', (
    tester,
  ) async {
    _l10n = await L10n.delegate.load(const Locale('en'));
    await launchApp(app.main);
    await pumpSettleBounded(tester);

    final fixture = await bootstrapFixture(runId: uniqueRunId('fact-quote'));
    final title = uniqueRequestTitle('IT fact quote');

    // Author A with helper B admitted to the discussion.
    await logout(tester);
    await createAndForwardRequest(tester, fixture: fixture, title: title);
    await logout(tester);
    await offerHelpFromInbox(tester, fixture: fixture, requestTitle: title);
    await logout(tester);
    await acceptHelpOffer(tester, fixture: fixture, requestTitle: title);

    late String beaconId;
    late String factId;

    await runE2eStep('A pins a message as a fact', () async {
      await enterChatIfNeeded(tester);
      await sendRoomMessage(tester, _pinnedText);
      await _openMessageActions(tester, _tileWithBody(_pinnedText));
      await tapAndSettle(
        tester,
        _action(_l10n.beaconRoomActionPinFact),
      );
      await tapAndSettle(
        tester,
        _action(_l10n.beaconRoomPinFactPublic),
      );
      await pumpUntil(
        tester,
        () => _roomCubit(tester).state.factCards.any(
          (f) => f.factText == _pinnedText,
        ),
        label: 'fact pinned',
      );
      final fact = _roomCubit(
        tester,
      ).state.factCards.firstWhere((f) => f.factText == _pinnedText);
      factId = fact.id;
      beaconId = fact.beaconId;
      expect(fact.pinnedBy, fixture.authorUserId);
      expect(fact.revisionSeq, 1);
    });

    await logout(tester);
    await loginAs(tester, fixture.helperEmail);
    await pumpUntil(
      tester,
      () => GetIt.I<ProfileCubit>().state.profile.id == fixture.helperUserId,
      label: 'profile switched to B',
    );
    await openRequestFromMyWork(tester, requestTitle: title);

    await runE2eStep('B edits the fact', () async {
      _expectSignedInAs(fixture.helperUserId, 'B');
      await _openFactFromSourceMessage(tester);
      await tapAndSettle(
        tester,
        _action(_l10n.beaconRoomFactCardActionEdit),
      );
      final input = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == _pinnedText,
      );
      await pumpUntilVisible(tester, input);
      await tester.enterText(input, _bEditText);
      await pumpSettleBounded(tester);
      await tapAndSettle(
        tester,
        find.widgetWithText(FilledButton, 'Save').last,
      );
      await pumpUntil(
        tester,
        () => _liveFact(tester, factId)?.revisionSeq == 2,
        label: 'B edit saved',
      );
    });

    // Back to A's own session: A must see B's edit on A's card.
    await logout(tester);
    await loginAs(tester, fixture.authorEmail);
    await pumpUntil(
      tester,
      () => GetIt.I<ProfileCubit>().state.profile.id == fixture.authorUserId,
      label: 'profile switched to A',
    );
    await openRequestFromMyWork(tester, requestTitle: title);

    await runE2eStep("A's card names pinner A and editor B", () async {
      _expectSignedInAs(fixture.authorUserId, 'A');
      await _openPinnedFactsCard(tester, factId);
      final card = _pinnedFactCard(factId);
      final fact = tester.widget<BeaconPinnedFactCard>(card).fact;
      expect(fact.factText, _bEditText);
      expect(fact.pinnedBy, fixture.authorUserId);
      expect(fact.lastEditedBy, fixture.helperUserId);
      expect(fact.pinnedByTitle, isNotEmpty);
      expect(fact.lastEditedByTitle, isNotEmpty);

      final line = find.descendant(
        of: card,
        matching: find.byType(FactProvenanceLine),
      );
      await pumpUntilVisible(tester, line);
      final text = tester
          .widget<Text>(find.descendant(of: line, matching: find.byType(Text)))
          .data!;
      expect(text, startsWith(fact.pinnedByTitle));
      expect(
        text,
        contains(
          _l10n.beaconRoomFactProvenanceEditedBy(fact.lastEditedByTitle),
        ),
      );
    });

    await runE2eStep(
      "A's history lists both versions with both authors",
      () async {
        _expectSignedInAs(fixture.authorUserId, 'A');
        final card = _pinnedFactCard(factId);
        await tester.ensureVisible(card);
        await _hoverAndTapMore(tester, within: card, hoverOn: card);
        await tapAndSettle(
          tester,
          _action(_l10n.beaconRoomFactCardActionEditHistory),
        );
        final sheet = find.byType(FactHistorySheet);
        await pumpUntilVisible(tester, sheet);
        FactHistoryCubit historyCubit() => tester
            .element(
              find.descendant(of: sheet, matching: find.byType(Scaffold)).first,
            )
            .read<FactHistoryCubit>();
        await pumpUntil(
          tester,
          () =>
              historyCubit().state.entries
                  .whereType<BeaconFactHistoryEntry>()
                  .length >=
              2,
          label: 'fact history loaded',
        );
        final revisions = historyCubit().state.entries
            .whereType<BeaconFactHistoryEntry>()
            .toList();
        final bySeq = {for (final r in revisions) r.seq: r};
        expect(bySeq[1]?.factText, _pinnedText);
        expect(bySeq[1]?.actorId, fixture.authorUserId);
        expect(bySeq[2]?.factText, _bEditText);
        expect(bySeq[2]?.actorId, fixture.helperUserId);
        // Both versions are rendered in the sheet, not only loaded. The
        // newer row is word-diffed against the older one with removed words
        // inline (struck through), so match the version it renders.
        for (final text in [_pinnedText, _bEditText]) {
          expect(
            find.descendant(
              of: sheet,
              matching: find.byWidgetPredicate(
                (w) => w is Text && _renderedVersion(w) == text,
              ),
            ),
            findsWidgets,
          );
        }
        expect(find.textContaining(bySeq[1]!.actorTitle), findsWidgets);
        expect(find.textContaining(bySeq[2]!.actorTitle), findsWidgets);
      },
    );

    await logout(tester);
    await loginAs(tester, fixture.helperEmail);
    await openRequestFromMyWork(tester, requestTitle: title);

    late Finder quoteTile;
    await runE2eStep('B quotes the fact in the discussion', () async {
      await _openFactFromSourceMessage(tester);
      await tapAndSettle(
        tester,
        _action(_l10n.beaconRoomFactCardActionQuoteInChat),
      );
      await pumpUntil(
        tester,
        () => _roomCubit(tester).state.pendingQuotedFact?.factCardId == factId,
        label: 'pending quoted fact',
      );
      await sendRoomMessage(tester, _quoteBody);
      quoteTile = _tileWithBody(_quoteBody);
      final quoted = tester.widget<RoomMessageTile>(quoteTile).message;
      expect(quoted.quotedFact?.factCardId, factId);
      expect(quoted.quotedFact?.seq, 2);
      expect(
        find.descendant(
          of: quoteTile,
          matching: find.textContaining(
            _l10n.beaconRoomFactQuoteChangedSinceQuoted,
          ),
        ),
        findsNothing,
      );
    });

    await runE2eStep(
      'A edits again; B sees "Changed since quoted" live',
      () async {
        await postGraphQlAsUser(
          email: fixture.authorEmail,
          restoreEmail: fixture.helperEmail,
          request: GBeaconFactCardCorrectReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..factCardId = factId
              ..newText = _aSecondEditText
              ..baseRevisionSeq = 2,
          ),
        );
        final changed = find.descendant(
          of: quoteTile,
          matching: find.descendant(
            of: find.byType(RoomMessageFactQuote),
            matching: find.textContaining(
              _l10n.beaconRoomFactQuoteChangedSinceQuoted,
            ),
          ),
        );
        await pumpUntilVisible(
          tester,
          changed,
          label: 'Changed since quoted without reload',
        );
        // The bubble keeps the quoted-at-send snapshot (B's edit), not A's
        // new wording.
        expect(
          tester
              .widget<RoomMessageTile>(quoteTile)
              .message
              .quotedFact
              ?.factText,
          _bEditText,
        );
        expect(
          find.descendant(
            of: find.descendant(
              of: quoteTile,
              matching: find.byType(RoomMessageFactQuote),
            ),
            matching: find.textContaining(_bEditText),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: quoteTile,
            matching: find.textContaining(_aSecondEditText),
          ),
          findsNothing,
        );
      },
    );
  });
}
