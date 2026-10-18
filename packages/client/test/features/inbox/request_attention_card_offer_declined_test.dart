import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #381 — a helper whose offer the author declined sees the author's reason
// on the Request's Activity card, not only on the Request page.
//
// The server already carries the reason: `CoordinationCase.declineHelpOffer`
// passes it as the `offerDeclined` receipt's excerpt, and the GraphQL
// allow-list keeps `excerpt`. The card dropped it.

const _reason = 'Thanks, but we already found a van';

const _author = Profile(id: 'a1', displayName: 'Tab QA');

final _beacon = Beacon(
  id: 'b1',
  title: 'Child: borrow moving straps',
  createdAt: DateTime.utc(2026, 10),
  updatedAt: DateTime.utc(2026, 10, 14),
  author: _author,
  viewerCanForward: true,
);

/// The receipt as the client gets it over the wire. `personal` is left out
/// unless asked for: the server writes it as a bool, and the GraphQL mapper
/// keeps only allow-listed String values, so today it never arrives and the
/// decline lands on the card's change line (QA: "Offer declined · now").
AttentionReceipt _declined({
  String id = 'd1',
  String kind = 'offerDeclined',
  String presentationKey = 'offer_declined',
  String title = 'Offer declined',
  String body = 'Child: borrow moving straps — $_reason',
  String? excerpt = _reason,
  bool? personal,
}) => AttentionReceipt(
  id: id,
  category: 'requestProgress',
  kind: kind,
  priority: 'normal',
  title: title,
  body: body,
  actionUrl: '/#/',
  createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
  collapsedCount: 1,
  presentationKey: presentationKey,
  presentationPayloadJson: jsonEncode({
    'eventType': kind,
    'actorUserId': 'a1',
    'beaconId': 'b1',
    'targetEntityId': 'helper',
    'beaconTitle': 'Child: borrow moving straps',
    'excerpt': ?excerpt,
    'personal': ?personal,
  }),
  surface: AttentionSurface.activity,
  beaconId: 'b1',
  actorUserId: 'a1',
);

RequestAttentionCard _card(List<AttentionReceipt> events) =>
    RequestAttentionCard(
      beacon: _beacon,
      relation: RequestAttentionRelation.following,
      facts: RequestAttentionFacts(
        requestId: 'b1',
        unclearedOptionalEvents: events.length,
      ),
      eventTotal: events.length,
      eventsPreview: events,
      actors: const {'a1': _author},
      onOpenBeacon: () {},
      onOpenTimeline: () {},
      onClearEvent: (_) {},
      onClearAll: () {},
    );

Widget _host(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: locale,
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: MediaQuery(
    data: const MediaQueryData(size: Size(1280, 800)),
    child: TenturaResponsiveScope(
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: 600, child: child),
        ),
      ),
    ),
  ),
);

Finder _inCard(Finder matching) => find.descendant(
  of: find.byType(RequestAttentionCard),
  matching: matching,
);

void main() {
  group('#381 — the declined helper reads the author reason on Activity', () {
    testWidgets('change line (the wire today): the reason is on the card, '
        'and the line still says the offer was declined', (tester) async {
      await tester.pumpWidget(_host(_card([_declined()])));
      await tester.pumpAndSettle();

      // Precondition: it really is the change line QA saw.
      expect(find.byKey(RequestAttentionCard.changeLineKey), findsOneWidget);
      expect(find.byKey(RequestAttentionCard.forYouZoneKey), findsNothing);

      expect(_inCard(find.textContaining(_reason)), findsOneWidget);
      expect(_inCard(find.textContaining('declined')), findsWidgets);
    });

    testWidgets('change line in Russian: the reason and a Russian decline', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(_card([_declined()]), locale: const Locale('ru')),
      );
      await tester.pumpAndSettle();

      expect(_inCard(find.textContaining(_reason)), findsOneWidget);
      expect(
        _inCard(find.textContaining(RegExp('отклон', caseSensitive: false))),
        findsWidgets,
      );
      expect(_inCard(find.textContaining('declined')), findsNothing);
    });

    testWidgets('«вам» row (personal receipt): the reason is shown under the '
        "author's name", (tester) async {
      await tester.pumpWidget(_host(_card([_declined(personal: true)])));
      await tester.pumpAndSettle();

      // Precondition: the personal path, not the change line.
      expect(find.byKey(RequestAttentionCard.forYouZoneKey), findsOneWidget);
      expect(find.byKey(RequestAttentionCard.changeLineKey), findsNothing);

      final row = find.byType(AttentionMiniCard);
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.textContaining(_reason)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.textContaining('Tab QA')),
        findsWidgets,
      );
    });

    // ------------------------------------------------------------ guards

    testWidgets('guard: a decline without words keeps the bare line', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _card([
            _declined(excerpt: '', body: 'Child: borrow moving straps'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(RequestAttentionCard.changeLineKey),
          matching: find.text('Offer declined'),
        ),
        findsOneWidget,
      );
      // No dangling «Offer declined: » on the change line.
      expect(
        find.descendant(
          of: find.byKey(RequestAttentionCard.changeLineKey),
          matching: find.textContaining(RegExp(r':\s*$')),
        ),
        findsNothing,
      );
    });

    testWidgets('guard: the change line never repeats the request title '
        '(the header already names it; blocks a body-based fix)', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_card([_declined()])));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(RequestAttentionCard.changeLineKey),
          matching: find.textContaining('Child: borrow moving straps'),
        ),
        findsNothing,
      );
    });

    testWidgets('guard: no structured excerpt means no words, even when the '
        'push body carries them', (tester) async {
      await tester.pumpWidget(
        _host(_card([_declined(excerpt: '')])),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(RequestAttentionCard.changeLineKey), findsOneWidget);
      expect(_inCard(find.textContaining(_reason)), findsNothing);
    });

    testWidgets('guard: a personal decline without words keeps its line', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _card([
            _declined(
              excerpt: '',
              body: 'Child: borrow moving straps',
              personal: true,
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Help not needed · Tab QA'), findsOneWidget);
    });

    testWidgets('guard: other general events stay one bare line — the fix '
        'is for the decline, not every change line', (tester) async {
      await tester.pumpWidget(
        _host(
          _card([
            _declined(
              id: 'c1',
              kind: 'coordinationChanged',
              presentationKey: 'coordination_changed',
              title: 'Plan updated',
              body: 'Child: borrow moving straps — Bring the straps by 10',
              excerpt: 'Bring the straps by 10',
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(RequestAttentionCard.changeLineKey),
          matching: find.text('Items updated'),
        ),
        findsOneWidget,
      );
      expect(_inCard(find.textContaining('Bring the straps')), findsNothing);
    });
  });
}
