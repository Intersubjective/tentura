import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';
import 'package:web/web.dart' as web;

import 'support/e2e_test_helpers.dart';

String _beaconIdFromUrl(String url) {
  final match = RegExp(r'/beacon/view/([^/?]+)').firstMatch(url);
  if (match == null) {
    throw StateError('beacon id not found in url: $url');
  }
  return match.group(1)!;
}

bool _urlHasThreadQuery(String url, String threadId) =>
    url.contains('thread=$threadId');

Future<void> _backToMyWork(WidgetTester tester) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    if (currentAppUrl() == kPathMyWork) {
      return;
    }

    // AutoLeadingWithFallback uses AutoLeadingButton (BackButton) when the
    // stack can pop, otherwise an IconButton with Icons.arrow_back (e.g. after
    // browser history.back() desyncs the AutoRoute stack from the URL).
    final back = find.byType(BackButton);
    final arrowBack = find.byIcon(Icons.arrow_back);
    if (back.evaluate().isNotEmpty) {
      await tapAndSettle(tester, back.first);
    } else if (arrowBack.evaluate().isNotEmpty) {
      await tapAndSettle(tester, arrowBack.first);
    } else {
      // Last resort: same destination as onFallback / fallbackPath.
      await goToPath(tester, kPathMyWork);
      return;
    }
  }

  if (currentAppUrl() != kPathMyWork) {
    throw StateError(
      'AppBar Back did not return to My Work after 3 attempts '
      '(url=${currentAppUrl()})',
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('request CHAT surface and deep-link routing', (tester) async {
    await launchApp(app.main);
    await tester.pump(const Duration(seconds: 2));

    final fixture = await bootstrapFixture(
      runId: uniqueRunId('request-threads-nav'),
    );
    final title = uniqueRequestTitle('IT threads nav');

    await logout(tester);
    await runE2eStep(
      'publish parent',
      () => createAndForwardRequest(
        tester,
        fixture: fixture,
        title: title,
      ),
    );

    await logout(tester);
    await runE2eStep(
      'helper offers help',
      () => offerHelpFromInbox(
        tester,
        fixture: fixture,
        requestTitle: title,
      ),
    );

    await logout(tester);
    await loginAs(tester, fixture.authorEmail);
    await runE2eStep(
      'open Request detail from My Work',
      () => openRequestFromMyWork(tester, requestTitle: title),
    );
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.beaconTabPeople)),
    );
    final accept = find.byKey(
      TestIds.key(TestIds.helpOfferAccept(fixture.helperUserId)),
    );
    final remove = find.byKey(
      TestIds.key(TestIds.helpOfferRemove(fixture.helperUserId)),
    );
    if (accept.evaluate().isEmpty && remove.evaluate().isEmpty) {
      await tapAndSettle(tester, find.textContaining('Willing to help').first);
    }
    await pumpUntil(
      tester,
      () => accept.evaluate().isNotEmpty || remove.evaluate().isNotEmpty,
    );
    if (accept.evaluate().isNotEmpty) {
      await tapAndSettle(tester, accept);
    }

    await logout(tester);
    await loginAs(tester, fixture.helperEmail);
    await runE2eStep(
      'open Request detail from My Work',
      () => openRequestFromMyWork(tester, requestTitle: title),
    );
    final beaconId = _beaconIdFromUrl(currentAppUrl());

    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.beaconTabRoom)),
    );
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.roomMessageInput)),
    );

    final message = await sendRoomMessage(
      tester,
      'Semantic thread navigation message',
    );

    await goToDeepLink(
      tester,
      '$kPathBeaconView/$beaconId/thread/${RequestThread.generalId}',
    );
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.roomMessageInput)),
    );
    expect(
      _urlHasThreadQuery(currentAppUrl(), RequestThread.generalId),
      isTrue,
    );

    await goToDeepLink(
      tester,
      '$kPathBeaconView/$beaconId?tab=threads&message=${message.id}',
    );
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.roomMessageInput)),
    );
    expect(
      _urlHasThreadQuery(currentAppUrl(), RequestThread.generalId),
      isTrue,
    );

    final chatUrl = currentAppUrl();
    web.window.history.back();
    await pumpUntil(
      tester,
      () => currentAppUrl() != chatUrl,
      timeout: const Duration(seconds: 15),
    );

    await _backToMyWork(tester);
    expect(currentAppUrl(), kPathMyWork);

    await runE2eStep(
      'open Request detail from My Work',
      () => openRequestFromMyWork(tester, requestTitle: title),
    );
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.beaconTabRoom)),
    );
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.roomMessageInput)),
    );
  });
}
