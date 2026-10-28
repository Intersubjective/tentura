// #700 QA re-check, RU Updates:
// 1. «Your post is about to expire» (postExpiringSoon; the server writes the
//    English title in AttentionIntentCase) stayed English in Russian, while
//    push and email already say «Пост скоро истечёт». It is now one of the
//    server-titled rows the client reads in the locale.
// 2. An invite-accepted row whose accepter still has the server placeholder
//    name «New member» showed it in English until (or unless) the profile
//    loaded; it now goes through localizedDisplayName like every other name.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/util/display_name_prompt.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// The literal title and body `AttentionIntentCase.postExpiringSoon` writes.
const _serverTitle = 'Your post is about to expire';
const _serverBody = 'Your post expires in under 3 hours';
const _payload = '{"eventType":"postExpiringSoon","beaconId":"P1"}';

AttentionReceipt _expiringReceipt() => AttentionReceipt(
  id: 'r-expiring',
  category: 'requestProgress',
  kind: 'postExpiringSoon',
  priority: 'high',
  title: _serverTitle,
  body: _serverBody,
  actionUrl: '/#/view/P1?is_deep_link=true',
  createdAt: DateTime.now().toUtc(),
  collapsedCount: 1,
  presentationKey: 'post_expiring_soon',
  presentationPayloadJson: _payload,
  surface: AttentionSurface.activity,
  beaconId: 'P1',
);

void main() {
  final ru = lookupL10n(const Locale('ru'));
  final en = lookupL10n(const Locale('en'));

  group('postExpiringSoon headline', () {
    test('RU: reads «Пост скоро истечёт», as push and email do', () {
      final copy = resolveUpdatesFeedRowCopy(
        title: _serverTitle,
        body: _serverBody,
        presentationKey: 'post_expiring_soon',
        presentationPayloadJson: _payload,
        l10n: ru,
      );
      expect(copy.headline, 'Пост скоро истечёт');
      // The English server sentence does not survive as the second line.
      expect(copy.body, isNot(contains('expire')));
    });

    test('EN: keeps the server wording', () {
      final copy = resolveUpdatesFeedRowCopy(
        title: _serverTitle,
        body: _serverBody,
        presentationKey: 'post_expiring_soon',
        presentationPayloadJson: _payload,
        l10n: en,
      );
      expect(copy.headline, _serverTitle);
    });

    test('RU: a row with a blank title falls back to the same words', () {
      final copy = resolveUpdatesFeedRowCopy(
        title: '',
        body: '',
        presentationKey: 'post_expiring_soon',
        presentationPayloadJson: _payload,
        l10n: ru,
      );
      expect(copy.headline, 'Пост скоро истечёт');
    });

    testWidgets('RU Updates row shows «Пост скоро истечёт»', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: UpdatesFeedTile(
                receipt: _expiringReceipt(),
                onTap: () {},
                onMarkSeen: () {},
                onMarkUnseen: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Пост скоро истечёт'), findsOneWidget);
      expect(find.textContaining('about to expire'), findsNothing);
      expect(find.textContaining('expires in under'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('invite row with the «New member» placeholder', () {
    setUp(() => setNewMemberDisplayNameLabel(ru.newMemberDisplayName));
    tearDown(() => setNewMemberDisplayNameLabel(kNewMemberDisplayName));

    InviteAcceptedDisplayCopy copyFor(String title) =>
        resolveInviteAcceptedDisplayCopy(
          receiptTitle: title,
          receiptBody:
              'Created an account via your invitation. You are now connected.',
          presentationPayloadJson: jsonEncode({
            'eventType': 'inviteAccepted',
            'inviteOrigin': 'new_account',
          }),
          presentationKey: 'invite_accepted',
          l10n: ru,
        );

    test('before the profile loads, the title reads in the locale', () {
      expect(copyFor('New member').title, 'Новый участник');
      expect(copyFor('New member · @anna').title, 'Новый участник · @anna');
    });

    test('an offer row named by the payload reads in the locale too', () {
      expect(
        actorNameFromPresentationPayload(
          jsonEncode({
            'eventType': 'helpOfferSubmitted',
            'actorName': 'New member',
          }),
        ),
        'Новый участник',
      );
    });

    test('a chosen name is left alone', () {
      expect(copyFor('Dave GQ2 · @dave').title, 'Dave GQ2 · @dave');
      expect(copyFor('New members club').title, 'New members club');
    });
  });
}
