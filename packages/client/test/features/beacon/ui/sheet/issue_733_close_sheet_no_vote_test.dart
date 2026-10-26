import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon/ui/sheet/beacon_close_confirm_sheet.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #733: with two committed helpers nobody can vote in a final check, so the
// sheet must not promise one ("helpers acknowledge contributions"): it says
// the request closes right away and why, and its button closes.

final _en = lookupL10n(const Locale('en'));

BeaconClosureConfirmationSummary _summary({
  required int committers,
  BeaconClosureReadiness readiness = BeaconClosureReadiness.readyToClose,
  Set<BeaconClosureCriterion> missing = const {},
}) => BeaconClosureConfirmationSummary(
  readiness: readiness,
  hasOpenBlocker: false,
  unansweredHelpOffersCount: 0,
  relevantHelpOffersCount: committers,
  unsettledRelevantCount: 0,
  hasWholeBeaconDoneSignal: false,
  enoughHelpOffered: !missing.contains(BeaconClosureCriterion.enoughHelp),
  hasSuccessfulHelpOfferResult: true,
  requiresReviewWindow: true,
  missingCriteria: missing,
  committedHelperCount: committers,
);

Future<List<bool>> _open(
  WidgetTester tester,
  BeaconClosureConfirmationSummary summary,
) async {
  final calls = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showBeaconCloseConfirmSheet(
                  context: context,
                  summary: summary,
                  isLoading: false,
                  onCloseBeacon: (expected) async {
                    calls.add(expected);
                    return true;
                  },
                  onOpenPeople: () {},
                ),
                child: const Text('Open sheet'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open sheet'));
  await tester.pumpAndSettle();
  return calls;
}

bool _anyTextContains(String needle) => find
    .byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.data ?? '').toLowerCase().contains(needle.toLowerCase()),
    )
    .evaluate()
    .isNotEmpty;

void main() {
  testWidgets('two helpers: explains it closes right away, no acknowledge '
      'promise, the button closes', (tester) async {
    final calls = await _open(tester, _summary(committers: 2));

    expect(find.text(_en.beaconCloseSheetNoVoteBody), findsOneWidget);
    expect(
      find.text(_en.beaconCloseSheetBranchClosedImmediate),
      findsOneWidget,
    );
    expect(_anyTextContains('acknowledge'), isFalse);
    expect(find.text(_en.beaconCloseSheetActionStartFinalCheck), findsNothing);

    await tester.tap(find.text(_en.beaconCloseSheetActionCloseBeacon));
    await tester.pumpAndSettle();
    expect(calls, [false]);
  });

  testWidgets('two helpers, a check still missing: the reason is shown too', (
    tester,
  ) async {
    await _open(
      tester,
      _summary(
        committers: 2,
        readiness: BeaconClosureReadiness.waitingForReview,
        missing: const {BeaconClosureCriterion.enoughHelp},
      ),
    );
    expect(find.text(_en.beaconCloseSheetNoVoteBody), findsOneWidget);
    expect(_anyTextContains('acknowledge'), isFalse);
    expect(find.text(_en.beaconCloseSheetActionCloseAnyway), findsOneWidget);
  });

  testWidgets('three helpers keep the final check (guard)', (tester) async {
    await _open(tester, _summary(committers: 3));
    expect(find.text(_en.beaconCloseSheetReadyReviewTitle), findsOneWidget);
    expect(
      find.text(_en.beaconCloseSheetActionStartFinalCheck),
      findsOneWidget,
    );
    expect(find.text(_en.beaconCloseSheetNoVoteBody), findsNothing);
  });

  testWidgets('an accepted offer is listed as such, not as a done result', (
    tester,
  ) async {
    await _open(tester, _summary(committers: 3));
    expect(find.text('An offer was accepted'), findsOneWidget);
    expect(find.text('Useful or done result present'), findsNothing);
  });
}
