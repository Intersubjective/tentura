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

bool _urlShowsThread(String url, String threadId) =>
    url.contains('/thread/$threadId') || url.contains('thread=$threadId');

bool _urlShowsGeneral(String url) =>
    url.contains('/thread/${RequestThread.generalId}') ||
    url.contains('thread=${RequestThread.generalId}');

Future<void> _popToThreadsList(WidgetTester tester) async {
  final askCreate = find.byKey(TestIds.key(TestIds.coordinationAskCreate));
  final back = find.byType(BackButton);
  // Right after a URL-driven thread resolution, ThreadDetailScreen can
  // still be mid-selection for a frame or two — it renders a bare
  // Scaffold (no AppBar/BackButton) while `switching` or `_selectedThread`
  // settles. Wait for a stable state (either target) before deciding.
  await pumpUntil(
    tester,
    () => back.evaluate().isNotEmpty || askCreate.evaluate().isNotEmpty,
    timeout: const Duration(seconds: 30),
  );
  if (back.evaluate().isEmpty) {
    return;
  }
  await tester.tap(back.first);
  await pumpUntil(
    tester,
    () => askCreate.evaluate().isNotEmpty,
    timeout: const Duration(seconds: 30),
  );
}

/// Return through the compact AppBar hierarchy just as a user does.
///
/// `navigatePath(kPathMyWork)` cannot replace an already-mounted Home tab
/// branch from this nested route. The AppBar's own fallback is the supported
/// transition, and the bounded loop also makes any intermediate detail route
/// explicit in the browser proof.
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

  testWidgets('request threads navigation and deep links', (tester) async {
    await launchApp(app.main);
    // On web, setSurfaceSize only changes the test render surface; the app's
    // MediaQuery remains the WebDriver browser viewport. Mixing those sizes
    // creates impossible layouts (for example, an expanded navigation rail
    // inside a 390 px render surface), so this browser journey must use the
    // real viewport configured by `flutter drive --browser-dimension`.
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
      find.byKey(TestIds.key(TestIds.beaconTabThreads)),
    );

    final thread = await createCoordinationItem(
      tester,
      launcherId: TestIds.coordinationBlockerCreate,
      title: 'Nav blocker',
      body: 'Blocker thread for navigation test',
    );
    final otherThread = await createCoordinationItem(
      tester,
      launcherId: TestIds.coordinationBlockerCreate,
      title: 'Second blocker',
      body: 'Switch target thread',
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
        return _urlShowsThread(url, thread.threadId) && !_urlShowsGeneral(url);
      },
      timeout: const Duration(seconds: 30),
    );

    await _popToThreadsList(tester);
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.requestThread(otherThread.threadId))),
    );
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.roomMessageInput)),
    );
    expect(_urlShowsThread(currentAppUrl(), otherThread.threadId), isTrue);

    await _popToThreadsList(tester);
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.requestThread(otherThread.threadId))),
    );

    final threadsListUrl = currentAppUrl();
    web.window.history.back();
    await pumpUntil(
      tester,
      () {
        final url = currentAppUrl();
        return url != threadsListUrl &&
            _urlShowsThread(url, otherThread.threadId);
      },
      timeout: const Duration(seconds: 15),
    );
    final threadDetailUrl = currentAppUrl();
    web.window.history.forward();
    await pumpUntil(
      tester,
      () {
        final url = currentAppUrl();
        return url != threadDetailUrl &&
            !_urlShowsThread(url, otherThread.threadId) &&
            find
                .byKey(TestIds.key(TestIds.requestThread(otherThread.threadId)))
                .evaluate()
                .isNotEmpty;
      },
      timeout: const Duration(seconds: 15),
    );

    await _backToMyWork(tester);
    expect(currentAppUrl(), kPathMyWork);
    await openRequestFromMyWork(tester, requestTitle: title);
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.beaconTabThreads)),
    );
    // Reacquire the exact persisted item after compact route re-entry. The
    // stable row key is the navigation contract.
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.requestThread(thread.threadId))),
    );
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.requestThread(thread.threadId))),
    );
    await pumpUntil(
      tester,
      () => _urlShowsThread(currentAppUrl(), thread.threadId),
      timeout: const Duration(seconds: 15),
    );
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.roomMessageInput)),
    );
    expect(_urlShowsThread(currentAppUrl(), thread.threadId), isTrue);
  });
}
