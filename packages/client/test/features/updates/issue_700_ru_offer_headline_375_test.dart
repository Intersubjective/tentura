import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #700 QA re-check: on an iPhone SE (375 px), in Russian, the author's
// Updates row for a help offer wrapped the headline but cut its second line
// («Dave GQ2 / предложил(а) пом…»). The headline is a name and a short
// event; it is shown whole, however many lines the name needs.

const _longName = 'Dave GQ2 Konstantinopolsky';

AttentionReceipt _offerReceipt() => AttentionReceipt(
  id: 'r-offer',
  category: 'requestProgress',
  kind: 'helpOfferSubmitted',
  priority: 'normal',
  title: _longName,
  body: 'I can help on Saturday',
  actionUrl: '/#/view?id=B1',
  createdAt: DateTime.now().toUtc(),
  collapsedCount: 1,
  presentationKey: 'help_offer_submitted',
  presentationPayloadJson: jsonEncode({
    'eventType': 'helpOfferSubmitted',
    'personal': true,
    'actorUserId': 'u-dave',
    'actorName': _longName,
    'beaconId': 'B1',
    'targetEntityId': 'u-dave',
    'excerpt': 'I can help on Saturday',
  }),
  surface: AttentionSurface.activity,
  beaconId: 'B1',
);

Future<void> _pumpSe(WidgetTester tester, {bool activityRow = false}) async {
  const size = Size(375, 667);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: UpdatesFeedTile(
              receipt: _offerReceipt(),
              activityRow: activityRow,
              onTap: () {},
              onMarkSeen: () {},
              onMarkUnseen: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

RenderParagraph _headline(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('предложил(а)'),
      ),
    );

void main() {
  for (final activityRow in [false, true]) {
    testWidgets(
      'RU 375x667 (activityRow: $activityRow): a long name and '
      '«предложил(а) помощь» are shown whole',
      (tester) async {
        await _pumpSe(tester, activityRow: activityRow);
        final context = tester.element(find.byType(UpdatesFeedTile));
        expect(MediaQuery.textScalerOf(context), TextScaler.noScaling);

        final paragraph = _headline(tester);
        expect(
          paragraph.text.toPlainText(),
          '$_longName предложил(а) помощь',
        );
        // The case under test: at this width the headline needs a third
        // line, so a two-line cap cuts the event (the QA screenshot).
        final painter = TextPainter(
          text: paragraph.text,
          textDirection: TextDirection.ltr,
          textScaler: paragraph.textScaler,
        )..layout(maxWidth: paragraph.constraints.maxWidth);
        addTearDown(painter.dispose);
        expect(
          painter.computeLineMetrics().length,
          greaterThan(2),
          reason: 'precondition: the headline needs more than two lines',
        );
        // Shown whole: no line cap below what it needs, no ellipsis.
        expect(paragraph.didExceedMaxLines, isFalse);
        final maxLines = paragraph.maxLines;
        if (maxLines != null) {
          expect(maxLines, greaterThanOrEqualTo(3));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
