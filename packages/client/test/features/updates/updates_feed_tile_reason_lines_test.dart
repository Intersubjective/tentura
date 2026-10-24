import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #601 (from #381): the author's reason for removing someone or ending their
// participation is the point of the row; on a phone-width row it must not be
// cut off after two lines with the Request title in front of it.

const _requestTitle = 'Child: borrow moving straps';

// The server caps the reason at 80 characters.
const _reason =
    'Sorry, we found someone with a van nearby, thanks a lot for offering, really!';

AttentionReceipt _receipt({
  required String kind,
  required String presentationKey,
  required String title,
  String? excerpt,
  String body = '',
  String? beaconTitle = _requestTitle,
}) => AttentionReceipt(
  id: 'r1',
  category: 'requestProgress',
  kind: kind,
  priority: 'normal',
  title: title,
  body: body,
  actionUrl: '/#/view?id=b1',
  createdAt: DateTime.utc(2026, 6, 19, 16, 40),
  collapsedCount: 1,
  presentationKey: presentationKey,
  presentationPayloadJson: jsonEncode({
    'eventType': kind,
    'actorUserId': 'a1',
    'beaconId': 'b1',
    'targetEntityId': 'helper',
    'beaconTitle': ?beaconTitle,
    'excerpt': ?excerpt,
  }),
  surface: AttentionSurface.activity,
  beaconId: 'b1',
  beaconTitle: beaconTitle,
);

Future<void> _pump(WidgetTester tester, AttentionReceipt receipt) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(700, 900);
  addTearDown(tester.view.reset);
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

RenderParagraph _paragraphOf(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );

void main() {
  for (final (kind, presentationKey, title) in [
    ('offerRemoved', 'offer_removed', 'Removed from the discussion'),
    ('commitmentReleased', 'commitment_released', 'Participation ended'),
    ('offerDeclined', 'offer_declined', 'Help offer declined'),
  ]) {
    testWidgets('#601 $kind: the whole reason shows, wrapped past two lines', (
      tester,
    ) async {
      await _pump(
        tester,
        _receipt(
          kind: kind,
          presentationKey: presentationKey,
          title: title,
          excerpt: _reason,
          body: '$_requestTitle — $_reason',
        ),
      );
      final body = find.textContaining(_reason);
      expect(body, findsOneWidget);
      final paragraph = _paragraphOf(tester, body);
      expect(paragraph.didExceedMaxLines, isFalse);
      // It really needed more than the old two lines.
      final text = paragraph.text.toPlainText();
      final lineTops = {
        for (final box in paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length),
        ))
          box.top.round(),
      };
      expect(lineTops.length, greaterThan(2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('guard: an ordinary row keeps its two-line second line', (
    tester,
  ) async {
    await _pump(
      tester,
      _receipt(
        kind: 'somethingNew',
        presentationKey: 'something_new',
        title: 'A note from the author',
        excerpt: _reason * 3,
        beaconTitle: null,
      ),
    );
    final body = find.textContaining(_reason);
    expect(body, findsOneWidget);
    expect(tester.widget<Text>(body).maxLines, 2);
  });
}
