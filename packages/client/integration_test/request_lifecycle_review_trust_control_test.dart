import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

// Covers the contribution-grounded trust UX of the post-close review
// (two-step trust control + inline save validation): Save is blocked until
// a trust category is picked, a direction pick demands an intensity, and
// pos2/neg* demand a reason tag before the sheet closes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('post-close review enforces two-step trust selection', (
    tester,
  ) async {
    await launchApp(app.main);
    await tester.pumpAndSettle();

    final fixture = await bootstrapFixture(
      runId: uniqueRunId('trust-review'),
    );
    final title = uniqueRequestTitle('IT trust control');

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

    final helperTile = find.byKey(
      TestIds.key(TestIds.evaluationParticipant(fixture.helperUserId)),
    );
    await tapAndSettle(tester, helperTile.first);
    final saveButton = find.byKey(TestIds.key(TestIds.evaluationSave));
    await pumpUntilVisible(tester, saveButton);

    // Save with no selection: category validation keeps the sheet open.
    await tapAndSettle(tester, saveButton);
    await pumpUntilVisible(
      tester,
      find.text('Choose how this contribution affected your trust.'),
    );

    // Pick "trust increased": the intensity step appears, Save still blocked.
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.evaluationTrustOption('increasePending'))),
    );
    await pumpUntilVisible(tester, find.text('How much?'));
    await tapAndSettle(tester, saveButton);
    await pumpUntilVisible(
      tester,
      find.text('Choose how much your trust changed.'),
    );

    // Pick "A lot" (pos2): the trust-impact preview shows and a reason tag
    // becomes mandatory.
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.evaluationTrustIntensityLot)),
    );
    await pumpUntilVisible(
      tester,
      find.textContaining('will increase noticeably'),
    );
    await tapAndSettle(tester, saveButton);
    await pumpUntilVisible(tester, find.text('Choose at least one reason.'));

    // Pick a reason: Save succeeds and the sheet closes.
    await tapAndSettle(
      tester,
      find.byKey(
        TestIds.key(TestIds.evaluationReasonChip('delivered_as_promised')),
      ),
    );
    await tapAndSettle(tester, saveButton);
    await pumpUntil(tester, () => saveButton.evaluate().isEmpty);

    // The participant list reflects the saved trust change ("More" status).
    await pumpUntilVisible(
      tester,
      find.descendant(of: helperTile, matching: find.text('More')),
    );

    // Finish the remaining review (zero = no intensity/reason) and submit.
    await reviewParticipant(tester, fixture.authorUserId);
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.evaluationSubmit)),
    );
  });
}
