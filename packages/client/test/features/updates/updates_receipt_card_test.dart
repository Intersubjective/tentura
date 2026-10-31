import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
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
}) => AttentionReceipt(
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
  surface: AttentionSurface.activity,
  beaconId: beaconId,
  actorUserId: 'actor-1',
  requiresAction: requiresAction,
);

Widget _wrap(Widget child) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: TenturaResponsiveScope(
    child: Scaffold(body: child),
  ),
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
          onMarkUnseen: () {},
          onSettle: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text(L10nEn().updatesFallbackTitleNeedsMe), findsOneWidget);
    expect(find.text(L10nEn().updatesFallbackBodyNeedsMe), findsOneWidget);

    await tester.tap(find.byType(UpdatesFeedTile));
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
          onMarkUnseen: () {},
          onSettle: () {},
        ),
      ),
    );
    await tester.pump();

    // #736: the event from the key, not the English push title.
    expect(
      find.text(L10nEn().updatesFallbackTitleCommitmentAccepted),
      findsOneWidget,
    );
    expect(find.text('Garden cleanup'), findsOneWidget);
    expect(find.textContaining('ago'), findsOneWidget);
  });

  testWidgets('live obligation shows explicit next-step hint', (tester) async {
    await tester.pumpWidget(
      _wrap(
        UpdatesReceiptCard(
          receipt: _receipt(requiresAction: true),
          onTap: () {},
          onMarkSeen: () {},
          onMarkUnseen: () {},
          onSettle: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text(L10nEn().updatesMarkDone), findsOneWidget);
    expect(find.byIcon(Icons.task_alt_outlined), findsNothing);
  });

  testWidgets('unread row marks seen; seen row unsees without opening', (
    tester,
  ) async {
    var markedSeen = false;
    var markedUnseen = false;
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        UpdatesReceiptCard(
          receipt: _receipt(),
          onTap: () => tapped = true,
          onMarkSeen: () => markedSeen = true,
          onMarkUnseen: () => markedUnseen = true,
          onSettle: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10nEn().updatesMarkSeen));
    await tester.pump();
    expect(markedSeen, isTrue);
    expect(tapped, isFalse);

    await tester.pumpWidget(
      _wrap(
        UpdatesReceiptCard(
          receipt: _receipt().copyWith(seenAt: DateTime.utc(2026, 8, 4)),
          onTap: () => tapped = true,
          onMarkSeen: () {},
          onMarkUnseen: () => markedUnseen = true,
          onSettle: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsNothing);
    tapped = false;
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10nEn().updatesMarkUnseen));
    await tester.pump();
    expect(markedUnseen, isTrue);
    expect(tapped, isFalse);
  });

  group('a read row still on Unread can be cleared from its menu (#711)', () {
    Future<void> openMenu(
      WidgetTester tester,
      AttentionReceipt receipt, {
      VoidCallback? onMarkSeen,
    }) async {
      await tester.pumpWidget(
        _wrap(
          UpdatesReceiptCard(
            receipt: receipt,
            onTap: () {},
            onMarkSeen: onMarkSeen ?? () {},
            onMarkUnseen: () {},
            onSettle: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
    }

    testWidgets('a read optional row offers the clear beside Mark unread', (
      tester,
    ) async {
      var cleared = false;
      await openMenu(
        tester,
        _receipt().copyWith(seenAt: DateTime.utc(2026, 8, 4)),
        onMarkSeen: () => cleared = true,
      );

      expect(find.text(L10nEn().updatesMarkUnseen), findsOneWidget);
      await tester.tap(find.text(L10nEn().attentionEventDismiss));
      await tester.pump();
      expect(cleared, isTrue);
    });

    testWidgets('guard: a cleared row offers only Mark unread', (
      tester,
    ) async {
      await openMenu(
        tester,
        _receipt().copyWith(
          seenAt: DateTime.utc(2026, 8, 4),
          clearedAt: DateTime.utc(2026, 8, 4),
        ),
      );

      expect(find.text(L10nEn().updatesMarkUnseen), findsOneWidget);
      expect(find.text(L10nEn().attentionEventDismiss), findsNothing);
    });

    testWidgets('guard: a read obligation is not offered the clear', (
      tester,
    ) async {
      await openMenu(
        tester,
        _receipt(
          requiresAction: true,
        ).copyWith(seenAt: DateTime.utc(2026, 8, 4)),
      );

      expect(find.text(L10nEn().updatesMarkUnseen), findsOneWidget);
      expect(find.text(L10nEn().attentionEventDismiss), findsNothing);
    });
  });
}
