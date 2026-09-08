import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';
import 'package:web/web.dart' as web;

import 'support/e2e_test_helpers.dart';

/// T7 web leg (plan §4.6 / decision D4): browser Back leaves the request
/// rather than stepping through surfaces.
///
/// Lives in its own file because every integration test in this repo boots the
/// app once per file; a second `launchApp` in the same file re-runs
/// `configureDependencies` and throws "Type Logger is already registered
/// inside GetIt".
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'T7 web: browser back after PEOPLE tab switch reaches My Desk in one press',
    (tester) async {
      await launchApp(app.main);
      await tester.pump(const Duration(seconds: 2));

      final fixture = await bootstrapFixture(
        runId: uniqueRunId('request-threads-web-back'),
      );
      final title = uniqueRequestTitle('IT web back');

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
      await loginAs(tester, fixture.authorEmail);
      await openRequestFromMyWork(tester, requestTitle: title);
      await tapAndSettle(
        tester,
        find.byKey(TestIds.key(TestIds.beaconTabPeople)),
      );

      final onRequestUrl = currentAppUrl();
      expect(onRequestUrl.startsWith(kPathBeaconView), isTrue);

      web.window.history.back();
      await pumpUntil(
        tester,
        () => currentAppUrl() == kPathMyWork,
        timeout: const Duration(seconds: 15),
      );

      expect(currentAppUrl(), kPathMyWork);
      expect(currentAppUrl(), isNot(onRequestUrl));
    },
  );
}
