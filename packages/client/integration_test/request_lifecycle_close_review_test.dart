import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('close request and complete contribution review', (
    tester,
  ) async {
    await launchApp(app.main);
    await tester.pumpAndSettle();

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
    await reviewParticipant(tester, fixture.authorUserId);
    await reviewParticipant(tester, fixture.helperUserId);
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.evaluationSubmit)),
    );
  });
}
