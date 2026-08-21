import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/ui/widget/updates_receipt_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

AttentionReceipt _receipt({
  String title = 'Alex accepted your ask',
  String body = 'Garden cleanup — Bring tools',
  String? presentationKey = 'commitment_accepted',
  String presentationPayloadJson =
      '{"beaconTitle":"Garden cleanup","eventType":"commitmentAccepted"}',
  String? beaconId = 'b1234567890ab',
  DateTime? createdAt,
  bool requiresAction = false,
}) =>
    AttentionReceipt(
      id: 'receipt-1',
      category: 'coordination',
      kind: 'commitmentAccepted',
      priority: 'normal',
      title: title,
      body: body,
      actionUrl: '/#/',
      createdAt: createdAt ?? DateTime(2026, 8, 4, 14, 30),
      collapsedCount: 1,
      presentationKey: presentationKey,
      presentationPayloadJson: presentationPayloadJson,
      beaconId: beaconId,
      actorUserId: 'actor-1',
      requiresAction: requiresAction,
    );

Widget _wrap(Widget child) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('empty title and body render non-empty tappable card', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        UpdatesReceiptCard(
          receipt: _receipt(
            title: '',
            body: '',
            presentationKey: 'needs_me',
            presentationPayloadJson: '{}',
            beaconId: null,
          ),
          onTap: () => tapped = true,
          onMarkSeen: () {},
          onSettle: () {},
        ),
      ),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel(L10nEn().updatesFallbackTitleNeedsMe),
      findsOneWidget,
    );
    expect(find.text(L10nEn().updatesFallbackTitleNeedsMe), findsOneWidget);
    expect(find.text(L10nEn().updatesFallbackBodyNeedsMe), findsOneWidget);

    await tester.tap(find.byType(ListTile));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('card surfaces actor action request name and time', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        UpdatesReceiptCard(
          receipt: _receipt(),
          onTap: () {},
          onMarkSeen: () {},
          onSettle: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Alex accepted your ask'), findsOneWidget);
    expect(find.text('Garden cleanup'), findsWidgets);
    expect(find.textContaining('ago'), findsOneWidget);
  });

  testWidgets('live obligation shows explicit next-step hint', (tester) async {
    await tester.pumpWidget(
      _wrap(
        UpdatesReceiptCard(
          receipt: _receipt(requiresAction: true),
          onTap: () {},
          onMarkSeen: () {},
          onSettle: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text(L10nEn().updatesNextStepMarkDoneHint), findsOneWidget);
    expect(find.byIcon(Icons.task_alt_outlined), findsOneWidget);
  });
}
