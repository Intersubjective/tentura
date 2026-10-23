@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

/// #532 — an Updates row read its age off the clock once, when it was built,
/// so «Just now» stayed for minutes. The age follows the shared ticking
/// clock, with no data change.
final _created = DateTime.utc(2026, 10, 14, 12);

final _receipt = AttentionReceipt(
  id: 'r1',
  category: 'requestProgress',
  kind: 'requestStatusChanged',
  priority: 'normal',
  title: 'Status: in review',
  body: '',
  actionUrl: '/#/view?id=b1',
  createdAt: _created,
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
  beaconId: 'b1',
);

Future<void> _pump(WidgetTester tester, {bool activityRow = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: UpdatesFeedTile(
            receipt: _receipt,
            onTap: () {},
            onMarkSeen: () {},
            onMarkUnseen: () {},
            activityRow: activityRow,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

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

  testWidgets('an Updates row age keeps counting while the feed is open', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Just now'), findsOneWidget);

    await advance(tester, const Duration(minutes: 2));
    expect(find.text('Just now'), findsNothing);
    expect(find.text('2m ago'), findsOneWidget);
  });

  testWidgets('an Activity row age and its spoken form keep counting', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, activityRow: true);
    expect(find.text('now'), findsOneWidget);

    await advance(tester, const Duration(minutes: 2));
    expect(find.text('now'), findsNothing);
    expect(find.text('2m'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('2 minutes ago')), findsWidgets);
    semantics.dispose();
  });
}
