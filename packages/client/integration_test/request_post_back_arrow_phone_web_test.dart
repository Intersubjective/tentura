import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/main.dart' as app;

import 'support/e2e_test_helpers.dart';

/// Real browser, real stack, phone viewport: the in-app back arrow on a
/// Request and on a Post opened from their lists returns to the list.
///
/// Phone width: run with BROWSER_DIMENSION=375x806 (the window size another
/// phone test in this directory documents as giving the 375x667 app
/// viewport; confirm on first run):
///   BROWSER_DIMENSION=375x806 ./scripts/run_client_integration_web_local.sh \
///     integration_test/request_post_back_arrow_phone_web_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'phone web: back arrow returns from a Request and from a Post to the list',
    (tester) async {
      await launchApp(app.main);
      await pumpSettleBounded(tester);

      final fixture = await bootstrapFixture(
        runId: uniqueRunId('back-arrow-phone'),
      );
      final requestTitle = uniqueRequestTitle('IT back arrow');
      final postBody = uniqueRequestTitle('IT back arrow post');

      await logout(tester);
      await loginAs(tester, fixture.authorEmail);
      await createPublishedBeacon(title: requestTitle);
      await createPublishedPost(
        body: postBody,
        recipientIds: [fixture.helperUserId],
      );

      await runE2eStep('Request: back arrow returns to the list', () async {
        await openRequestFromMyWork(tester, requestTitle: requestTitle);
        expect(currentAppUrl().startsWith(kPathBeaconView), isTrue);
        await tapAndSettle(tester, find.byIcon(Icons.arrow_back).last);
        await pumpUntil(
          tester,
          () => currentAppUrl() == kPathMyWork,
          timeout: const Duration(seconds: 15),
        );
        expect(currentAppUrl(), kPathMyWork);
      });

      await runE2eStep('Post: back arrow returns to the list', () async {
        await goToPath(tester, kPathConversations);
        await tapAndSettle(tester, find.text(postBody).first);
        expect(currentAppUrl().startsWith(kPathPostView), isTrue);
        await tapAndSettle(tester, find.byType(BackButton).last);
        await pumpUntil(
          tester,
          () => currentAppUrl() == kPathConversations,
          timeout: const Duration(seconds: 15),
        );
        expect(currentAppUrl(), kPathConversations);
      });
    },
  );
}
