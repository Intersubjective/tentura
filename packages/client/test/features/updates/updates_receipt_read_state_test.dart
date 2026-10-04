import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

void main() {
  for (final actor in <Profile?>[
    null,
    const Profile(id: 'actor-a', displayName: 'Actor'),
  ]) {
    testWidgets(
      'receipt read state survives ${actor == null ? 'glyph' : 'avatar'} rendering without actions',
      (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        try {
          var actions = 0;
          final receipt = AttentionReceipt(
            id: 'receipt-a',
            category: 'social',
            kind: 'event',
            priority: 'normal',
            title: 'A connection update',
            body: 'Optional attention',
            actionUrl: '/home/inbox/history',
            createdAt: DateTime.utc(2026, 10, 4),
            collapsedCount: 1,
            presentationPayloadJson: '{}',
            surface: AttentionSurface.activity,
          );

          for (final seen in [false, true, false]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: TenturaTheme.light(),
                localizationsDelegates: L10n.localizationsDelegates,
                supportedLocales: L10n.supportedLocales,
                home: TenturaResponsiveScope(
                  child: Scaffold(
                    body: UpdatesFeedTile(
                      actor: actor,
                      receipt: receipt.copyWith(
                        seenAt: seen ? DateTime.utc(2026, 10, 4, 12) : null,
                      ),
                      onTap: () => actions++,
                      onMarkSeen: () => actions++,
                      onMarkUnseen: () => actions++,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.bySemanticsIdentifier(TestIds.updatesReceipt(receipt.id)),
              findsOneWidget,
            );
            expect(
              find.bySemanticsIdentifier(
                TestIds.updatesReceiptReadState(receipt.id, seen: seen),
              ),
              findsOneWidget,
            );
            expect(
              tester
                  .getSemantics(
                    find.bySemanticsIdentifier(
                      TestIds.updatesReceiptReadState(receipt.id, seen: seen),
                    ),
                  )
                  .getSemanticsData()
                  .identifier,
              TestIds.updatesReceiptReadState(receipt.id, seen: seen),
            );
            expect(
              find.bySemanticsIdentifier(
                TestIds.updatesReceiptReadState(receipt.id, seen: !seen),
              ),
              findsNothing,
            );
            expect(actions, 0);
          }
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
