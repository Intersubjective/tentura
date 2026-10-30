import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #736 round 3: a Post shared with the viewer (`relay_received` on a Post)
// read only «Q1030 Alice» in Updates — the server titles the receipt with
// the sender's name, a Post has no title, and the English body «… shared a
// post with you» is dropped as canned. Activity reads «Q1030 Alice shared a
// post / QA736 r3 garden post»; the Updates row now says the same.

AttentionReceipt _postShared() => AttentionReceipt(
  id: 'r1',
  category: 'coordination',
  kind: 'newRelay',
  priority: 'low',
  title: 'Q1030 Alice',
  body: 'Q1030 Alice shared a post with you',
  actionUrl: '/#/view?id=B1',
  createdAt: DateTime.utc(2026, 10, 30, 12, 10),
  collapsedCount: 1,
  presentationKey: 'relay_received',
  presentationPayloadJson: jsonEncode({
    'eventType': 'relayReceived',
    'personal': true,
    'actorUserId': 'u-alice',
    'beaconId': 'B1',
    'excerpt': '',
  }),
  surface: AttentionSurface.activity,
  beaconId: 'B1',
  actorUserId: 'u-alice',
  beaconKind: 1,
  postRootExcerpt: 'QA736 r3 garden post',
);

Future<void> _pump(WidgetTester tester, Locale locale) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: UpdatesFeedTile(
            receipt: _postShared(),
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
  testWidgets('a shared Post says who shared it and which Post (EN)', (
    tester,
  ) async {
    await _pump(tester, const Locale('en'));

    expect(
      find.text('Q1030 Alice shared a post', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('QA736 r3 garden post'), findsOneWidget);
  });

  testWidgets('a shared Post says who shared it and which Post (RU)', (
    tester,
  ) async {
    await _pump(tester, const Locale('ru'));

    expect(
      find.text('Q1030 Alice поделился(ась) постом', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('QA736 r3 garden post'), findsOneWidget);
  });
}
