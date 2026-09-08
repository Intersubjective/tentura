import 'dart:async';
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

    final back = find.byType(BackButton);
    if (back.evaluate().isEmpty) {
      throw StateError(
        'AppBar Back unavailable while returning to My Work '
        '(url=${currentAppUrl()})',
      );
    }
    await tapAndSettle(tester, back.first);
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
    await openRequestFromMyWork(tester, requestTitle: title);
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

    await goToPath(
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

    await goToPath(
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

    await openRequestFromMyWork(tester, requestTitle: title);
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
