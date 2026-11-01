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
import 'package:tentura/features/inbox/ui/widget/activity_offer_bounded_shell.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

/// #609 regression — the weekday date age («Wed, Oct 14, 2026» /
/// «ср, 14 окт. 2026 г.») on an Activity card's change line overflowed the
/// line at 360 dp with 2x text. The age is capped and ellipsises instead.
final _created = DateTime.utc(2026, 10, 14, 12);

final _beacon = Beacon(
  id: 'b1',
  title: 'Van to the lake',
  createdAt: DateTime.utc(2026, 10),
  updatedAt: DateTime.utc(2026, 10, 14),
  author: const Profile(id: 'a1', displayName: 'Author'),
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

Widget _host(Locale locale, {Widget? card}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: locale,
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(2)),
    child: child!,
  ),
  home: TenturaResponsiveScope(
    child: Scaffold(
      body: SingleChildScrollView(
        child:
            card ??
            RequestAttentionCard(
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
      ),
    ),
  ),
);

void main() {
  setUp(
    () => RelativeTimestampTicker.debugClock = () => DateTime.utc(2027, 1, 20),
  );
  tearDown(() => RelativeTimestampTicker.debugClock = null);

  for (final locale in const [Locale('en'), Locale('ru')]) {
    testWidgets('${locale.languageCode} 360 dp, 2x text: an earlier-year '
        'card age does not overflow the change line', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 2000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(locale));
      await tester.pump();

      expect(find.byKey(RequestAttentionCard.changeLineKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${locale.languageCode} 360 dp, 2x text: an earlier-year '
        'age does not overflow the offer card headline row', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 2000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          locale,
          card: ActivityOfferBoundedShell(
            leading: const SizedBox.square(dimension: 40),
            headline: 'Van to the lake',
            whyLine: 'Bai Yue forwarded this to you',
            createdAt: _created,
            showUnseenDot: true,
            onBodyTap: () {},
            onDismiss: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ActivityOfferBoundedShell), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
