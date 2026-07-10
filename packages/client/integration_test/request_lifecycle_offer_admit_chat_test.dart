import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offer help, admit helper, chat, and manage items', (
    tester,
  ) async {
    await launchApp(app.main);
    await tester.pumpAndSettle();

    final fixture = await bootstrapFixture(
      runId: uniqueRunId('offer-admit'),
    );
    final title = uniqueRequestTitle('IT offer admit');

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

    await logout(tester);
    await loginAs(tester, fixture.helperEmail);
    await openRequestFromInbox(tester, requestTitle: title);
    await sendRoomMessage(tester, 'Integration test room message');

    await createCoordinationItem(
      tester,
      launcherId: TestIds.coordinationAskCreate,
      title: 'Need answer',
      body: 'Please confirm the plan',
    );
    await createCoordinationItem(
      tester,
      launcherId: TestIds.coordinationPromiseCreate,
      title: 'I can help',
      body: 'I will take this tomorrow',
    );
    await createCoordinationItem(
      tester,
      launcherId: TestIds.coordinationBlockerCreate,
      title: 'Blocked on input',
      body: 'Need one missing detail',
    );
    await resolveFirstCoordinationItem(tester);

    await logout(tester);
    await loginAs(tester, fixture.authorEmail);
    await openRequestFromMyWork(tester, requestTitle: title);
    final peopleTab = find.textContaining('People');
    if (peopleTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, peopleTab.first);
    }
    await removeHelperFromChat(tester, fixture: fixture);
  });
}
