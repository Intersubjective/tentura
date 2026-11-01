@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

/// #609 (#450 leftover) — past a week an Activity card's change line read a
/// numeric «10/31/2026» / «31.10.2026». It reads the weekday day, with the
/// year for an earlier year, and still fits one line at 375×667 RU.
final _created = DateTime.utc(2026, 10, 14, 12);

final _beacon = Beacon(
  id: 'b1',
  title: 'Van to the lake',
  createdAt: DateTime.utc(2026, 10),
  updatedAt: DateTime.utc(2026, 10, 14),
  author: const Profile(id: 'a1', displayName: 'Author'),
);

AttentionReceipt _blocker(DateTime createdAt) => AttentionReceipt(
  id: 's1',
  category: 'requestProgress',
  kind: 'blockerOpened',
  priority: 'normal',
  title: 'Petr',
  body: 'Blocker',
  actionUrl: '/#/',
  createdAt: createdAt,
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
      body: Align(
        alignment: Alignment.topCenter,
        child: child,
      ),
    ),
  ),
);

RequestAttentionCard _card(AttentionReceipt change) => RequestAttentionCard(
  beacon: _beacon,
  facts: const RequestAttentionFacts(requestId: 'b1'),
  eventTotal: 1,
  eventsPreview: [change],
  actors: const {'u4': Profile(id: 'u4', displayName: 'Petr')},
  onOpenBeacon: () {},
  onOpenTimeline: () {},
  onClearEvent: (_) {},
  onClearAll: () {},
);

void main() {
  late DateTime clock;

  setUp(() => RelativeTimestampTicker.debugClock = () => clock);
  tearDown(() => RelativeTimestampTicker.debugClock = null);

  String changeAge(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(RequestAttentionCard.changeLineKey),
          matching: find.byType(Text),
        ),
      )
      .last
      .data!;

  Future<void> pumpPhone(WidgetTester tester, Locale locale) async {
    tester.view
      ..physicalSize = const Size(375, 667)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(_card(_blocker(_created)), locale));
    await tester.pump();
  }

  for (final (locale, sameYear, earlierYear) in [
    (const Locale('ru'), 'ср, 14 окт.', 'ср, 14 окт. 2026\u202Fг.'),
    (const Locale('en'), 'Wed, Oct 14', 'Wed, Oct 14, 2026'),
  ]) {
    testWidgets('${locale.languageCode} same year: weekday day, no year', (
      tester,
    ) async {
      clock = DateTime.utc(2026, 12, 20, 12);
      await pumpPhone(tester, locale);
      expect(changeAge(tester), sameYear);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${locale.languageCode} earlier year: weekday day with the '
        'year, not a numeric date, and no overflow at 375×667', (
      tester,
    ) async {
      clock = DateTime.utc(2027, 1, 20, 12);
      await pumpPhone(tester, locale);
      expect(changeAge(tester), earlierYear);
      expect(changeAge(tester), isNot(matches(RegExp(r'\d+[./]\d+[./]\d+'))));
      expect(tester.takeException(), isNull);
    });
  }
}
