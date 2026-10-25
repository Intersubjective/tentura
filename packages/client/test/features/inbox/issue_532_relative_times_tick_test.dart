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
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/ui/widget/post_conversation_row.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/features/inbox/ui/widget/tombstone_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

/// #532 — relative times froze: the Requests card said «Time to sum up · 2m
/// ago» for four minutes, because its age was read off the clock once, when
/// the card was built. Every age on the Requests and Conversations lists must
/// follow the shared ticking clock, with no data change.
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

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('en'),
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: TenturaResponsiveScope(
    child: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 400, child: child),
      ),
    ),
  ),
);

RequestAttentionCard _card(AttentionReceipt change) => RequestAttentionCard(
  beacon: _beacon,
  relation: RequestAttentionRelation.following,
  facts: const RequestAttentionFacts(
    requestId: 'b1',
    unclearedOptionalEvents: 1,
  ),
  provenance: InboxProvenance.empty,
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

  setUp(() {
    // 30 s after the event, on a :30 boundary of the shared clock.
    clock = _created.add(const Duration(seconds: 30));
    RelativeTimestampTicker.debugClock = () => clock;
  });
  tearDown(() => RelativeTimestampTicker.debugClock = null);

  Future<void> advance(WidgetTester tester, Duration by) async {
    clock = clock.add(by);
    await tester.pump(by);
  }

  String changeAge(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(RequestAttentionCard.changeLineKey),
          matching: find.byType(Text),
        ),
      )
      .last
      .data!;

  testWidgets('a Requests card change line age keeps counting while open', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(_card(_blocker(_created))));
    await tester.pump();
    expect(changeAge(tester), 'now');

    await advance(tester, const Duration(minutes: 1));
    expect(changeAge(tester), '1m');
    await advance(tester, const Duration(minutes: 1));
    expect(changeAge(tester), '2m');
    // The spoken line carries the same age.
    expect(find.bySemanticsLabel(RegExp('2 minutes ago')), findsWidgets);
    semantics.dispose();
  });

  testWidgets('a change line older than a week keeps its absolute date', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_card(_blocker(_created.subtract(const Duration(days: 30))))),
    );
    await tester.pump();
    final before = changeAge(tester);
    expect(before, 'Sep 14');

    await advance(tester, const Duration(minutes: 2));
    expect(changeAge(tester), before);
  });

  testWidgets('a Conversations row age keeps counting while open', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        PostConversationRow(
          post: PostSummary(
            id: 'P1',
            authorId: 'U1',
            authorName: 'Anna',
            rootExcerpt: 'Who is in on Saturday?',
            lastMessageExcerpt: 'Me, what time?',
            lastActivityAt: _created,
          ),
          // The clock the list was arranged against stays put: no data change.
          now: clock,
          onOpen: () {},
        ),
      ),
    );
    await tester.pump();
    // The card's short age (#476), as on the tombstone below.
    expect(find.text('now'), findsOneWidget);

    await advance(tester, const Duration(minutes: 2));
    expect(find.text('now'), findsNothing);
    expect(find.text('2m'), findsOneWidget);
  });

  testWidgets('a tombstone age keeps counting while open', (tester) async {
    await tester.pumpWidget(
      _host(
        TombstoneRow(
          receipt: AttentionReceipt(
            id: 't1',
            category: 'forward',
            kind: 'relayReceived',
            priority: 'normal',
            title: 'Van to the lake',
            body: 'Bai Yue',
            actionUrl: '/#/',
            createdAt: _created,
            collapsedCount: 1,
            presentationPayloadJson: '{"eventType":"relayReceived"}',
            surface: AttentionSurface.activity,
            beaconId: 'b1',
            seenAt: _created,
            forwardOutcome: AttentionForwardOutcome.helping,
          ),
          onOpenBeacon: () {},
          onDismiss: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('now'), findsOneWidget);

    await advance(tester, const Duration(minutes: 2));
    expect(find.text('now'), findsNothing);
    expect(find.text('2m'), findsOneWidget);
  });
}
