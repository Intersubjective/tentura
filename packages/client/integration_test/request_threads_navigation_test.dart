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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('request threads navigation and deep links', (tester) async {
    await launchApp(app.main);
    await tester.pumpAndSettle();

    final fixture = await bootstrapFixture(
      runId: uniqueRunId('request-threads-nav'),
    );
    final title = uniqueRequestTitle('IT threads nav');

    await logout(tester);
    await createAndForwardRequest(
      tester,
      fixture: fixture,
      title: title,
    );

    await logout(tester);
    await acceptHelpOffer(
      tester,
      fixture: fixture,
      requestTitle: title,
    );

    await logout(tester);
    await loginAs(tester, fixture.helperEmail);
    await openRequestFromMyWork(tester, requestTitle: title);
    final beaconId = _beaconIdFromUrl(currentAppUrl());

    final thread = await createCoordinationItem(
      tester,
      launcherId: TestIds.coordinationBlockerCreate,
      title: 'Nav blocker',
      body: 'Blocker thread for navigation test',
    );
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.requestThread(thread.threadId))),
    );
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.roomMessageInput)),
    );
    final message = await sendRoomMessage(
      tester,
      'Semantic thread navigation message',
    );

    await goToPath(
      tester,
      '$kPathBeaconView/$beaconId/thread/${RequestThread.generalId}',
    );
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.roomMessageInput)),
    );

    await goToPath(
      tester,
      '$kPathBeaconView/$beaconId?tab=threads&message=${message.id}',
    );
    await pumpUntil(
      tester,
      () {
        final url = currentAppUrl();
        return url.contains('thread=${thread.threadId}') &&
            !url.contains('thread=${RequestThread.generalId}');
      },
      timeout: const Duration(seconds: 30),
    );

    final otherThread = await createCoordinationItem(
      tester,
      launcherId: TestIds.coordinationBlockerCreate,
      title: 'Second blocker',
      body: 'Switch target thread',
    );
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.requestThread(otherThread.threadId))),
    );
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.roomMessageInput)),
    );
    expect(currentAppUrl(), contains(otherThread.threadId));

    await tapAndSettle(tester, find.byType(BackButton).first);
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.requestThread(otherThread.threadId))),
    );

    final beforeHistory = currentAppUrl();
    web.window.history.back();
    await pumpUntil(
      tester,
      () => currentAppUrl() != beforeHistory,
      timeout: const Duration(seconds: 15),
    );
    web.window.history.forward();
    await pumpUntil(
      tester,
      () => currentAppUrl() == beforeHistory,
      timeout: const Duration(seconds: 15),
    );

    await goToPath(tester, kPathMyWork);
    await tapAndSettle(tester, find.text(title).first);
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.requestThread(thread.threadId))),
    );
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.requestThread(thread.threadId))),
    );
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.roomMessageInput)),
    );
  });
}
