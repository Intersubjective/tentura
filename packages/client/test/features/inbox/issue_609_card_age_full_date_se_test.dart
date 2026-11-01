@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/activity_offer_bounded_shell.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/features/inbox/ui/widget/tombstone_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

/// #609 (QA round 5) — on iPhone SE (375×667, 1.0x text) an earlier-year
/// card age was cut before the year («Sun, Nov 1, 20…» /
/// «вс, 1 нояб. 20…») on the Activity row for help you offered. The whole
/// date shows: it wraps rather than losing the year.
final _created = DateTime.utc(2026, 11, 1, 12);

final _beacon = Beacon(
  id: 'b1',
  title: 'Van to the lake for the whole weekend',
  createdAt: DateTime.utc(2026, 10),
  updatedAt: _created,
  author: const Profile(id: 'a1', displayName: 'Author'),
);

final _offered = AttentionReceipt(
  id: 't1',
  category: 'forward',
  kind: 'relayReceived',
  priority: 'normal',
  title: 'Van to the lake for the whole weekend',
  body: 'Alice',
  actionUrl: '/#/',
  createdAt: _created,
  collapsedCount: 1,
  presentationPayloadJson: '{"eventType":"relayReceived"}',
  surface: AttentionSurface.activity,
  beaconId: 'b1',
  seenAt: DateTime.utc(2026, 11, 1, 13),
  forwardOutcome: AttentionForwardOutcome.helping,
  beaconAuthorId: 'a1',
  beaconAuthorName: 'Alice',
);

final _change = AttentionReceipt(
  id: 's1',
  category: 'requestProgress',
  kind: 'blockerOpened',
  priority: 'normal',
  title: 'Petr',
  body: 'Blocker',
  actionUrl: '/#/',
  createdAt: _created,
  collapsedCount: 1,
  presentationKey: 'blocker_opened',
  presentationPayloadJson:
      '{"eventType":"blockerOpened","personal":false,'
      '"excerpt":"no gate key"}',
  surface: AttentionSurface.activity,
  beaconId: 'b1',
  actorUserId: 'u4',
);

Widget _host(Widget child, Locale locale) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: locale,
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: TenturaResponsiveScope(
    child: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  ),
);

final _cards = <String, Widget Function()>{
  'offered-help row': () => TombstoneRow(
    receipt: _offered,
    forwarder: const Profile(id: 'a1', displayName: 'Alice'),
    onOpenBeacon: () {},
    onDismiss: () {},
  ),
  'offer card headline row': () => ActivityOfferBoundedShell(
    leading: const SizedBox.square(dimension: 40),
    headline: 'Van to the lake for the whole weekend',
    whyLine: 'Alice forwarded this to you',
    createdAt: _created,
    showUnseenDot: true,
    onBodyTap: () {},
    onDismiss: () {},
  ),
  'request card change line': () => RequestAttentionCard(
    beacon: _beacon,
    facts: const RequestAttentionFacts(requestId: 'b1'),
    eventTotal: 1,
    eventsPreview: [_change],
    actors: const {'u4': Profile(id: 'u4', displayName: 'Petr')},
    onOpenBeacon: () {},
    onOpenTimeline: () {},
    onClearEvent: (_) {},
    onClearAll: () {},
  ),
};

void main() {
  setUp(
    () =>
        RelativeTimestampTicker.debugClock = () => DateTime.utc(2027, 1, 20, 9),
  );
  tearDown(() => RelativeTimestampTicker.debugClock = null);

  for (final (locale, fullDate) in const [
    (Locale('en'), 'Sun, Nov 1, 2026'),
    (Locale('ru'), 'вс, 1 нояб. 2026\u202Fг.'),
  ]) {
    for (final MapEntry(key: name, value: card) in _cards.entries) {
      testWidgets('${locale.languageCode} 375×667 1.0x: the $name shows the '
          'whole earlier-year date', (tester) async {
        tester.view
          ..physicalSize = const Size(375, 667)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_host(card(), locale));
        await tester.pump();

        final age = find.text(fullDate);
        expect(age, findsWidgets);
        for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.descendant(of: age, matching: find.byType(RichText)),
        )) {
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '«$fullDate» is cut on the $name',
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
