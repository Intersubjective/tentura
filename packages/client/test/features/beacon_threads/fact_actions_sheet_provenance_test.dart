import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_provenance_line.dart';
import 'package:tentura/ui/l10n/l10n.dart';

BeaconFactCard _fact({int revisionSeq = 1}) => BeaconFactCard(
  id: 'f1',
  beaconId: 'b1',
  factText: 'Gate code is 4821',
  visibility: BeaconFactCardVisibilityBits.public,
  pinnedBy: 'Uanna',
  pinnedByTitle: 'Anna',
  createdAt: DateTime.now().subtract(const Duration(days: 3)),
  status: revisionSeq > 1
      ? BeaconFactCardStatusBits.corrected
      : BeaconFactCardStatusBits.active,
  revisionSeq: revisionSeq,
  lastEditedBy: revisionSeq > 1 ? 'Uanna' : null,
  lastEditedByTitle: revisionSeq > 1 ? 'Anna' : '',
  lastEditedAt: revisionSeq > 1
      ? DateTime.now().subtract(const Duration(hours: 2))
      : null,
);

Future<void> _openSheet(
  WidgetTester tester, {
  required BeaconFactCard fact,
  bool canMutate = false,
  void Function(BeaconFactCard fact)? onEditHistory,
  void Function(BeaconFactCard fact)? onQuoteInChat,
}) async {
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showFactActionsHostSheet(
                ctx,
                fact: fact,
                canMutate: canMutate,
                onCorrect: ({required factCardId, required newText}) async {},
                onRemove: ({required factCardId}) async {},
                onSetVisibility: ({required factCardId, required visibility}) async {},
                onEditHistory: onEditHistory ?? (_) {},
                onQuoteInChat: onQuoteInChat ?? (_) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('header shows the full provenance line naming the pinner', (
    tester,
  ) async {
    await _openSheet(tester, fact: _fact());

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconRoomFactManageSheetTitle), findsOneWidget);
    final line = find.byType(FactProvenanceLine);
    expect(line, findsOneWidget);
    // Header is the detail surface: full variant, pin time included.
    expect(tester.widget<FactProvenanceLine>(line).compact, isFalse);
    expect(
      find.descendant(of: line, matching: find.textContaining('Anna')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: line, matching: find.textContaining('3d')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Edit history" is hidden at revisionSeq 1', (tester) async {
    await _openSheet(tester, fact: _fact());

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(
      find.text(l10n.beaconRoomFactCardActionEditHistory),
      findsNothing,
    );
  });

  testWidgets('"Edit history" is hidden at revisionSeq 1 for a mutator too', (
    tester,
  ) async {
    await _openSheet(tester, fact: _fact(), canMutate: true);

    final l10n = await L10n.delegate.load(const Locale('en'));
    // Mutator sheet is open (Edit action visible) yet no history item.
    expect(find.text(l10n.beaconRoomFactCardActionEdit), findsOneWidget);
    expect(
      find.text(l10n.beaconRoomFactCardActionEditHistory),
      findsNothing,
    );
  });

  testWidgets('"Edit history" is shown at revisionSeq 2 for a mutator', (
    tester,
  ) async {
    await _openSheet(tester, fact: _fact(revisionSeq: 2), canMutate: true);

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(
      find.text(l10n.beaconRoomFactCardActionEditHistory),
      findsOneWidget,
    );
  });

  testWidgets(
    '"Edit history" is shown at revisionSeq 2 to a non-mutating reader',
    (tester) async {
      BeaconFactCard? opened;
      await _openSheet(
        tester,
        fact: _fact(revisionSeq: 2),
        onEditHistory: (f) => opened = f,
      );

      final l10n = await L10n.delegate.load(const Locale('en'));
      final editHistory = l10n.beaconRoomFactCardActionEditHistory;
      // Reader: no mutate actions.
      expect(find.text(l10n.beaconRoomFactCardActionEdit), findsNothing);
      expect(find.text(editHistory), findsOneWidget);

      await tester.tap(find.text(editHistory));
      await tester.pumpAndSettle();
      expect(opened?.id, 'f1');
      expect(find.text(editHistory), findsNothing);
    },
  );

  testWidgets('"Quote in chat" is present and invokes its callback', (
    tester,
  ) async {
    BeaconFactCard? quoted;
    await _openSheet(
      tester,
      fact: _fact(),
      onQuoteInChat: (f) => quoted = f,
    );

    final l10n = await L10n.delegate.load(const Locale('en'));
    final quote = l10n.beaconRoomFactCardActionQuoteInChat;
    expect(find.text(quote), findsOneWidget);

    await tester.tap(find.text(quote));
    await tester.pumpAndSettle();
    expect(quoted?.id, 'f1');
    expect(find.text(quote), findsNothing);
  });
}
