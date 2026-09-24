// Setup mutations go straight to the API, like the sibling multiclient drivers.
// ignore_for_file: tentura_lints/no_raw_graphql_in_dart
// Issue #178 plan §P5: two accounts in two real browsers. Account A (Request
// author) stays mounted on the General discussion; account B (admitted
// helper) opens General in its own Chrome session. A's own message must flip
// from the single check ("Sent") to the double check ("Read by 1 person",
// Icons.done_all) within 5 s over the `room_seen_peer` invalidation — no
// reload, no re-navigation — and the message actions sheet must show the
// "Read by" row.
//
// Run: REALTIME_MULTICLIENT_DRIVER=chat_read_receipt_multiclient_web_test.dart
//      REALTIME_MULTICLIENT_RUNS=1 REALTIME_MULTICLIENT_NEGATIVE_PROOFS=false
//      ./scripts/run_realtime_multiclient_web_local.sh
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webdriver/async_io.dart' hide TimeoutException;

import 'multiclient_webdriver_support.dart';

// EN copy from l10n/app_en.arb (beaconRoomReceipt* / beaconRoomReadBy*).
const _receiptSent = 'Sent';
const _receiptReadByOne = 'Read by 1 person';
const _readByTitle = 'Read by';
const _readByNobodyYet = 'Nobody has read this yet';
const _messageActionsTitle = 'Message actions';

Future<void> main() async {
  final qaToken = Platform.environment['QA_AUTH_TOKEN']?.trim() ?? '';
  if (qaToken.isEmpty) {
    throw StateError('QA_AUTH_TOKEN is required');
  }
  final runId =
      Platform.environment['REALTIME_MULTICLIENT_RUN_ID'] ??
      'read-receipt-${DateTime.now().microsecondsSinceEpoch}';
  final artifactDir = Directory(
    Platform.environment['REALTIME_MULTICLIENT_ARTIFACT_DIR'] ??
        'read-receipt-artifacts/$runId',
  )..createSync(recursive: true);

  final timings = <String, int>{};
  final fixture = await bootstrapFixture(qaToken, runId);

  BrowserSession? accountA;
  BrowserSession? accountB;
  Object? failure;
  StackTrace? failureStack;
  try {
    accountA = await BrowserSession.start('account-a-author', artifactDir);
    accountB = await BrowserSession.start('account-b-helper', artifactDir);
    await Future.wait([
      accountA.login(fixture.authorEmail),
      accountB.login(fixture.helperEmail),
    ]);
    await _runJourney(
      a: accountA,
      b: accountB,
      fixture: fixture,
      runId: runId,
      timings: timings,
    );
    await assertNoUncaughtFlutterErrors([accountA, accountB]);
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
    File('${artifactDir.path}/failure.txt').writeAsStringSync(
      '$error\n$stackTrace',
    );
    await Future.wait([
      if (accountA != null) accountA.captureFailure(),
      if (accountB != null) accountB.captureFailure(),
    ]);
  } finally {
    await Future.wait([
      if (accountA != null) accountA.finish(),
      if (accountB != null) accountB.finish(),
    ]);
    File('${artifactDir.path}/timings.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(timings),
    );
  }

  if (failure != null) {
    Error.throwWithStackTrace(failure, failureStack!);
  }
  stdout.writeln(
    '[read-receipt-multiclient] PASS run=$runId timings=${jsonEncode(timings)}',
  );
}

Future<void> _runJourney({
  required BrowserSession a,
  required BrowserSession b,
  required Fixture fixture,
  required String runId,
  required Map<String, int> timings,
}) async {
  final suffix = DateTime.now().microsecondsSinceEpoch;
  final probe = 'Read receipt probe $suffix';

  // Setup (not under test): author publishes, forwards to the helper, helper
  // offers, author admits — General requires admission.
  final beaconId = await createBeaconViaApi(
    authorEmail: fixture.authorEmail,
    title: 'Read receipt request $suffix',
  );
  await forwardBeaconViaApi(
    authorEmail: fixture.authorEmail,
    beaconId: beaconId,
    recipientId: fixture.helperUserId,
  );
  await _graphQlOk(
    email: fixture.helperEmail,
    field: 'beaconOfferHelp',
    query:
        'mutation { beaconOfferHelp(id: "$beaconId", message: '
        '"${escapeGraphQlString('Read receipt helper $runId')}") }',
  );
  await _graphQlOk(
    email: fixture.authorEmail,
    field: 'acceptHelpOffer',
    query:
        'mutation { acceptHelpOffer(id: "$beaconId", '
        'offerUserId: "${fixture.helperUserId}") { beaconId } }',
  );

  // 1. A opens General and sends its own message. B is parked elsewhere so it
  //    cannot have seen the room yet.
  await b.open('/home/work');
  await b.waitForText('My Work');
  await _openGeneral(a, beaconId);
  await a.sendChatMessage(probe);
  await a.waitForText(probe);

  // 2. First transition: pending → sent (single check), never read yet.
  await waitUntil(
    () => a.hasText(_receiptSent),
    timeout: const Duration(seconds: 10),
  );
  requireTruth(
    !await a.hasText(_receiptReadByOne),
    'A saw a read receipt before B opened the discussion',
  );

  // A stays mounted from here on. A window marker proves no reload: any
  // document reload or hard navigation wipes it.
  final marker = 'dap-$suffix';
  await a.driver.execute('window.__tenturaReadReceiptMarker = arguments[0];', [
    marker,
  ]);
  final urlBefore = await a.driver.currentUrl;

  // 3. B opens the General discussion in its own browser and sees A's message.
  final bOpenedAt = DateTime.now();
  await _openGeneral(b, beaconId);
  await b.waitForText(probe);
  timings['b_open_general_ms'] = DateTime.now()
      .difference(bOpenedAt)
      .inMilliseconds;

  // 4. Second transition: sent → read (Icons.done_all) within 5 s, live.
  timings['a_glyph_read_ms'] = await measureUntil(
    () => a.hasText(_receiptReadByOne),
    timeout: const Duration(seconds: 5),
  );
  requireTruth(
    await a.driver.execute(
          'return window.__tenturaReadReceiptMarker ?? null;',
          [],
        ) ==
        marker,
    'A reloaded while waiting for the read receipt',
  );
  requireTruth(
    await a.driver.currentUrl == urlBefore,
    'A navigated while waiting for the read receipt',
  );

  // 5. The "Read by" row: open A's own bubble's actions sheet via the desktop
  //    hover toolbar and require the Read-by row, not the nobody-yet
  //    placeholder.
  await _openMessageActions(a, probe);
  await a.waitForText(_messageActionsTitle);
  await waitUntil(
    () => _hasExactLabel(a, _readByTitle),
    timeout: const Duration(seconds: 5),
  );
  requireTruth(
    !await a.hasText(_readByNobodyYet),
    'Read-by row still says nobody has read the message',
  );
}

// The Chat tab (`beacon.tab.room`) opens General directly; rooms are
// General-only, so there is no thread list to pick from.
Future<void> _openGeneral(BrowserSession session, String beaconId) async {
  await session.open('/beacon/view/$beaconId');
  await waitUntil(
    () async =>
        await session.hasTestId('room.message.input') ||
        await session.hasTestId('beacon.tab.room'),
  );
  if (!await session.hasTestId('room.message.input')) {
    await session.clickTestId('beacon.tab.room');
  }
  await session.waitForTestId('room.message.input');
}

Future<void> _openMessageActions(BrowserSession session, String body) async {
  late WebElement bubble;
  await waitUntil(() async {
    final result = await session.driver.execute(
      '''
      const wanted = arguments[0];
      const visible = element => {
        const rect = element.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0;
      };
      const valueOf = element =>
        element.getAttribute('aria-label') || element.innerText ||
          element.textContent || '';
      const matches = Array.from(document.querySelectorAll('*')).filter(
        element => visible(element) && valueOf(element).includes(wanted));
      matches.sort((a, b) => valueOf(a).length - valueOf(b).length);
      return matches[0] || null;
    ''',
      [body],
    );
    if (result is! WebElement) return false;
    bubble = result;
    return true;
  });
  // Hover reveals the desktop toolbar; its "…" button opens the actions sheet.
  await session.driver.mouse.moveTo(element: bubble);
  await session.clickText(_messageActionsTitle);
}

Future<bool> _hasExactLabel(BrowserSession session, String label) async =>
    await session.driver.execute(
      r'''
      // Flutter semantics joins title/subtitle with '\n' in textContent;
      // innerText collapses it to a space, so compare the first line.
      const wanted = arguments[0];
      const firstLine = value => (value || '').trim().split('\n')[0].trim();
      return Array.from(document.querySelectorAll('*')).some(element =>
        firstLine(element.getAttribute('aria-label')) === wanted ||
        firstLine(element.textContent) === wanted);
    ''',
      [label],
    ) ==
    true;

Future<void> _graphQlOk({
  required String email,
  required String field,
  required String query,
}) async {
  final response = await postGraphQlAuthenticated(email: email, query: query);
  final errors = response['errors'];
  final data = response['data'] as Map<String, dynamic>?;
  if (errors != null || data?[field] == null || data?[field] == false) {
    throw StateError('$field failed: $response');
  }
}
