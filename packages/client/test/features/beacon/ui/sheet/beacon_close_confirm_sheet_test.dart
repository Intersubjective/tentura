import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon/ui/sheet/beacon_close_confirm_sheet.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  testWidgets('shows answer-first action when unanswered offers exist', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    var openPeopleCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () async {
                      await showBeaconCloseConfirmSheet(
                        context: context,
                        summary: const BeaconClosureConfirmationSummary(
                          readiness: BeaconClosureReadiness.readyToClose,
                          hasOpenBlocker: false,
                          unansweredHelpOffersCount: 2,
                          relevantHelpOffersCount: 2,
                          unsettledRelevantCount: 0,
                          hasWholeBeaconDoneSignal: false,
                          enoughHelpOffered: false,
                          hasSuccessfulHelpOfferResult: false,
                          requiresReviewWindow: false,
                        ),
                        isLoading: false,
                        onCloseBeacon: (_) async => true,
                        onOpenPeople: () => openPeopleCalled = true,
                      );
                    },
                    child: const Text('Open sheet'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        l10n.beaconCloseSheetEvidenceUnansweredCount(2),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.beaconCloseAnswerFirst), findsOneWidget);

    await tester.tap(find.text(l10n.beaconCloseAnswerFirst));
    await tester.pumpAndSettle();

    expect(openPeopleCalled, isTrue);
    expect(find.text(l10n.beaconCloseSheetReadyTitle), findsNothing);
  });

  testWidgets('hides answer-first action when no unanswered offers', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () async {
                      await showBeaconCloseConfirmSheet(
                        context: context,
                        summary: const BeaconClosureConfirmationSummary(
                          readiness: BeaconClosureReadiness.readyToClose,
                          hasOpenBlocker: false,
                          unansweredHelpOffersCount: 0,
                          relevantHelpOffersCount: 0,
                          unsettledRelevantCount: 0,
                          hasWholeBeaconDoneSignal: false,
                          enoughHelpOffered: false,
                          hasSuccessfulHelpOfferResult: false,
                          requiresReviewWindow: false,
                        ),
                        isLoading: false,
                        onCloseBeacon: (_) async => true,
                        onOpenPeople: () {},
                      );
                    },
                    child: const Text('Open sheet'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.beaconCloseAnswerFirst), findsNothing);
  });
}
