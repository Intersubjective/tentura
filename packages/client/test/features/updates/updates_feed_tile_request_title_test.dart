import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

AttentionReceipt _receipt({String? beaconTitle, String body = ''}) =>
    AttentionReceipt(
      id: 'r1',
      category: 'requestProgress',
      kind: 'requestStatusChanged',
      priority: 'normal',
      title: 'Status: in review',
      body: body,
      actionUrl: '/#/view?id=b1',
      createdAt: DateTime.utc(2026, 6, 19, 16, 40),
      collapsedCount: 1,
      presentationPayloadJson: '{}',
      surface: AttentionSurface.activity,
      beaconId: 'b1',
      beaconTitle: beaconTitle,
    );

Future<void> _pump(WidgetTester tester, AttentionReceipt receipt) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: UpdatesFeedTile(
            receipt: receipt,
            onTap: () {},
            onMarkSeen: () {},
            onMarkUnseen: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('names the Request the row is about', (tester) async {
    await _pump(tester, _receipt(beaconTitle: 'Group Hikes'));

    final line = tester.widget<Text>(
      find.byKey(UpdatesFeedTile.requestTitleKey),
    );
    expect(line.data, 'Group Hikes');
    expect(line.maxLines, 1);
  });

  testWidgets('no line without a readable title', (tester) async {
    await _pump(tester, _receipt());

    expect(find.byKey(UpdatesFeedTile.requestTitleKey), findsNothing);
  });

  testWidgets('no second copy when the row text already names it', (
    tester,
  ) async {
    await _pump(
      tester,
      _receipt(beaconTitle: 'Group Hikes', body: 'Group Hikes is in review'),
    );

    expect(find.byKey(UpdatesFeedTile.requestTitleKey), findsNothing);
  });
}
