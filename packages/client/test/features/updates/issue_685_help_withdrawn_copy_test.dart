// #685: the author's Requests card said only «Promise withdrawn» — no name,
// no reason, and a word the product does not use. A withdrawal now says who
// withdrew their help offer and the reason they chose (the author and
// stewards, who get this event, see that reason on the People tab anyway).
// 7.46.0: the event is `helpWithdrawn` (W1, #516) and the reason rides the
// headline (`attentionEventOfferWithdrawn`); a note would be the body.

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
    '{"eventType":"helpWithdrawn","beaconTitle":"Move a couch",'
    '"excerpt":"","withdrawReason":"timing","leftDiscussion":false}';
const _payloadNoReason =
    '{"eventType":"helpWithdrawn","beaconTitle":"Move a couch",'
    '"excerpt":"","leftDiscussion":false}';
const _payloadWithNote =
    '{"eventType":"helpWithdrawn","beaconTitle":"Move a couch",'
    '"excerpt":"Back next week","withdrawReason":"timing",'
    '"leftDiscussion":false}';

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
  presentationKey: 'help_withdrawn',
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
      presentationKey: 'help_withdrawn',
      presentationPayloadJson: payload,
      requestTitle: 'Move a couch',
      actorName: actorName,
      l10n: l10n,
    );

    test('names who withdrew and why', () {
      final c = copy(en);
      expect(
        c.event,
        'Cleo QA2 withdrew their help offer (${en.withdrawTimingChanged})',
      );
      expect(c.excerpt, isEmpty);
      expect(c.event, isNot(contains('romise')));
    });

    test('in Russian', () {
      final c = copy(ru);
      expect(
        c.event,
        ru.attentionEventOfferWithdrawn('Cleo QA2', ru.withdrawTimingChanged),
      );
      expect(c.excerpt, isEmpty);
    });

    test('the contact name wins over the server title', () {
      expect(
        copy(en, actorName: 'Cleo').event,
        startsWith('Cleo withdrew their help offer ('),
      );
    });

    test('the note is the excerpt', () {
      expect(copy(en, payload: _payloadWithNote).excerpt, 'Back next week');
    });

    test('a reason that is not readable: the plain line', () {
      expect(
        copy(en, payload: _payloadNoReason).event,
        'Cleo QA2 withdrew their help offer',
      );
    });

    test('no name and no reason: still plain words', () {
      final c = copy(en, title: 'Someone', payload: _payloadNoReason);
      expect(c.event, en.updatesFallbackTitleHelpWithdrawn);
      expect(c.excerpt, isEmpty);
    });
  });

  test('Updates row: who and why, then the Request and the note', () {
    final withReason = resolveUpdatesFeedRowCopy(
      title: 'Cleo QA2',
      body: 'Cleo QA2 withdrew their help',
      presentationKey: 'help_withdrawn',
      presentationPayloadJson: _payload,
      l10n: en,
    );
    expect(
      withReason.headline,
      'Cleo QA2 withdrew their help offer (${en.withdrawTimingChanged})',
    );
    expect(withReason.body, 'Move a couch');

    final withNote = resolveUpdatesFeedRowCopy(
      title: 'Cleo QA2',
      body: 'Back next week',
      presentationKey: 'help_withdrawn',
      presentationPayloadJson: _payloadWithNote,
      l10n: en,
    );
    expect(
      withNote.body,
      en.updatesOfferDeclinedBody('Move a couch', 'Back next week'),
    );
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

    expect(
      find.text(
        'Cleo QA2 withdrew their help offer (${en.withdrawTimingChanged})',
      ),
      findsOneWidget,
    );
  });
}
