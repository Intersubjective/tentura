import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/main.dart' as app;

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create, publish, forward, and reach inbox', (tester) async {
    await launchApp(app.main);
    await tester.pumpAndSettle();

    final fixture = await bootstrapFixture(
      runId: uniqueRunId('create-forward'),
    );
    final title = uniqueRequestTitle('IT create forward');

    await logout(tester);
    await createAndForwardRequest(
      tester,
      fixture: fixture,
      title: title,
    );

    await logout(tester);
    await loginAs(tester, fixture.helperEmail);
    await openRequestFromInbox(tester, requestTitle: title);

    expect(find.text(title), findsWidgets);
  });
}
