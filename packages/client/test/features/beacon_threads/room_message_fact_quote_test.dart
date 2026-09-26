// tentura-617.36: quoted fact display in the message bubble (issue #181 plan
// §7.5/§7.6). RoomMessageFactQuote renders a message's QuotedFact snapshot:
// - collapsed by default to a one-line excerpt;
// - tapping expands in place to the full quoted text and reveals an "Open"
//   action;
// - when the pinned fact has moved on (currentSeq != seq) it shows a
//   "Changed since quoted [Diff›]" line whose Diff action opens fact
//   history;
// - once the fact has been unpinned (status == removed) it shows a muted
//   "(unpinned)" marker, still renders the quoted text (even before any
//   tap), and never shows "Open";
// - throughout, the widget must render the *quoted* snapshot text, never a
//   separately-available *current* fact text.
//
// The widget does not exist yet, so every test below fails to even compile.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/quoted_fact.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_fact_quote.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _kSurfaceWidth = 360.0;

/// Long enough that a one-line collapsed excerpt has to clip it, so a
/// passing "collapsed" test can only mean real truncation, not luck.
const _kLongFactText =
    'The venue moved to 221B Baker Street, second floor, use the side '
    'entrance after 6pm since the main door is locked, and bring your own '
    'badge because the front desk stops issuing guest passes at five.';

QuotedFact _quotedFact({
  String factText = _kLongFactText,
  int seq = 1,
  int currentSeq = 1,
  int status = BeaconFactCardStatusBits.active,
}) => QuotedFact(
  factCardId: 'fact-1',
  seq: seq,
  currentSeq: currentSeq,
  status: status,
  factText: factText,
  pinnedById: 'peer-1',
  pinnedByTitle: 'Peer One',
);

/// The fact card's live state, as the room already tracks it elsewhere
/// (`RoomMessageTile.pinnedFact`). Used to prove the quote widget never
/// substitutes this live wording for the quoted snapshot.
BeaconFactCard _currentFact({required String factText}) => BeaconFactCard(
  id: 'fact-1',
  beaconId: 'b1',
  factText: factText,
  visibility: BeaconFactCardVisibilityBits.room,
  pinnedBy: 'peer-1',
  pinnedByTitle: 'Peer One',
  createdAt: DateTime.utc(2026, 6, 30, 12),
  status: BeaconFactCardStatusBits.active,
  revisionSeq: 5,
);

Widget _harness(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: MediaQuery(
      data: const MediaQueryData(size: Size(_kSurfaceWidth, 600)),
      child: TenturaResponsiveScope(
        child: Scaffold(
          body: SizedBox(width: _kSurfaceWidth, child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('collapsed quote shows a single-line excerpt, no Open yet', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(RoomMessageFactQuote(quotedFact: _quotedFact())),
    );
    await tester.pumpAndSettle();

    final excerptFinder = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.data?.contains('The venue moved to 221B Baker Street') ?? false),
    );
    expect(excerptFinder, findsOneWidget);
    expect(tester.widget<Text>(excerptFinder).maxLines, 1);

    expect(find.text(_kLongFactText), findsNothing);
    expect(find.text('Open'), findsNothing);

    // Not muted: an active fact's quote must read at normal emphasis, so
    // the unpinned test's onSurfaceVariant check actually distinguishes
    // "muted" from the default look rather than matching everything.
    final scheme = Theme.of(
      tester.element(find.byType(RoomMessageFactQuote)),
    ).colorScheme;
    final excerptStyle = tester.widget<Text>(excerptFinder).style;
    expect(excerptStyle?.color, isNot(scheme.onSurfaceVariant));
  });

  testWidgets(
    'tapping the quote expands it to the full text and reveals Open',
    (tester) async {
      await tester.pumpWidget(
        _harness(RoomMessageFactQuote(quotedFact: _quotedFact())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(RoomMessageFactQuote));
      await tester.pumpAndSettle();

      expect(find.text(_kLongFactText), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    },
  );

  testWidgets(
    'a fact revised since it was quoted shows a changed-since line whose '
    'Diff action opens fact history',
    (tester) async {
      var historyOpened = 0;
      await tester.pumpWidget(
        _harness(
          RoomMessageFactQuote(
            quotedFact: _quotedFact(currentSeq: 2),
            onOpenHistory: () => historyOpened++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Changed since quoted'), findsOneWidget);
      expect(find.textContaining('Diff'), findsOneWidget);

      final diffAction = find.byKey(const ValueKey('room-fact-quote-diff'));
      expect(diffAction, findsOneWidget);

      await tester.tap(diffAction);
      await tester.pumpAndSettle();

      expect(historyOpened, 1);
    },
  );

  testWidgets(
    'a fact unchanged since it was quoted shows no changed-since line',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          RoomMessageFactQuote(
            quotedFact: _quotedFact(seq: 3, currentSeq: 3),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Changed since quoted'), findsNothing);
    },
  );

  testWidgets(
    'an unpinned fact is muted, keeps the quoted text visible from the '
    'start, and never shows Open',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          RoomMessageFactQuote(
            quotedFact: _quotedFact(
              status: BeaconFactCardStatusBits.removed,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Quoted text is visible immediately, before any tap — an
      // implementation that shows only the "(unpinned)" marker until
      // expanded would fail this. It may be the one-line excerpt or the
      // full snapshot text; either satisfies "keeps the quoted text".
      final quotedTextFinder = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data?.contains('The venue moved to 221B Baker Street') ?? false),
      );
      expect(quotedTextFinder, findsOneWidget);

      final unpinnedMarkerFinder = find.text('(unpinned)');
      expect(unpinnedMarkerFinder, findsOneWidget);
      expect(find.text('Open'), findsNothing);

      // Muted presentation: both the quoted text and the marker read at
      // reduced emphasis (onSurfaceVariant), not the default text color.
      final scheme = Theme.of(
        tester.element(find.byType(RoomMessageFactQuote)),
      ).colorScheme;
      expect(
        tester.widget<Text>(quotedTextFinder).style?.color,
        scheme.onSurfaceVariant,
      );
      expect(
        tester.widget<Text>(unpinnedMarkerFinder).style?.color,
        scheme.onSurfaceVariant,
      );

      // Tapping must not conjure an Open action for an unpinned fact,
      // whether or not the tap otherwise toggles the excerpt.
      await tester.tap(find.byType(RoomMessageFactQuote));
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsNothing);
    },
  );

  testWidgets(
    'the bubble renders the quoted revision text, never the separately '
    'available current fact text',
    (tester) async {
      const quotedWording = 'Meet at the north gate, not the south one';
      const currentWording =
          'Meet at the west gate now, updated after printing';

      await tester.pumpWidget(
        _harness(
          RoomMessageFactQuote(
            quotedFact: _quotedFact(
              factText: quotedWording,
              currentSeq: 5,
            ),
            currentFact: _currentFact(factText: currentWording),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Collapsed: quoted wording shown, current wording never leaks in.
      expect(find.textContaining(quotedWording), findsOneWidget);
      expect(find.textContaining(currentWording), findsNothing);

      await tester.tap(find.byType(RoomMessageFactQuote));
      await tester.pumpAndSettle();

      // Expanded, the widget must show exactly the snapshot text captured
      // at quote time — never the live/current fact text, even though
      // both are available to it.
      expect(find.text(quotedWording), findsOneWidget);
      expect(find.textContaining(currentWording), findsNothing);
    },
  );
}
