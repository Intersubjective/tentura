import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/ui/sheet/beacon_close_confirm_sheet.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #474: with every check passed the close sheet reads as ready (no warning,
// no «anyway»); the final-check branch names its action one way; the sheet
// is its own semantics node.

final _en = lookupL10n(const Locale('en'));

BeaconClosureConfirmationSummary _summary({
  required BeaconClosureReadiness readiness,
  required bool requiresReviewWindow,
  Set<BeaconClosureCriterion> missingCriteria = const {},
}) => BeaconClosureConfirmationSummary(
  readiness: readiness,
  hasOpenBlocker: false,
  unansweredHelpOffersCount: 0,
  relevantHelpOffersCount: 1,
  unsettledRelevantCount: 0,
  hasWholeBeaconDoneSignal: false,
  enoughHelpOffered: !missingCriteria.contains(
    BeaconClosureCriterion.enoughHelp,
  ),
  hasSuccessfulHelpOfferResult: true,
  requiresReviewWindow: requiresReviewWindow,
  missingCriteria: missingCriteria,
);

Future<void> _openSheet(
  WidgetTester tester,
  BeaconClosureConfirmationSummary summary,
) async {
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
                  onCloseBeacon: (_) async => true,
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
}

void main() {
  testWidgets('all checks pass while waiting for review: ready, no anyway', (
    tester,
  ) async {
    await _openSheet(
      tester,
      _summary(
        readiness: BeaconClosureReadiness.waitingForReview,
        requiresReviewWindow: true,
      ),
    );

    expect(find.text(_en.beaconCloseSheetReadyReviewTitle), findsOneWidget);
    expect(
      find.text(_en.beaconCloseSheetActionStartFinalCheck),
      findsOneWidget,
    );
    expect(find.text(_en.beaconCloseSheetActionCloseAnyway), findsNothing);
    expect(find.text(_en.beaconCloseSheetReviewWrappingUpBody), findsNothing);
    expect(find.text(_en.beaconCloseSheetReviewTitle), findsNothing);
  });

  testWidgets('ready with a final check names the action Start final check', (
    tester,
  ) async {
    await _openSheet(
      tester,
      _summary(
        readiness: BeaconClosureReadiness.readyToClose,
        requiresReviewWindow: true,
      ),
    );

    expect(find.text(_en.beaconCloseSheetReadyReviewTitle), findsOneWidget);
    expect(
      find.text(_en.beaconCloseSheetActionStartFinalCheck),
      findsOneWidget,
    );
    expect(find.text(_en.beaconCloseSheetActionCloseBeacon), findsNothing);
  });

  testWidgets('ready without a final check keeps Close request', (
    tester,
  ) async {
    await _openSheet(
      tester,
      _summary(
        readiness: BeaconClosureReadiness.readyToClose,
        requiresReviewWindow: false,
      ),
    );

    expect(find.text(_en.beaconCloseSheetReadyTitle), findsOneWidget);
    expect(find.text(_en.beaconCloseSheetActionCloseBeacon), findsOneWidget);
    expect(find.text(_en.beaconCloseSheetActionCloseAnyway), findsNothing);
  });

  testWidgets('a failed check before the final check: warning and anyway', (
    tester,
  ) async {
    await _openSheet(
      tester,
      _summary(
        readiness: BeaconClosureReadiness.waitingForReview,
        requiresReviewWindow: true,
        missingCriteria: {BeaconClosureCriterion.enoughHelp},
      ),
    );

    expect(find.text(_en.beaconCloseSheetReviewWrappingUpBody), findsOneWidget);
    expect(
      find.text(_en.beaconCloseSheetEvidenceEnoughHelpMissing),
      findsOneWidget,
    );
    expect(
      find.text(_en.beaconCloseSheetActionStartFinalCheckAnyway),
      findsOneWidget,
    );
    expect(find.text(_en.beaconCloseSheetActionCloseAnyway), findsNothing);
  });

  testWidgets('a failed check with an immediate close keeps Close anyway', (
    tester,
  ) async {
    await _openSheet(
      tester,
      _summary(
        readiness: BeaconClosureReadiness.waitingForReview,
        requiresReviewWindow: false,
        missingCriteria: {BeaconClosureCriterion.enoughHelp},
      ),
    );

    expect(find.text(_en.beaconCloseSheetReviewBody), findsOneWidget);
    expect(find.text(_en.beaconCloseSheetActionCloseAnyway), findsOneWidget);
  });

  testWidgets('a backup offer on standby adds no unsettled row', (
    tester,
  ) async {
    final state = BeaconViewState(
      beacon: Beacon(
        createdAt: DateTime.utc(2025),
        updatedAt: DateTime.utc(2025),
        id: 'b1',
        title: 'T',
        author: const Profile(id: 'uAuthor', displayName: 'Author'),
        status: BeaconStatus.enoughHelp,
      ),
      helpOffers: [
        TimelineHelpOffer(
          user: const Profile(id: 'u1', displayName: 'u1'),
          message: '',
          createdAt: DateTime.utc(2025),
          updatedAt: DateTime.utc(2025),
          coordinationResponse: CoordinationResponseType.useful,
        ),
        TimelineHelpOffer(
          user: const Profile(id: 'uFay', displayName: 'Fay'),
          message: '',
          createdAt: DateTime.utc(2025),
          updatedAt: DateTime.utc(2025),
          offerKind: TimelineHelpOffer.offerKindBackup,
        ),
      ],
      myProfile: const Profile(id: 'uAuthor', displayName: 'Me'),
    );

    await _openSheet(tester, buildClosureConfirmationSummary(state));

    expect(
      find.text(_en.beaconCloseSheetEvidenceUnsettledCount(1)),
      findsNothing,
    );
    expect(find.text(_en.beaconCloseSheetActionCloseAnyway), findsNothing);
  });

  testWidgets('the sheet is a semantics node named by its title', (
    tester,
  ) async {
    await _openSheet(
      tester,
      _summary(
        readiness: BeaconClosureReadiness.readyToClose,
        requiresReviewWindow: true,
      ),
    );

    final title = _en.beaconCloseSheetReadyReviewTitle;
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            (w.properties.scopesRoute ?? false) &&
            (w.properties.namesRoute ?? false) &&
            w.properties.label == title,
      ),
      findsOneWidget,
    );
  });

  // #474 review: the route node is named by the title, so the visible title
  // must not be a second node saying it again.
  testWidgets('a screen reader hears the sheet title once', (tester) async {
    final handle = tester.ensureSemantics();
    await _openSheet(
      tester,
      _summary(
        readiness: BeaconClosureReadiness.readyToClose,
        requiresReviewWindow: true,
      ),
    );
    final title = _en.beaconCloseSheetReadyReviewTitle;
    final saying = find.semantics
        .byPredicate(
          (node) =>
              !node.isMergedIntoParent &&
              node.getSemanticsData().label.contains(title),
        )
        .evaluate()
        .toList();
    expect(saying, hasLength(1));
    final data = saying.single.getSemanticsData();
    expect(title.allMatches(data.label), hasLength(1));
    expect(data.flagsCollection.namesRoute, isTrue);
    handle.dispose();
  });
}
