import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/main.dart' as app;
import 'support/e2e_test_helpers.dart';

/// Covers the contribution-impact sheet in the closed-request workflow.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('post-close review uses direct impact choices', (tester) async {
    await launchApp(app.main);
    await tester.pumpAndSettle();
    final fixture = await bootstrapFixture(
      runId: uniqueRunId('impact-review'),
    );
    final title = uniqueRequestTitle('impact review');
    await logout(tester);
    await createAndForwardRequest(tester, fixture: fixture, title: title);
    await logout(tester);
    await offerHelpFromInbox(tester, fixture: fixture, requestTitle: title);
    await logout(tester);
    await acceptHelpOffer(tester, fixture: fixture, requestTitle: title);
    await closeRequestAndOpenReview(tester);

    await reviewParticipant(tester, fixture.helperUserId, impact: 'zero');
  });
}
