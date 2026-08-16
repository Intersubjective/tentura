import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

Future<void> skipReviewContributions(WidgetTester tester) async {
  await pumpUntilVisible(
    tester,
    find.byKey(TestIds.key(TestIds.evaluationSubmit)),
  );
  await tapAndSettle(tester, find.text('Skip for now').first);
}

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
  await pumpUntilVisible(tester, find.widgetWithText(FilledButton, 'Review'));
  await tapAndSettle(tester, find.widgetWithText(FilledButton, 'Review').first);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('closed request shows archive CTA and blocks delete', (
    tester,
  ) async {
    await launchApp(app.main);
    await tester.pumpAndSettle();

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
    await skipReviewContributions(tester);
    await logout(tester);

    await loginAs(tester, fixture.helperEmail);
    await openRequestFromMyWork(tester, requestTitle: title);
    await openReviewContributionsIfNeeded(tester);
    await skipReviewContributions(tester);
    await logout(tester);

    await loginAs(tester, fixture.authorEmail);
    await triggerCloseNow(tester);

    await tapAndSettle(tester, find.text('Archive').first);
    await pumpUntil(tester, () => find.text(title).evaluate().isEmpty);

    // Active becomes empty after archiving the only item, so the toolbar
    // filter menu (hidden in some layouts once the list is empty / a card
    // was selected) is not a reliable target here. The empty-state body's
    // own archived shortcut ("Archived (N)") is always rendered when
    // archivedCountHint > 0 and calls the same setFilter(archived) path.
    await tapAndSettle(tester, find.textContaining('Archived (').first);
    await pumpUntilVisible(tester, find.text(title));

    await tapAndSettle(tester, find.text(title).first);
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.beaconOverflowMenu)).first,
    );
    await tapAndSettle(tester, find.text('Delete Request').first);

    expect(find.text('Cannot delete'), findsOneWidget);
    expect(find.text('Archive'), findsWidgets);
  });
}
