// Setup mutations go straight to the API, like the sibling multiclient drivers.
// ignore_for_file: tentura_lints/no_raw_graphql_in_dart
// Issue #178 plan §P6 (last row): two accounts in two real browsers. Account A
// (offerer) sent a still-pending help offer and stays mounted on the Request's
// People tab; account B (Request author) opens People in its own Chrome
// session. A's own offer footer must flip from "Sent · not seen by the author
// yet" (Icons.done) to "Seen by the author · awaiting decision"
// (Icons.done_all) within 5 s over the `people_seen` frame — no reload, no
// re-navigation — and B's `help_offer_submitted` Activity receipt for that
// offer must turn seen via the attention bridge. The author's own Request is
// in their responsibility scope, so that receipt lands on the `myWork`
// attention surface, never on `activity`; the driver reads the whole feed.
//
// The offer is deliberately left pending: admitting the helper would hide the
// author-seen row, unlike the chat read-receipt journey.
//
// Run: REALTIME_MULTICLIENT_DRIVER=help_offer_author_seen_multiclient_web_test.dart
//      REALTIME_MULTICLIENT_RUNS=1 REALTIME_MULTICLIENT_NEGATIVE_PROOFS=false
//      ./scripts/run_realtime_multiclient_web_local.sh
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'multiclient_webdriver_support.dart';

// Exact EN copy from l10n/app_en.arb (helpOfferAuthor*), compared whole per
// line — a substring match would let other copy through. The seen row's
// Tooltip puts its "Seen <date>" line ahead of the label in the same
// semantics node.
const _authorNotSeenYet = 'Sent · not seen by the author yet';
const _authorSeen = 'Seen by the author · awaiting decision';
const _peopleTab = 'beacon.tab.people';
// app_en.arb beaconPeopleLensWillingToHelpHeading.
const _willingToHelpHeading = 'Willing to help';
const _helpOfferSubmittedKey = 'help_offer_submitted';

// Icons are painted on the canvas, not exposed in the web DOM. The row picks
// its icon and label from the same `authorSeenAt` check (done ↔ not seen,
// done_all ↔ seen); test/features/beacon_view/help_offer_tile_author_seen_test
// pins that pairing. Here the row's exact label stands in for its icon.

Future<void> main() async {
  final qaToken = Platform.environment['QA_AUTH_TOKEN']?.trim() ?? '';
  if (qaToken.isEmpty) {
    throw StateError('QA_AUTH_TOKEN is required');
  }
  final runId =
      Platform.environment['REALTIME_MULTICLIENT_RUN_ID'] ??
      'author-seen-${DateTime.now().microsecondsSinceEpoch}';
  final artifactDir = Directory(
    Platform.environment['REALTIME_MULTICLIENT_ARTIFACT_DIR'] ??
        'author-seen-artifacts/$runId',
  )..createSync(recursive: true);

  final timings = <String, int>{};
  final fixture = await bootstrapFixture(qaToken, runId);

  BrowserSession? accountA;
  BrowserSession? accountB;
  Object? failure;
  StackTrace? failureStack;
  try {
    accountA = await BrowserSession.start('account-a-offerer', artifactDir);
    accountB = await BrowserSession.start('account-b-author', artifactDir);
    await Future.wait([
      accountA.login(fixture.helperEmail),
      accountB.login(fixture.authorEmail),
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
    '[author-seen-multiclient] PASS run=$runId timings=${jsonEncode(timings)}',
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

  // Setup (not under test): B publishes and forwards to A; A offers help.
  // The offer stays pending — B never admits A in this journey.
  final beaconId = await createBeaconViaApi(
    authorEmail: fixture.authorEmail,
    title: 'Author seen request $suffix',
  );
  await forwardBeaconViaApi(
    authorEmail: fixture.authorEmail,
    beaconId: beaconId,
    recipientId: fixture.helperUserId,
  );
  final offerMessage = 'Author seen offer $runId';
  final offerResponse = await postGraphQlAuthenticated(
    email: fixture.helperEmail,
    query:
        'mutation { beaconOfferHelp(id: "$beaconId", message: '
        '"${escapeGraphQlString(offerMessage)}") }',
  );
  final offerData = offerResponse['data'] as Map<String, dynamic>?;
  if (offerResponse['errors'] != null ||
      offerData?['beaconOfferHelp'] != true) {
    throw StateError('beaconOfferHelp failed: $offerResponse');
  }

  // B's receipt for the new offer exists and is still unseen.
  await waitUntil(
    () async =>
        (await _offerReceipts(fixture.authorEmail, beaconId)).isNotEmpty,
    timeout: const Duration(seconds: 15),
  );
  requireTruth(
    (await _offerReceipts(
      fixture.authorEmail,
      beaconId,
    )).every((receipt) => receipt['seenAt'] == null),
    "B's help_offer_submitted receipt was seen before B opened People",
  );

  // 1. B is parked elsewhere so it cannot have seen People yet; A opens the
  //    Request's People tab, where its own pending offer carries the footer.
  //    A pending offerer's access level is observer (not member).
  await b.open('/home/work');
  await b.waitForText('My Work');
  await _openPeople(a, beaconId);

  // 2. First footer state: sent, not seen by the author yet (Icons.done).
  try {
    await waitUntil(
      () => _hasExactLabel(a, _authorNotSeenYet),
      timeout: const Duration(seconds: 20),
    );
  } on TimeoutException {
    throw StateError(
      'A (pending offerer, observer access) never saw its own offer footer '
      '"$_authorNotSeenYet" on People',
    );
  }
  requireTruth(
    !await _hasExactLabel(a, _authorSeen),
    'A saw "Seen by the author" before B opened People',
  );

  // A stays mounted from here on. A window marker proves no reload: any
  // document reload or hard navigation wipes it.
  final marker = 'aseen-$suffix';
  await a.driver.execute('window.__tenturaAuthorSeenMarker = arguments[0];', [
    marker,
  ]);
  final urlBefore = await a.driver.currentUrl;

  // 3. B, the author, opens the Request and then People. The 5 s budget
  //    starts once B's People click has been performed, so WebDriver's own
  //    click latency does not count against the live update.
  await b.open('/beacon/view/$beaconId');
  await b.waitForTestId(_peopleTab);
  await b.clickTestId(_peopleTab);
  final peopleOpenedAt = Stopwatch()..start();

  // 4. Second footer state: seen by the author (Icons.done_all) within 5 s,
  //    live, and the not-seen state is gone.
  final aFlipped = waitUntil(
    () async =>
        await _hasExactLabel(a, _authorSeen) &&
        !await _hasExactLabel(a, _authorNotSeenYet),
    timeout: const Duration(seconds: 5),
  ).then((_) => peopleOpenedAt.elapsedMilliseconds);
  // Awaited together so a flip timeout surfaces here (and artifacts are
  // captured) instead of escaping as an unhandled async error.
  // B's People lens keeps the pending offer under a collapsed section, so its
  // heading (not the offer message) proves B's People surface is showing.
  final bOpened = b
      .waitForText(_willingToHelpHeading)
      .then((_) => peopleOpenedAt.elapsedMilliseconds);
  final [aSeenMs, bOpenMs] = await Future.wait([aFlipped, bOpened]);
  timings['b_open_people_ms'] = bOpenMs;
  timings['a_footer_seen_ms'] = aSeenMs;
  requireTruth(
    timings['a_footer_seen_ms']! <= 5000,
    'A flipped ${timings['a_footer_seen_ms']} ms after B opened People',
  );
  requireTruth(
    await a.driver.execute(
          'return window.__tenturaAuthorSeenMarker ?? null;',
          [],
        ) ==
        marker,
    'A reloaded while waiting for the author-seen footer',
  );
  requireTruth(
    await a.driver.currentUrl == urlBefore,
    'A navigated while waiting for the author-seen footer',
  );

  // 5. Bridge: B's help_offer_submitted receipt for A's offer is now seen.
  try {
    timings['b_activity_offer_receipt_seen_ms'] = await measureUntil(
      () async {
        final receipts = await _offerReceipts(fixture.authorEmail, beaconId);
        return receipts.isNotEmpty &&
            receipts.every((receipt) => receipt['seenAt'] != null);
      },
      timeout: const Duration(seconds: 5),
    );
  } on TimeoutException {
    throw StateError(
      "B's help_offer_submitted receipt did not turn seen after B opened "
      'People',
    );
  }
}

Future<void> _openPeople(BrowserSession session, String beaconId) async {
  await session.open('/beacon/view/$beaconId');
  await session.waitForTestId(_peopleTab);
  await session.clickTestId(_peopleTab);
}

Future<bool> _hasExactLabel(BrowserSession session, String label) async =>
    await session.driver.execute(
      r'''
      const wanted = arguments[0];
      const hasLine = value =>
        (value || '').split('\n').some(line => line.trim() === wanted);
      return Array.from(document.querySelectorAll('*')).some(element =>
        hasLine(element.getAttribute('aria-label')) ||
        hasLine(element.textContent));
    ''',
      [label],
    ) ==
    true;

/// B's `help_offer_submitted` receipts on [beaconId] across the whole
/// attention feed (every surface; top-level items plus event previews).
Future<List<Map<String, dynamic>>> _offerReceipts(
  String email,
  String beaconId,
) async {
  final receipts = <String, Map<String, dynamic>>{};
  final response = await postGraphQlAuthenticated(
    email: email,
    query:
        'query { attentionFeed(view: "all", limit: 100) '
        '{ page { items { id beaconId presentationKey seenAt '
        'eventsPreview { id beaconId presentationKey seenAt } } } } }',
  );
  if (response['errors'] != null) {
    throw StateError('attentionFeed failed: $response');
  }
  final data = response['data'] as Map<String, dynamic>?;
  final feed = data?['attentionFeed'] as Map<String, dynamic>?;
  final page = feed?['page'] as Map<String, dynamic>?;
  final items = (page?['items'] as List?) ?? const [];
  for (final item in items.cast<Map<String, dynamic>>()) {
    final previews = (item['eventsPreview'] as List?) ?? const [];
    for (final receipt in [item, ...previews.cast<Map<String, dynamic>>()]) {
      if (receipt['beaconId'] == beaconId &&
          receipt['presentationKey'] == _helpOfferSubmittedKey) {
        receipts[receipt['id']! as String] = receipt;
      }
    }
  }
  return receipts.values.toList();
}
