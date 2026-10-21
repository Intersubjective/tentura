import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

// #601 (from #381) — `offerRemoved` and `commitmentReleased` carry the
// author's reason as the receipt's excerpt, exactly like `offerDeclined`, but
// the Activity card's change line had no arm for them and dropped it. A long
// reason was also cut off at one line.

const _reason = 'Sorry, we only need someone with a car for this one';

/// The longest reason the server sends (`notificationExcerpt`: 80 characters,
/// the last one an ellipsis) — too long for one change line.
const _longReason =
    'We already have two people for Saturday and the van only seats three, sorry …';

const _requestTitle = 'Child: borrow moving straps';

const _author = Profile(id: 'a1', displayName: 'Tab QA');

final _beacon = Beacon(
  id: 'b1',
  title: _requestTitle,
  createdAt: DateTime.utc(2026, 10),
  updatedAt: DateTime.utc(2026, 10, 14),
  author: _author,
  viewerCanForward: true,
);

AttentionReceipt _receipt({
  required String kind,
  required String presentationKey,
  required String title,
  String id = 'e1',
  String? excerpt = _reason,
  bool? personal,
}) => AttentionReceipt(
  id: id,
  category: 'requestProgress',
  kind: kind,
  priority: 'normal',
  title: title,
  body: excerpt == null || excerpt.isEmpty
      ? _requestTitle
      : '$_requestTitle — $excerpt',
  actionUrl: '/#/',
  createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
  collapsedCount: 1,
  presentationKey: presentationKey,
  presentationPayloadJson: jsonEncode({
    'eventType': kind,
    'actorUserId': 'a1',
    'beaconId': 'b1',
    'targetEntityId': 'helper',
    'beaconTitle': _requestTitle,
    'excerpt': ?excerpt,
    'personal': ?personal,
  }),
  surface: AttentionSurface.activity,
  beaconId: 'b1',
  actorUserId: 'a1',
);

AttentionReceipt _removed({String? excerpt = _reason, bool? personal}) =>
    _receipt(
      kind: 'offerRemoved',
      presentationKey: 'offer_removed',
      title: 'Removed from the discussion',
      excerpt: excerpt,
      personal: personal,
    );

AttentionReceipt _released({String? excerpt = _reason, bool? personal}) =>
    _receipt(
      kind: 'commitmentReleased',
      presentationKey: 'commitment_released',
      title: 'Participation ended',
      excerpt: excerpt,
      personal: personal,
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

Widget _host(
  Widget child, {
  Locale locale = const Locale('en'),
  double width = 600,
}) => MaterialApp(
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
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  ),
);

Finder _onChangeLine(Finder matching) => find.descendant(
  of: find.byKey(RequestAttentionCard.changeLineKey),
  matching: matching,
);

void main() {
  for (final (label, build, enWord, ruWord) in [
    ('offerRemoved', _removed, 'removed', 'удал'),
    ('commitmentReleased', _released, 'ended', 'заверш'),
  ]) {
    group('#601 — $label shows the author reason on Activity', () {
      testWidgets('change line: the reason is there, and the line still '
          'says what happened', (tester) async {
        await tester.pumpWidget(_host(_card([build()])));
        await tester.pumpAndSettle();

        expect(find.byKey(RequestAttentionCard.changeLineKey), findsOneWidget);
        expect(find.byKey(RequestAttentionCard.forYouZoneKey), findsNothing);
        expect(_onChangeLine(find.textContaining(_reason)), findsOneWidget);
        expect(
          _onChangeLine(
            find.textContaining(RegExp(enWord, caseSensitive: false)),
          ),
          findsOneWidget,
        );
      });

      testWidgets('change line in Russian: the reason and Russian copy', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(_card([build()]), locale: const Locale('ru')),
        );
        await tester.pumpAndSettle();

        expect(_onChangeLine(find.textContaining(_reason)), findsOneWidget);
        expect(
          _onChangeLine(
            find.textContaining(RegExp(ruWord, caseSensitive: false)),
          ),
          findsOneWidget,
        );
      });

      testWidgets('a long reason wraps instead of being cut at one line', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(_card([build(excerpt: _longReason)])),
        );
        await tester.pumpAndSettle();

        final text = _onChangeLine(find.textContaining(_longReason));
        expect(text, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: text, matching: find.byType(RichText)),
        );
        // Precondition: it really needs more than one line here.
        expect(
          paragraph.getMaxIntrinsicWidth(double.infinity),
          greaterThan(paragraph.size.width),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
      });

      testWidgets('«вам» row (personal receipt): the reason is shown once', (
        tester,
      ) async {
        await tester.pumpWidget(_host(_card([build(personal: true)])));
        await tester.pumpAndSettle();

        expect(find.byKey(RequestAttentionCard.forYouZoneKey), findsOneWidget);
        expect(find.byKey(RequestAttentionCard.changeLineKey), findsNothing);
        final row = find.byType(AttentionMiniCard);
        expect(
          find.descendant(of: row, matching: find.textContaining(_reason)),
          findsOneWidget,
        );
      });

      testWidgets('guard: without words the line keeps its bare copy', (
        tester,
      ) async {
        await tester.pumpWidget(_host(_card([build(excerpt: '')])));
        await tester.pumpAndSettle();

        expect(find.byKey(RequestAttentionCard.changeLineKey), findsOneWidget);
        expect(
          _onChangeLine(find.textContaining(RegExp(r':\s*$'))),
          findsNothing,
        );
        expect(
          _onChangeLine(find.textContaining(_requestTitle)),
          findsNothing,
        );
      });
    });
  }

  testWidgets('guard: other change lines stay one line', (tester) async {
    await tester.pumpWidget(
      _host(
        _card([
          _receipt(
            kind: 'blockerOpened',
            presentationKey: 'blocker_opened',
            title: 'Blocker',
            excerpt: _longReason,
          ),
        ]),
        width: 360,
      ),
    );
    await tester.pumpAndSettle();

    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: _onChangeLine(find.textContaining(_longReason)),
        matching: find.byType(RichText),
      ),
    );
    expect(paragraph.maxLines, 1);
  });
}
