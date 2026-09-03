import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_app_bar.dart';
import 'package:tentura/features/updates/ui/widget/updates_receipt_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

AttentionReceipt _unreadObligation() => AttentionReceipt(
  id: 'receipt-golden',
  category: 'coordination',
  kind: 'needsMe',
  priority: 'normal',
  title: 'Asked of you',
  body: 'Garden cleanup — Bring tools',
  actionUrl: '/#/',
  createdAt: DateTime(2026, 8, 4, 14, 30),
  collapsedCount: 1,
  presentationKey: 'needs_me',
  presentationPayloadJson: '{"beaconTitle":"Garden cleanup"}',
  beaconId: 'b1',
  requiresAction: true,
);

void main() {
  testWidgets('dense unread obligation row dark compact 360', (tester) async {
    const size = Size(360, 220);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        theme: TenturaTheme.dark(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: TenturaResponsiveScope(
            child: Scaffold(
              backgroundColor: TenturaTokens.dark.bg,
              body: Align(
                alignment: Alignment.topCenter,
                child: RepaintBoundary(
                  key: const Key('row-golden'),
                  child: UpdatesReceiptCard(
                    receipt: _unreadObligation(),
                    onTap: () {},
                    onMarkSeen: () {},
                    onMarkUnseen: () {},
                    onSettle: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byKey(const Key('row-golden')),
      matchesGoldenFile('goldens/updates_dense_row_dark_compact.png'),
    );
  });

  testWidgets('360 dark RU top bar keeps command size', (tester) async {
    const size = Size(360, 800);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ru'),
        theme: TenturaTheme.dark(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: TenturaResponsiveScope(
            child: Builder(
              builder: (context) => Scaffold(
                appBar: TenturaTopBar.of(
                  context,
                  title: const SizedBox.shrink(),
                  row: UpdatesFeedAppBarRow(
                    title: L10nRu().updatesTitle,
                    markAllLabel: L10nRu().updatesMarkAllSeen,
                    hasUnread: true,
                    onMarkAll: () {},
                    showSearchIcon: true,
                    searchOpen: false,
                    onSearchPressed: () {},
                    searchTooltip: L10nRu().updatesSearchHint,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final label = tester.widget<Text>(find.text(L10nRu().updatesMarkAllSeen));
    expect(label.style?.fontSize, 15);
    await expectLater(
      find.byType(AppBar),
      matchesGoldenFile('goldens/updates_top_bar_dark_ru_360.png'),
    );
  });
}
