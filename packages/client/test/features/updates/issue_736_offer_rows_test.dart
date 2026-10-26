import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

// R9 QA rework of #736 and #700, with receipts shaped as the server writes
// them (`AttentionPolicy._presentationPayload`,
// `BeaconNotificationCopyBuilder`):
// - #736: the author's row for a help offer (`helpOfferSubmitted`) is titled
//   with the helper's name only, so it said nothing about an offer.
// - #700: the helper's row for an accepted offer (`offerAccepted`) is titled
//   «Alice GQ2 accepted your offer» in English and stayed English in RU.
// - #736: on a 375 px phone the headline was one ellipsized line, so the
//   event after the name was cut off («Dave GQ2 can't mak…»).

const _request = 'QA496 trail 01:40';

String _offerPayload({String excerpt = 'Eve can help'}) => jsonEncode({
  'eventType': 'helpOfferSubmitted',
  'personal': true,
  'actorUserId': 'u-eve',
  'beaconId': 'B1',
  'targetEntityId': 'u-eve',
  'excerpt': excerpt,
});

String _acceptedPayload() => jsonEncode({
  'eventType': 'offerAccepted',
  'personal': true,
  'actorUserId': 'u-alice',
  'beaconId': 'B1',
  'targetEntityId': 'u-bob',
  'beaconTitle': _request,
  'excerpt': 'I can bring gloves',
});

UpdatesFeedRowCopy _offerRow(
  L10n l10n, {
  String excerpt = 'Eve can help',
  String? actorName,
}) => resolveUpdatesFeedRowCopy(
  title: 'Eve GQ2',
  body: excerpt,
  presentationKey: 'help_offer_submitted',
  presentationPayloadJson: _offerPayload(excerpt: excerpt),
  l10n: l10n,
  actorName: actorName,
);

UpdatesFeedRowCopy _acceptedRow(
  L10n l10n, {
  String title = 'Alice GQ2 accepted your offer',
  String? actorName,
}) => resolveUpdatesFeedRowCopy(
  title: title,
  body: '$_request — I can bring gloves',
  presentationKey: 'offer_accepted',
  presentationPayloadJson: _acceptedPayload(),
  l10n: l10n,
  actorName: actorName,
);

AttentionReceipt _inviteReceipt() => AttentionReceipt(
  id: 'r1',
  category: 'requestProgress',
  kind: 'authorInviteDeclined',
  priority: 'normal',
  title: 'Bob',
  body: "Bob can't help",
  actionUrl: '/#/view?id=B1',
  createdAt: DateTime.now().toUtc(),
  collapsedCount: 1,
  presentationKey: 'author_invite_declined',
  presentationPayloadJson: jsonEncode({
    'eventType': 'authorInviteDeclined',
    'personal': true,
    'actorUserId': 'u-bob',
    'beaconId': 'B1',
    'targetEntityId': 'u-bob',
    'excerpt': '',
  }),
  surface: AttentionSurface.activity,
  beaconId: 'B1',
);

Future<void> _pumpPhone(WidgetTester tester, Locale locale) async {
  const size = Size(375, 667);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: UpdatesFeedTile(
              receipt: _inviteReceipt(),
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

RenderParagraph _headline(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains(text),
      ),
    );

void main() {
  final en = L10nEn();
  final ru = L10nRu();

  group('an offer row says someone offered help (#736)', () {
    test('the headline names the event, in each locale', () {
      for (final (l10n, line) in <(L10n, String)>[
        (en, 'Eve GQ2 offered help'),
        (ru, 'Eve GQ2 предложил(а) помощь'),
      ]) {
        final copy = _offerRow(l10n);
        expect(copy.headline, line, reason: l10n.localeName);
        expect(copy.body, 'Eve can help', reason: l10n.localeName);
      }
    });

    test('the known contact name wins over the server title', () {
      expect(_offerRow(en, actorName: 'Evie').headline, 'Evie offered help');
    });

    test('an offer with no note still says what happened', () {
      final copy = _offerRow(ru, excerpt: '');
      expect(copy.headline, 'Eve GQ2 предложил(а) помощь');
      expect(copy.body, isEmpty);
    });
  });

  group('an accepted offer reads in the locale (#700)', () {
    test('Russian: «Alice GQ2 принял(а) ваше предложение»', () {
      final copy = _acceptedRow(ru);
      expect(copy.headline, 'Alice GQ2 принял(а) ваше предложение');
      expect(copy.body, _request);
    });

    test('English keeps the same sentence, once', () {
      final copy = _acceptedRow(en);
      expect(copy.headline, 'Alice GQ2 accepted your offer');
      expect(copy.body, _request);
    });

    test('the known contact name wins over the server title', () {
      expect(
        _acceptedRow(ru, actorName: 'Алиса').headline,
        'Алиса принял(а) ваше предложение',
      );
    });

    test('guard: a row with no name says the offer was accepted', () {
      expect(
        _acceptedRow(ru, title: 'Offer accepted').headline,
        ru.updatesFallbackTitleOfferAccepted,
      );
    });
  });

  // The test font draws every glyph as a square (15 px here), about twice as
  // wide as the app font, and «Just now» beside it leaves the headline
  // ~145 px: the QA strings would need three test-font lines. What the test
  // can show honestly: a headline that needs a second line at 375 px gets
  // it, where one ellipsized line cut the event off.
  group('on a 375 px phone the event is not cut off (#736)', () {
    testWidgets("English: «Bob can't make it» is shown whole", (
      tester,
    ) async {
      await _pumpPhone(tester, const Locale('en'));
      final paragraph = _headline(tester, "can't make it");
      expect(paragraph.text.toPlainText(), "Bob can't make it");
      expect(paragraph.didExceedMaxLines, isFalse);
    });

    testWidgets('Russian: «Bob не сможет» is shown whole', (tester) async {
      await _pumpPhone(tester, const Locale('ru'));
      final paragraph = _headline(tester, 'не сможет');
      expect(paragraph.text.toPlainText(), 'Bob не сможет');
      expect(paragraph.didExceedMaxLines, isFalse);
    });
  });
}
