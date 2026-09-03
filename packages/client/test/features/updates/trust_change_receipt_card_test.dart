import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/ui/widget/trust_change_receipt_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

AttentionReceipt _trustReceipt({
  required String presentationKey,
  String title = 'Trust in Alex increased',
  String body = 'After "Move help this weekend" closed, your trust shifted.',
  String presentationPayloadJson =
      '{"beaconTitle":"Move help this weekend","eventType":"trustGivenChanged"}',
  String? beaconId = 'b1234567890ab',
  DateTime? seenAt,
}) {
  return AttentionReceipt(
      id: 'receipt-trust-1',
      category: 'connections',
      kind: 'reviewReady',
      priority: 'normal',
      title: title,
      body: body,
      actionUrl: '/profile/view/u1',
      createdAt: DateTime(2026, 8, 4, 14, 30),
      collapsedCount: 1,
      presentationKey: presentationKey,
      presentationPayloadJson: presentationPayloadJson,
      beaconId: beaconId,
      actorUserId: 'actor-1',
      seenAt: seenAt ?? DateTime.utc(2026, 8, 4),
    );
}

Widget _wrap(Widget child) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: TenturaResponsiveScope(
    child: Scaffold(body: child),
  ),
);

void main() {
  final l10n = L10nEn();

  Future<void> pumpCard(
    WidgetTester tester, {
    required String presentationKey,
    String title = 'Trust in Alex increased',
    String body = 'After "Move help this weekend" closed, your trust shifted.',
  }) async {
    await tester.pumpWidget(
      _wrap(
        TrustChangeReceiptCard(
          receipt: _trustReceipt(
            presentationKey: presentationKey,
            title: title,
            body: body,
          ),
          onTap: () {},
          onMarkSeen: () {},
          onSettle: () {},
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('trust_given_changed_up shows upward glyph and server copy', (
    tester,
  ) async {
    await pumpCard(tester, presentationKey: 'trust_given_changed_up');

    expect(find.text('Trust in Alex increased: After "Move help this weekend" closed, your trust shifted.'), findsOneWidget);
    expect(find.byIcon(TenturaIcons.arrowUp), findsOneWidget);
    expect(find.text('Move help this weekend'), findsOneWidget);
    expect(find.textContaining('ago'), findsOneWidget);
    expect(find.textContaining('bin'), findsNothing);
    expect(find.textContaining('edge weight'), findsNothing);
    expect(find.textContaining('MeritRank'), findsNothing);
  });

  testWidgets('trust_given_changed_down shows downward glyph', (tester) async {
    await pumpCard(
      tester,
      presentationKey: 'trust_given_changed_down',
      title: 'Trust in Alex decreased',
      body: 'After the request closed, your trust shifted down.',
    );

    expect(find.textContaining('Trust in Alex decreased'), findsOneWidget);
    expect(find.byIcon(TenturaIcons.arrowDown), findsOneWidget);
  });

  testWidgets('trust_received_changed_neutral shows flat glyph', (tester) async {
    await pumpCard(
      tester,
      presentationKey: 'trust_received_changed_neutral',
      title: 'Someone reviewed you',
      body: 'No significant change in how they trust you.',
    );

    expect(find.textContaining('Someone reviewed you'), findsOneWidget);
    expect(find.byIcon(TenturaIcons.updates), findsOneWidget);
  });

  testWidgets('blank copy uses direction-agnostic trust fallbacks', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        TrustChangeReceiptCard(
          receipt: _trustReceipt(
            presentationKey: 'trust_received_changed_up',
            title: '',
            body: '',
            presentationPayloadJson: '{}',
            beaconId: null,
          ),
          onTap: () {},
          onMarkSeen: () {},
          onSettle: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text(l10n.updatesFallbackTitleTrustReceivedChanged), findsOneWidget);
    expect(
      find.textContaining(l10n.updatesFallbackBodyTrustReceivedChanged),
      findsOneWidget,
    );
    expect(find.byIcon(TenturaIcons.arrowUp), findsOneWidget);
  });
}
