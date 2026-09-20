import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

Future<void> openReviewContributionsIfNeeded(WidgetTester tester) async {
  if (await tryPumpUntilVisible(
    tester,
    find.byKey(TestIds.key(TestIds.evaluationSubmit)),
    timeout: const Duration(seconds: 2),
  )) {
    return;
  }
  final reviewHud = find.byKey(
    TestIds.key(TestIds.beaconHudAuthorAction('reviewContributions')),
  );
  if (await tryPumpUntilVisible(tester, reviewHud)) {
    await tapAndSettle(tester, reviewHud);
    return;
  }
  // The CTA is labelled «Review contributions» / «Submit changes», never the
  // bare 'Review' this used to match, so it goes through the stable id.
  final reviewOpen = find.byKey(TestIds.key(TestIds.reviewOpen));
  await pumpUntilVisible(tester, reviewOpen);
  await tapAndSettle(tester, reviewOpen.first);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('closed request shows archive CTA and blocks delete', (
    tester,
  ) async {
    await launchApp(app.main);
    await pumpSettleBounded(tester);

    final fixture = await bootstrapFixture(
      runId: uniqueRunId('closed-archive'),
    );
    final title = uniqueRequestTitle('IT closed archive');

    await logout(tester);
    await createAndForwardRequest(
      tester,
      fixture: fixture,
      title: title,
    );

    await logout(tester);
    await offerHelpFromInbox(
      tester,
      fixture: fixture,
      requestTitle: title,
    );

    await logout(tester);
    await acceptHelpOffer(
      tester,
      fixture: fixture,
      requestTitle: title,
    );

    await closeRequestAndOpenReview(tester);
    await runE2eStep('author send review package', () async {
      await sendCompleteReviewPackage(tester);
    });
    await logout(tester);

    await loginAs(tester, fixture.helperEmail);
    await runE2eStep('helper open request from My Work', () async {
      await openRequestFromMyWork(tester, requestTitle: title);
    });
    await runE2eStep('helper open review contributions', () async {
      await openReviewContributionsIfNeeded(tester);
    });
    await runE2eStep('helper send review package', () async {
      await sendCompleteReviewPackage(tester);
    });
    await logout(tester);

    await loginAs(tester, fixture.authorEmail);
    await runE2eStep('author reclaim My Work desk', () async {
      await showMyWorkList(tester);
    });
    await runE2eStep('trigger close / await finished archive', () async {
      await triggerCloseNow(tester);
    });

    await runE2eStep('archive finished card', () async {
      final archive = find.widgetWithText(TextButton, 'Archive');
      await pumpUntilVisible(
        tester,
        archive,
        timeout: const Duration(seconds: 30),
        label: 'finished Archive CTA',
      );
      await tapAndSettle(tester, archive.first);
      await pumpUntil(
        tester,
        () => find.text(title).evaluate().isEmpty,
        label: 'archived card left active list',
      );
    });

    // Active becomes empty after archiving the only item, so the toolbar
    // filter menu (hidden in some layouts once the list is empty / a card
    // was selected) is not a reliable target here. The empty-state body's
    // own archived shortcut ("Archived (N)") is always rendered when
    // archivedCountHint > 0 and calls the same setFilter(archived) path.
    await tapAndSettle(tester, find.textContaining('Archived (').first);
    await pumpUntilVisible(tester, find.text(title));

    await tapAndSettle(tester, find.text(title).first);
    // Delete is on the management overflow (`inRoomSurface: false`). In the
    // wide split layout that lives on the content pane (first overflow key);
    // on narrow layouts switch to Now so Chat's room-only overflow is not
    // the sole menu.
    final nowTab = find.byKey(TestIds.key(TestIds.beaconTabNow));
    if (finderHasMatch(nowTab)) {
      await tapAndSettle(tester, nowTab);
    }
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.beaconOverflowMenu)).first,
    );
    final deleteItem = find.text('Delete Request');
    await pumpUntilVisible(
      tester,
      deleteItem,
      label: 'Delete Request overflow',
    );
    await tapAndSettle(tester, deleteItem.first);

    expect(find.text('Cannot delete'), findsOneWidget);
    expect(find.text('Archive'), findsWidgets);
  });
}
