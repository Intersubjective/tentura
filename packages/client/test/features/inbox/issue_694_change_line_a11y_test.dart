import 'dart:convert';

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

/// #694 — the Requests card change line («Helper Two … · 3m») was visible but
/// missing from the screen-reader tree: its Semantics excluded its children
/// but was not a container, so with no tap handler it was folded into the
/// card's own labelled node. It must be its own node, carrying its words and
/// the spoken age.
const _note = 'Sorry, Saturday morning fell through';
const _line = 'Helper Two left the request (Timing no longer works) · $_note';
const _spokenLine = '$_line · 3 minutes ago';

final _created = DateTime.utc(2026, 10, 22, 12);

const _author = Profile(id: 'a1', displayName: 'Tab QA');
const _helper = Profile(id: 'h2', displayName: 'Helper Two');

final _beacon = Beacon(
  id: 'b1',
  title: 'Move a sofa',
  createdAt: DateTime.utc(2026, 10),
  updatedAt: DateTime.utc(2026, 10, 22),
  author: _author,
);

final _withdrawn = AttentionReceipt(
  id: 'e1',
  category: 'coordination',
  kind: 'commitmentEvent',
  priority: 'normal',
  title: 'Helper Two',
  body: _note,
  actionUrl: '/#/',
  createdAt: _created,
  collapsedCount: 1,
  presentationKey: 'help_withdrawn',
  presentationPayloadJson: jsonEncode({
    'eventType': 'helpWithdrawn',
    'leftDiscussion': true,
    'personal': false,
    'actorUserId': 'h2',
    'beaconId': 'b1',
    'targetEntityId': 'h2',
    'beaconTitle': 'Move a sofa',
    'withdrawReason': 'timing',
    'excerpt': _note,
  }),
  surface: AttentionSurface.myWork,
  beaconId: 'b1',
  actorUserId: 'h2',
);

RequestAttentionCard _card({ValueChanged<AttentionReceipt>? onEventTap}) =>
    RequestAttentionCard(
      beacon: _beacon,
      facts: const RequestAttentionFacts(
        requestId: 'b1',
        unclearedOptionalEvents: 1,
      ),
      eventTotal: 1,
      eventsPreview: [_withdrawn],
      actors: const {'a1': _author, 'h2': _helper},
      onOpenBeacon: () {},
      onOpenTimeline: () {},
      onClearEvent: (_) {},
      onClearAll: () {},
      onEventTap: onEventTap,
    );

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('en'),
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

void main() {
  setUp(
    () =>
        RelativeTimestampTicker.debugClock = () =>
            _created.add(const Duration(minutes: 3)),
  );
  tearDown(() => RelativeTimestampTicker.debugClock = null);

  testWidgets('with no tap handler the change line is its own node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(_card()));
    await tester.pump();

    expect(find.bySemanticsLabel(_spokenLine), findsOneWidget);
    final line = tester.getSemantics(
      find.byKey(RequestAttentionCard.changeLineKey),
    );
    expect(line.label, _spokenLine);
    // Not tappable: it is read, not offered as a button.
    expect(line.getSemanticsData().flagsCollection.isButton, isFalse);
    handle.dispose();
  });

  testWidgets('a tappable change line stays a button with the same words', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    AttentionReceipt? tapped;
    await tester.pumpWidget(_host(_card(onEventTap: (r) => tapped = r)));
    await tester.pump();

    expect(find.bySemanticsLabel(_spokenLine), findsOneWidget);
    final line = tester.getSemantics(
      find.byKey(RequestAttentionCard.changeLineKey),
    );
    expect(line.label, _spokenLine);
    expect(line.getSemanticsData().flagsCollection.isButton, isTrue);

    await tester.tap(find.byKey(RequestAttentionCard.changeLineKey));
    expect(tapped?.id, 'e1');
    handle.dispose();
  });
}
