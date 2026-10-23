// #685: the author's Requests card said only «Promise withdrawn» — no name,
// no reason, and a word the product does not use. A withdrawal now says who
// withdrew their help offer and the reason they chose (the author and
// stewards, who get this event, see that reason on the People tab anyway).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

const _payload =
    '{"eventType":"promiseWithdrawn","beaconTitle":"Move a couch",'
    '"excerpt":"","withdrawReason":"timing"}';
const _payloadNoReason =
    '{"eventType":"promiseWithdrawn","beaconTitle":"Move a couch",'
    '"excerpt":""}';

AttentionReceipt _receipt({String payload = _payload}) => AttentionReceipt(
  id: 'e1',
  category: 'coordination',
  kind: 'commitmentEvent',
  priority: 'normal',
  // What the server writes for this event: the helper's name, and push copy.
  title: 'Cleo QA2',
  body: 'Cleo QA2 withdrew their help',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 10, 23, 9),
  collapsedCount: 1,
  presentationKey: 'promise_withdrawn',
  presentationPayloadJson: payload,
  surface: AttentionSurface.activity,
  actorUserId: 'Ucleo',
);

void main() {
  final en = L10nEn();
  final ru = L10nRu();

  group('under a Request header', () {
    RequestScopedEventCopy copy(
      L10n l10n, {
      String payload = _payload,
      String title = 'Cleo QA2',
      String? actorName,
    }) => requestScopedEventCopy(
      title: title,
      body: 'Cleo QA2 withdrew their help',
      presentationKey: 'promise_withdrawn',
      presentationPayloadJson: payload,
      requestTitle: 'Move a couch',
      actorName: actorName,
      l10n: l10n,
    );

    test('names who withdrew and why', () {
      final c = copy(en);
      expect(c.event, 'Cleo QA2 withdrew their help offer');
      expect(c.excerpt, en.withdrawTimingChanged);
      expect(c.event, isNot(contains('romise')));
    });

    test('in Russian', () {
      final c = copy(ru);
      expect(c.event, 'Cleo QA2: предложение помощи отозвано');
      expect(c.excerpt, ru.withdrawTimingChanged);
    });

    test('the contact name wins over the server title', () {
      expect(
        copy(en, actorName: 'Cleo').event,
        'Cleo withdrew their help offer',
      );
    });

    test('no name and no reason: still plain words', () {
      final c = copy(en, title: 'Someone', payload: _payloadNoReason);
      expect(c.event, en.updatesFallbackTitleHelpWithdrawn);
      expect(c.excerpt, isEmpty);
    });
  });

  test('Updates row: the event, then the reason (else the Request)', () {
    final withReason = resolveUpdatesFeedRowCopy(
      title: 'Cleo QA2',
      body: 'Cleo QA2 withdrew their help',
      presentationKey: 'promise_withdrawn',
      presentationPayloadJson: _payload,
      l10n: en,
    );
    expect(withReason.headline, 'Cleo QA2 withdrew their help offer');
    expect(withReason.body, en.withdrawTimingChanged);

    final noReason = resolveUpdatesFeedRowCopy(
      title: 'Cleo QA2',
      body: 'Cleo QA2 withdrew their help',
      presentationKey: 'promise_withdrawn',
      presentationPayloadJson: _payloadNoReason,
      l10n: en,
    );
    expect(noReason.body, 'Move a couch');
  });

  testWidgets('the card row shows the helper and the reason, with no '
      'profile loaded', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: AttentionMiniCard(
              receipt: _receipt(),
              requestTitle: 'Move a couch',
            ),
          ),
        ),
      ),
    );

    expect(
      find.textContaining('Cleo QA2 withdrew their help offer'),
      findsOneWidget,
    );
    expect(find.textContaining(en.withdrawTimingChanged), findsOneWidget);
    expect(find.textContaining('Promise'), findsNothing);
  });

  testWidgets('with the profile, the name is said once', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: AttentionMiniCard(
              receipt: _receipt(),
              actor: const Profile(id: 'Ucleo', displayName: 'Cleo QA2'),
              requestTitle: 'Move a couch',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Cleo QA2 withdrew their help offer'), findsOneWidget);
  });
}
