import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('close request and complete contribution review', (
    tester,
  ) async {
    await launchApp(app.main);
    await pumpSettleBounded(tester);

    final fixture = await bootstrapFixture(
      runId: uniqueRunId('close-review'),
    );
    final title = uniqueRequestTitle('IT close review');

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
    await reviewParticipant(tester, fixture.helperUserId);
    await sendCompleteReviewPackage(tester);

    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.evaluationDone)),
      timeout: const Duration(seconds: 45),
    );
    expect(find.textContaining('Reviews sent'), findsOneWidget);
    expect(find.byKey(TestIds.key(TestIds.evaluationSubmit)), findsNothing);

    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.evaluationDone)),
    );
    expect(
      find.byKey(TestIds.key(TestIds.beaconHudAuthorAction('reviewContributions'))),
      findsNothing,
    );

    await goToPath(tester, kPathMyWork);
    await showMyWorkList(tester);
    await pumpUntilVisible(tester, find.text(title));
    await pumpUntil(
      tester,
      () => finderHasMatch(find.text('Your reviews are sent')),
      timeout: const Duration(seconds: 45),
      label: 'My Work sent status',
    );
    expect(
      find.widgetWithText(TenturaCommandButton, 'Review contributions'),
      findsNothing,
    );
    expect(find.widgetWithText(TextButton, 'Edit'), findsWidgets);

    await tapAndSettle(tester, find.widgetWithText(TextButton, 'Edit').first);
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.evaluationDone)),
      timeout: const Duration(seconds: 45),
    );
    expect(find.textContaining('Reviews sent'), findsOneWidget);
    expect(find.byKey(TestIds.key(TestIds.evaluationSubmit)), findsNothing);

    await reviewParticipant(
      tester,
      fixture.helperUserId,
      impact: 'neg1',
    );
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.evaluationSubmit)),
    );
    expect(find.text('Changes not sent'), findsOneWidget);
    expect(find.text('Send changes'), findsOneWidget);

    final back = find.byType(BackButton);
    if (finderHasMatch(back)) {
      await tapAndSettle(tester, back.first);
    } else {
      await tapAndSettle(tester, find.byIcon(Icons.arrow_back).first);
    }
    await goToPath(tester, kPathMyWork);
    await showMyWorkList(tester);
    await pumpUntilVisible(tester, find.text(title));
    await pumpUntil(
      tester,
      () => finderHasMatch(find.text('Send changes')),
      timeout: const Duration(seconds: 45),
      label: 'My Work unsent changes',
    );
    expect(find.text('Your reviews are sent'), findsNothing);
  });
}
