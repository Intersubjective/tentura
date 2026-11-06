// Two sessions of the same forwarded, unseated reader. Opening a Request in A
// clears B's Field unread marker through the private realtime invalidation.
// Run with REALTIME_MULTICLIENT_ACTOR_ECHO_ENABLED=false (also in local .env)
// and REALTIME_MULTICLIENT_DRIVER=field_open_unread_multiclient_web_test.dart.
import 'dart:convert';
import 'dart:io';

import 'multiclient_webdriver_support.dart';

Future<void> main() async {
  final qaToken = Platform.environment['QA_AUTH_TOKEN']?.trim() ?? '';
  if (qaToken.isEmpty) {
    throw StateError('QA_AUTH_TOKEN is required');
  }
  final runId =
      Platform.environment['REALTIME_MULTICLIENT_RUN_ID'] ??
      'field-open-${DateTime.now().microsecondsSinceEpoch}';
  final artifactDir = Directory(
    Platform.environment['REALTIME_MULTICLIENT_ARTIFACT_DIR'] ??
        'field-open-artifacts/$runId',
  )..createSync(recursive: true);
  final timings = <String, int>{};
  final sessions = <BrowserSession>[];

  try {
    final fixture = await bootstrapFixture(qaToken, runId);
    final title = 'Field unread request $runId';
    final beaconId = await createBeaconViaApi(
      authorEmail: fixture.authorEmail,
      title: title,
    );
    await forwardBeaconViaApi(
      authorEmail: fixture.authorEmail,
      beaconId: beaconId,
      recipientId: fixture.helperUserId,
    );
    // Forwarding grants content access without offering help or seating the
    // reader. Neither session opens the discussion in this journey.
    final a = await BrowserSession.start('reader-a', artifactDir);
    sessions.add(a);
    final b = await BrowserSession.start('reader-b', artifactDir);
    sessions.add(b);
    await Future.wait([
      a.login(fixture.helperEmail),
      b.login(fixture.helperEmail),
    ]);
    await b.open('/home/constellation');
    await b.clickTestId('constellation.app_bar.view_mode.text');
    final rowId = 'constellation.text.request.$beaconId';
    await b.waitForTestId(rowId);
    final unreadLabel = '$title, unread';
    await b.waitForTestIdText(rowId, unreadLabel);

    final marker = 'field-open-$runId';
    await b.driver.execute('window.__tenturaFieldOpenMarker = arguments[0];', [
      marker,
    ]);
    final urlBefore = await b.driver.currentUrl;

    await a.open('/beacon/view/$beaconId');
    // Unseated readers see the discovery screen, which has no People tab.
    await a.waitForText(title);
    timings['reader_b_unread_cleared_ms'] = await measureUntil(
      () async =>
          await b.testIdTextContains(rowId, title) &&
          !await b.testIdTextContains(rowId, unreadLabel),
      timeout: const Duration(seconds: 5),
    );
    requireTruth(
      await b.driver.execute(
            'return window.__tenturaFieldOpenMarker ?? null;',
            [],
          ) ==
          marker,
      'Session B reloaded while waiting for its Field unread marker to clear',
    );
    requireTruth(
      await b.driver.currentUrl == urlBefore,
      'Session B navigated while waiting for its Field unread marker to clear',
    );
    await assertNoUncaughtFlutterErrors(sessions);
  } catch (error, stackTrace) {
    File('${artifactDir.path}/failure.txt').writeAsStringSync(
      '$error\n$stackTrace',
    );
    await Future.wait(sessions.map((session) => session.captureFailure()));
    rethrow;
  } finally {
    await Future.wait(sessions.map((session) => session.finish()));
    File('${artifactDir.path}/timings.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(timings),
    );
  }

  stdout.writeln(
    '[field-open-multiclient] PASS run=$runId timings=${jsonEncode(timings)}',
  );
}
