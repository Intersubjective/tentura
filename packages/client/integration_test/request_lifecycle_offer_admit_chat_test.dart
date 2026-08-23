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
    // After offering help the request moves from Inbox to the helper's
    // My Work (involved) list.
    await openRequestFromMyWork(tester, requestTitle: title);

    final ask = await runE2eStep(
      'create ask',
      () => createCoordinationItem(
        tester,
        launcherId: TestIds.coordinationAskCreate,
        title: 'Need answer',
        body: 'Please confirm the plan',
      ),
    );
    await runE2eStep(
      'create promise',
      () => createCoordinationItem(
        tester,
        launcherId: TestIds.coordinationPromiseCreate,
        title: 'I can help',
        body: 'I will take this tomorrow',
      ),
    );
    await runE2eStep(
      'create blocker',
      () => createCoordinationItem(
        tester,
        launcherId: TestIds.coordinationBlockerCreate,
        title: 'Blocked on input',
        body: 'Need one missing detail',
      ),
    );
    await runE2eStep(
      'resolve ask',
      () => resolveCoordinationItem(tester, title: ask.item!.title),
    );

    await runE2eStep(
      'send room message',
      () => sendRoomMessage(tester, 'Integration test room message'),
    );

    await runE2eStep('log out helper', () => logout(tester));
    await runE2eStep(
      'log in author',
      () => loginAs(tester, fixture.authorEmail),
    );
    await runE2eStep(
      'open author request from My Work',
      () => openRequestFromMyWork(tester, requestTitle: title),
    );
    final peopleTab = find.textContaining('People');
    if (peopleTab.evaluate().isNotEmpty) {
      await tapAndSettle(tester, peopleTab.first);
    }
    await runE2eStep(
      'end helper participation',
      () => endHelperParticipation(tester, fixture: fixture),
    );
  });
}
