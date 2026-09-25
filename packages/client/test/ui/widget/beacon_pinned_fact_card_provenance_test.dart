import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_provenance_line.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Widget _harness(BeaconFactCard fact) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: const Locale('en'),
  home: TenturaResponsiveScope(
    child: Scaffold(
      body: Builder(
        builder: (context) =>
            BeaconPinnedFactCard(fact: fact, l10n: L10n.of(context)!),
      ),
    ),
  ),
);

void main() {
  testWidgets('never-edited card shows the full provenance line', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        BeaconFactCard(
          id: 'f1',
          beaconId: 'b1',
          factText: 'Gate code is 4821',
          visibility: BeaconFactCardVisibilityBits.public,
          pinnedBy: 'Uanna',
          pinnedByTitle: 'Anna',
          createdAt: DateTime.now().subtract(const Duration(days: 3)),
          status: BeaconFactCardStatusBits.active,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final line = find.byType(FactProvenanceLine);
    expect(line, findsOneWidget);
    expect(tester.widget<FactProvenanceLine>(line).compact, isFalse);
    expect(
      find.descendant(of: line, matching: find.textContaining('Anna')),
      findsOneWidget,
    );
  });

  testWidgets('corrected card: provenance line replaces the "Edited" badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        BeaconFactCard(
          id: 'f1',
          beaconId: 'b1',
          factText: 'Gate code is 4822',
          visibility: BeaconFactCardVisibilityBits.public,
          pinnedBy: 'Uanna',
          pinnedByTitle: 'Anna',
          createdAt: DateTime.now().subtract(const Duration(days: 3)),
          status: BeaconFactCardStatusBits.corrected,
          revisionSeq: 2,
          lastEditedBy: 'Uboris',
          lastEditedByTitle: 'Boris',
          lastEditedAt: DateTime.now().subtract(const Duration(hours: 2)),
          otherEditorCount: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconRoomFactCardCorrectedBadge), findsNothing);
    expect(
      find.descendant(
        of: find.byType(FactProvenanceLine),
        matching: find.textContaining('Boris'),
      ),
      findsOneWidget,
    );
  });
}
