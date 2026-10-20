// #416: the mini-card × announces "Dismiss update" once (its tooltip and
// its icon label both said it, and web joins them into one aria-label).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/a11y_spoken.dart';

const _anna = Profile(id: 'u1', displayName: 'Anna');

AttentionReceipt _receipt() => AttentionReceipt(
  id: 'e1',
  category: 'requestProgress',
  kind: 'helpOfferSubmitted',
  priority: 'normal',
  title: 'Offered help',
  body: 'Body',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 6, 19, 16, 40),
  collapsedCount: 1,
  presentationKey: 'help_offer_submitted',
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
  actorUserId: _anna.id,
);

void main() {
  testWidgets('the mini-card dismiss is announced once', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 640)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: AttentionMiniCard(
                receipt: _receipt(),
                actor: _anna,
                onTap: () {},
                onDismiss: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(AttentionMiniCard.dismissButtonKey), findsOneWidget);
    expect(
      spokenCount('Dismiss update'),
      1,
      reason: spokenNodes().join(' | '),
    );
    handle.dispose();
  });
}
