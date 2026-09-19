import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/inbox/ui/widget/tombstone_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _bai = Profile(id: 'u1', displayName: 'Bai Yue');

AttentionReceipt _event({String id = 'ev1'}) => AttentionReceipt(
  id: id,
  category: 'requestProgress',
  kind: 'roomMessagePosted',
  priority: 'normal',
  title: 'Anna',
  body: 'A message',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 6, 19, 16, 40),
  collapsedCount: 1,
  presentationPayloadJson: '{"eventType":"roomMessagePosted"}',
  surface: AttentionSurface.activity,
);

AttentionReceipt _tombstone({
  AttentionForwardOutcome outcome = AttentionForwardOutcome.helping,
  bool seen = true,
  List<AttentionReceipt> events = const [],
}) => AttentionReceipt(
  id: 't1',
  category: 'forward',
  kind: 'relayReceived',
  priority: 'normal',
  title: 'Наши требования',
  body: 'Bai Yue',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 6, 19, 16, 40),
  collapsedCount: 1,
  presentationPayloadJson: '{"eventType":"relayReceived"}',
  surface: AttentionSurface.activity,
  beaconId: 'b1',
  seenAt: seen ? DateTime.utc(2026, 6, 19, 17) : null,
  forwardOutcome: outcome,
  eventTotal: events.length,
  eventsPreview: events,
);

Widget _host(
  Widget child, {
  Locale locale = const Locale('ru'),
  double textScaler = 1,
  Size size = const Size(360, 640),
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: locale,
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: TextScaler.linear(textScaler),
    ),
    child: TenturaResponsiveScope(
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: size.width, child: child),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('header quotes the title and attributes the last forwarder', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        TombstoneRow(
          receipt: _tombstone(),
          forwarder: _bai,
          onOpenBeacon: () {},
          onDismiss: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('«Наши требования» · от Bai Yue'), findsOneWidget);
    // The last forwarder's avatar, not a send glyph (spec §8).
    expect(find.byType(TenturaAvatar), findsOneWidget);
  });

  testWidgets('each outcome reads as a past-tense event sentence (A3)', (
    tester,
  ) async {
    const expected = {
      AttentionForwardOutcome.helping: 'Вы предложили помощь',
      AttentionForwardOutcome.watching: 'Вы начали следить',
      AttentionForwardOutcome.notInterested: 'Вы отказались',
      AttentionForwardOutcome.closedBeforeResponse:
          'Автор закрыл запрос до вашего ответа',
      AttentionForwardOutcome.deletedBeforeResponse: 'Запрос удалён',
    };
    for (final MapEntry(key: outcome, value: sentence) in expected.entries) {
      await tester.pumpWidget(
        _host(
          TombstoneRow(
            key: ValueKey(outcome),
            receipt: _tombstone(outcome: outcome),
            forwarder: _bai,
            onOpenBeacon: () {},
            onDismiss: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(sentence), findsOneWidget, reason: '$outcome');
    }
  });

  testWidgets('the private x is a labelled >=48dp button and removes the row', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(
      _host(
        TombstoneRow(
          receipt: _tombstone(),
          forwarder: _bai,
          onOpenBeacon: () {},
          onDismiss: () => dismissed++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final target = find.byKey(TombstoneRow.dismissKey);
    expect(target, findsOneWidget);
    expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(target).width, greaterThanOrEqualTo(48));

    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(dismissed, 1);
  });

  testWidgets('carries no dot and no sub-cards, even unseen and with events', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        TombstoneRow(
          receipt: _tombstone(seen: false, events: [_event(), _event(id: 'e2')]),
          forwarder: _bai,
          onOpenBeacon: () {},
          onDismiss: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Positive first: the row itself did render.
    expect(find.text('Вы предложили помощь'), findsOneWidget);
    expect(find.byType(TenturaPresenceDot), findsNothing);
    expect(find.byType(AttentionMiniCard), findsNothing);
  });

  testWidgets('notInterested also offers Вернуть; other outcomes do not', (
    tester,
  ) async {
    var restored = 0;
    await tester.pumpWidget(
      _host(
        TombstoneRow(
          receipt: _tombstone(outcome: AttentionForwardOutcome.notInterested),
          forwarder: _bai,
          onOpenBeacon: () {},
          onDismiss: () {},
          onRestore: () => restored++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(TombstoneRow.restoreKey));
    await tester.pumpAndSettle();
    expect(restored, 1);

    await tester.pumpWidget(
      _host(
        TombstoneRow(
          receipt: _tombstone(),
          forwarder: _bai,
          onOpenBeacon: () {},
          onDismiss: () {},
          onRestore: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(TombstoneRow.restoreKey), findsNothing);
  });

  testWidgets('in a list at 360 dp and 2x text, the row below it still builds', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _host(
        SizedBox(
          height: 640,
          child: ListView(
            children: [
              TombstoneRow(
                receipt: _tombstone(),
                forwarder: _bai,
                onOpenBeacon: () {},
                onDismiss: () {},
              ),
              const Text('следующая строка', key: ValueKey('next')),
            ],
          ),
        ),
        textScaler: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TombstoneRow), findsOneWidget);
    expect(find.text('Вы предложили помощь'), findsOneWidget);
    // A long header at 2x has silently unbuilt the items under it before.
    expect(find.byKey(const ValueKey('next')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
