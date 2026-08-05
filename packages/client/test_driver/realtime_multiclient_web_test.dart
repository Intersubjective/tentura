import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:webdriver/async_io.dart' hide TimeoutException;

const _appOrigin = 'https://dev.lvh.me:9443';
const _apiOrigin = 'http://127.0.0.1:2080';
const _driverUri = 'http://127.0.0.1:4444/';
const _sessionCookieName = '__Host-tentura_session';

Future<void> main() async {
  final qaToken = Platform.environment['QA_AUTH_TOKEN']?.trim() ?? '';
  if (qaToken.isEmpty) {
    throw StateError('QA_AUTH_TOKEN is required');
  }
  final runId =
      Platform.environment['REALTIME_MULTICLIENT_RUN_ID'] ??
      'realtime-${DateTime.now().microsecondsSinceEpoch}';
  final disabledPath =
      Platform.environment['REALTIME_MULTICLIENT_DISABLE_PATH']?.trim() ?? '';
  if (disabledPath.isNotEmpty &&
      disabledPath != 'live' &&
      disabledPath != 'catch_up') {
    throw StateError(
      'REALTIME_MULTICLIENT_DISABLE_PATH must be live or catch_up',
    );
  }
  final artifactDir = Directory(
    Platform.environment['REALTIME_MULTICLIENT_ARTIFACT_DIR'] ??
        'realtime-multiclient-artifacts/$runId',
  )..createSync(recursive: true);

  final timings = <String, int>{};
  final proof = <String, dynamic>{};
  final fixture = await _bootstrap(qaToken, runId);
  BrowserSession? author;
  BrowserSession? authorPeer;
  BrowserSession? helper;
  BrowserSession? helperPeer;
  Object? failure;
  StackTrace? failureStack;
  try {
    author = await BrowserSession.start('author', artifactDir);
    authorPeer = await BrowserSession.start('author-peer', artifactDir);
    helper = await BrowserSession.start('helper', artifactDir);
    helperPeer = await BrowserSession.start('helper-peer', artifactDir);
    await Future.wait([
      author.login(fixture.authorEmail),
      authorPeer.login(fixture.authorEmail),
      helper.login(fixture.helperEmail),
      helperPeer.login(fixture.helperEmail),
    ]);
    await _clearAuthorAttentionBaseline(author, authorPeer);
    if (disabledPath == 'live') {
      final suspended = await _controlSocket(
        qaToken,
        fixture.helperUserId,
        action: 'suspend',
      );
      _require(
        suspended.sessionsClosed > 0,
        'Live-delivery negative proof closed no helper session',
      );
    }
    await _runJourney(
      author: author,
      authorPeer: authorPeer,
      helper: helper,
      helperPeer: helperPeer,
      fixture: fixture,
      qaToken: qaToken,
      timings: timings,
      proof: proof,
      artifactDir: artifactDir,
      disabledPath: disabledPath,
    );
    await _assertNoUncaughtFlutterErrors([
      author,
      authorPeer,
      helper,
      helperPeer,
    ]);
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
    await Future.wait([
      if (author != null) author.captureFailure(),
      if (authorPeer != null) authorPeer.captureFailure(),
      if (helper != null) helper.captureFailure(),
      if (helperPeer != null) helperPeer.captureFailure(),
    ]);
  } finally {
    await _controlSocket(
      qaToken,
      fixture.authorUserId,
      action: 'resume',
    );
    await _controlSocket(
      qaToken,
      fixture.helperUserId,
      action: 'resume',
    );
    await Future.wait([
      if (author != null) author.finish(),
      if (authorPeer != null) authorPeer.finish(),
      if (helper != null) helper.finish(),
      if (helperPeer != null) helperPeer.finish(),
    ]);
    File('${artifactDir.path}/timings.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(timings),
    );
    if (proof.isNotEmpty) {
      File('${artifactDir.path}/proof.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(proof),
      );
    }
  }

  if (failure != null) {
    Error.throwWithStackTrace(failure, failureStack!);
  }
  stdout.writeln(
    '[realtime-multiclient] PASS run=$runId timings=${jsonEncode(timings)}',
  );
}

Future<void> _runJourney({
  required BrowserSession author,
  required BrowserSession authorPeer,
  required BrowserSession helper,
  required BrowserSession helperPeer,
  required Fixture fixture,
  required String qaToken,
  required Map<String, int> timings,
  required Map<String, dynamic> proof,
  required Directory artifactDir,
  required String disabledPath,
}) async {
  final suffix = DateTime.now().microsecondsSinceEpoch;
  final title = 'Realtime request $suffix';
  final chatMessage = 'Realtime chat $suffix';
  final failedMessage = 'Must not deliver $suffix';
  final gapMessage = 'Reconnect catch-up $suffix';
  final myWorkUnreadMessage = 'Same account My Work unread $suffix';

  // 1. Helper Inbox stays mounted while the author publishes and forwards.
  await helper.open('/home/inbox');
  await helper.waitForText('Inbox');
  await author.open('/beacon/new');
  await author.setTestId('request.title', title);
  await author.setTestId(
    'request.description',
    'Simultaneous WebDriver proof for $title',
  );
  await author.clickText('Recipients');
  await author.clickTestId('forward.recipient.${fixture.helperUserId}');

  await author.setNetworkLatency(const Duration(milliseconds: 700));
  final submitStarted = author.clickTestId('forward.submit');
  await author.waitForTestIdDisabled('forward.submit');
  await author.setNetworkLatency(Duration.zero);
  await submitStarted;
  timings['inbox_delivery_ms'] = await _measureUntil(
    () => helper.hasText(title),
    timeout: const Duration(seconds: 5),
  );
  _require(await helper.textCount(title) == 1, 'Inbox card duplicated');

  // Open People before the helper command so convergence cannot be navigation.
  await author.open('/home/work');
  await author.clickText(title);
  await _waitUntil(
    () async => (await author.driver.currentUrl).contains('/beacon/view/'),
  );
  final beaconId = _beaconIdFromUrl(await author.driver.currentUrl);
  await author.clickTestId('beacon.tab.people');
  await authorPeer.open('/home/updates');
  await authorPeer.waitForText('Updates');

  // 2. Helper offers help; the already-mounted People projection converges.
  await helper.open('/home/inbox');
  await helper.waitForText('Inbox');
  await helper.waitForText(title);
  await helper.waitForTestId('inbox.offer_help');
  await helper.clickTestId('inbox.offer_help');
  await helper.waitForTestId('help_offer.message');
  await helper.setTestId('help_offer.message', 'I can help with software');
  await helper.clickTestId('help_offer.browse_categories');
  await helper.setTestId('help_offer.search', 'software');
  await helper.clickTestId('capability.software');
  await helper.clickTestId('help_offer.submit');
  timings['updates_delivery_ms'] = await _measureUntil(
    () => authorPeer.hasTestId('updates-unread-count-1'),
    timeout: const Duration(seconds: 5),
  );

  // 2a. The enabled Updates slice receives exactly one offer receipt in both
  // author sessions. Opening the card must mark it seen before navigating to
  // the exact People target, then converge its unread badge to zero everywhere.
  await author.open('/home/updates');
  await author.waitForText('Updates');
  await Future.wait([
    author.waitForText('offered help'),
    authorPeer.waitForText('offered help'),
    author.waitForTestId('updates-unread-count-1'),
    authorPeer.waitForTestId('updates-unread-count-1'),
  ]);
  _require(
    await authorPeer.textCount('offered help') == 1,
    'Offer produced duplicate Updates cards',
  );
  await author.clickText('offered help');
  await _waitUntil(
    () async =>
        (await author.driver.currentUrl).contains('/beacon/view/$beaconId'),
  );
  await author.waitForText('People');
  await author.open('/home/updates');
  await author.waitForText('Updates');
  timings['updates_open_ack_ms'] = await _measureUntil(
    () async =>
        await author.hasTestId('updates-unread-count-0') &&
        await authorPeer.hasTestId('updates-unread-count-0'),
    timeout: const Duration(seconds: 3),
  );

  // 3. Both Chat views stay mounted. First prove the established error UI,
  // then prove the successful hint creates exactly one remote bubble.
  // helperPeer enters Chat so helper's same-account My Work tab stays room-naive.
  await Future.wait([
    author.open('/beacon/view/$beaconId'),
    helperPeer.open('/beacon/view/$beaconId'),
  ]);
  await Future.wait([
    author.clickTestId('beacon.room.open'),
    helperPeer.clickTestId('beacon.room.open'),
  ]);
  await Future.wait([
    author.waitForTestId('room.message.input'),
    helperPeer.waitForTestId('room.message.input'),
  ]);

  await helperPeer.blockGraphql(true);
  await helperPeer.sendChatMessage(failedMessage);
  await helperPeer.waitForText('No Internet connection');
  _require(
    !await author.hasText(failedMessage),
    'Failed message was delivered',
  );
  await helperPeer.blockGraphql(false);
  // Error snackbars remain visible for 15 seconds and cover the composer. Close
  // the deliberately-proven error before verifying that the next send works.
  await helperPeer.dismissSnackBar('No Internet connection');
  await helperPeer.waitForTextGone('No Internet connection');

  await helperPeer.sendChatMessage(chatMessage);
  timings['chat_delivery_ms'] = await _measureUntil(
    () => author.hasText(chatMessage),
    timeout: const Duration(seconds: 5),
  );
  _require(await author.textCount(chatMessage) == 1, 'Chat bubble duplicated');

  // 3a. Two independently authenticated sessions for the helper account prove
  // room_seen convergence. One tab remains mounted on My Work while its
  // same-account peer reads Chat; the mounted projection never navigates or
  // reloads. Inbox uses the same desk-relevant stream and has a focused Cubit
  // contract because offered Requests are no longer present in Inbox.
  await Future.wait([
    helper.open('/home/work'),
    helperPeer.open('/home/work'),
  ]);
  await Future.wait([
    helper.waitForText(title),
    helperPeer.waitForText(title),
  ]);
  await author.sendChatMessage(myWorkUnreadMessage);
  await helper.waitForTestIdText(
    'my_work.room_status.$beaconId',
    '+1',
  );
  await helperPeer.open('/beacon/view/$beaconId');
  await helperPeer.clickTestId('beacon.room.open');
  await helperPeer.waitForText(myWorkUnreadMessage);
  timings['same_account_my_work_read_ms'] = await _measureUntil(
    () async => !await helper.testIdTextContains(
      'my_work.room_status.$beaconId',
      '+1',
    ),
    timeout: const Duration(seconds: 5),
  );

  // Issue #102 setup: author creates the ask while still on the beacon surface,
  // then moves to My Work and stays there while helper accepts.
  final askTitle = 'Accept proof $suffix';
  final askBody = '102 accept regression $suffix';
  final askItemId = await _markAskViaApi(
    authorEmail: fixture.authorEmail,
    beaconId: beaconId,
    targetPersonId: fixture.helperUserId,
    title: askTitle,
    body: askBody,
  );

  // 7. Issue #102: author stays on My Work; helper accepts an ask via API.
  await Future.wait([
    author.open('/home/work'),
    authorPeer.open('/home/updates'),
  ]);
  await Future.wait([
    author.waitForText(title),
    authorPeer.waitForText('Updates'),
  ]);
  final receiptIdsBefore102 = await authorPeer.collectUpdatesReceiptIds();
  await _acceptAskViaApi(helperEmail: fixture.helperEmail, itemId: askItemId);
  timings['my_work_102_delivery_ms'] = await _measureUntil(
    () async =>
        await author.hasTestId('updates-unread-count-1') &&
        await author.hasText('Ask accepted') &&
        await authorPeer.hasTestId('updates-unread-count-1'),
    timeout: const Duration(seconds: 5),
  );
  _require(
    await authorPeer.textCount('accepted your ask') == 1,
    'Commitment accept produced duplicate Updates cards',
  );
  final receiptIdsAfter102 = await authorPeer.collectUpdatesReceiptIds();
  final newReceiptIds102 = receiptIdsAfter102.difference(receiptIdsBefore102);
  _require(
    newReceiptIds102.length == 1,
    'Expected exactly one new Updates receipt id',
  );
  final receiptId102 = newReceiptIds102.single;
  _require(
    await authorPeer.receiptIdCount(receiptId102) == 1,
    'Duplicate stable receipt id in Updates feed',
  );
  final qaLatencyMs = await author.readQaHeadRefreshLatencyMs();
  if (qaLatencyMs != null) {
    timings['my_work_102_qa_head_refresh_latency_ms'] = qaLatencyMs;
  }
  proof['my_work_102'] = {
    'runId': Platform.environment['REALTIME_MULTICLIENT_RUN_ID'],
    'beaconId': beaconId,
    'itemId': askItemId,
    'receiptId': receiptId102,
    'delivery_ms': timings['my_work_102_delivery_ms'],
    'qa_head_refresh_latency_ms': qaLatencyMs,
    'artifactDir': artifactDir.path,
    'ok': true,
  };

  // 8. Missed attention receipt: author socket gated, then catch-up without dupes.
  final receiptIdsBeforeReconnect =
      await authorPeer.collectUpdatesReceiptIds();
  final suspendedAuthor = await _controlSocket(
    qaToken,
    fixture.authorUserId,
    action: 'suspend',
  );
  _require(
    suspendedAuthor.sessionsClosed > 0,
    'QA gate closed no author session',
  );
  final reconnectAskItemId = await _markAskViaApi(
    authorEmail: fixture.authorEmail,
    beaconId: beaconId,
    targetPersonId: fixture.helperUserId,
    title: 'Reconnect catch-up ask $suffix',
    body: 'Attention reconnect proof $suffix',
  );
  await _acceptAskViaApi(
    helperEmail: fixture.helperEmail,
    itemId: reconnectAskItemId,
  );
  final receiptIdsWhileGated = await authorPeer.collectUpdatesReceiptIds();
  _require(
    receiptIdsWhileGated.difference(receiptIdsBeforeReconnect).isEmpty,
    'Attention receipt arrived while author socket was gated',
  );
  if (disabledPath != 'catch_up') {
    await _controlSocket(qaToken, fixture.authorUserId, action: 'resume');
  }
  timings['attention_reconnect_catch_up_ms'] = await _measureUntil(
    () async {
      final ids = await authorPeer.collectUpdatesReceiptIds();
      return ids.difference(receiptIdsBeforeReconnect).length == 1;
    },
    timeout: const Duration(seconds: 8),
  );
  final receiptIdsAfterReconnect = await authorPeer.collectUpdatesReceiptIds();
  _require(
    receiptIdsAfterReconnect.length ==
        receiptIdsAfterReconnect.toSet().length,
    'Reconnect catch-up duplicated a receipt id in the feed',
  );
  final newReceiptIdsReconnect = receiptIdsAfterReconnect.difference(
    receiptIdsBeforeReconnect,
  );
  _require(
    newReceiptIdsReconnect.length == 1,
    'Reconnect catch-up produced wrong receipt id count',
  );
  _require(
    await authorPeer.receiptIdCount(newReceiptIdsReconnect.single) == 1,
    'Reconnect catch-up duplicated stable receipt content',
  );
  proof['attention_reconnect'] = {
    'receiptIdsBefore': receiptIdsBeforeReconnect.toList(),
    'receiptIdsAfter': receiptIdsAfterReconnect.toList(),
    'newReceiptIds': newReceiptIdsReconnect.toList(),
    'catch_up_ms': timings['attention_reconnect_catch_up_ms'],
    'ok': true,
  };

  // 4. Helper My Work stays mounted while the author enters review.
  await helper.open('/home/work');
  await helper.waitForText(title);
  await author.open('/beacon/view/$beaconId');
  await author.clickTestId('beacon.hud_author_action.markEnoughHelp');
  await author.clickTestId('beacon.hud.mark_enough_help.confirm');
  timings['my_work_status_ms'] = await _measureUntil(
    () => helper.hasText('Enough help — in motion'),
    timeout: const Duration(seconds: 5),
  );
  await author.clickTestId('beacon.hud_author_action.wrapUpForReview');
  timings['my_work_review_ms'] = await _measureUntil(
    () => helper.hasText('Closed by'),
    timeout: const Duration(seconds: 5),
  );
  _require(await helper.hasText(title), 'Request disappeared from My Work');

  // 5. Force a confirmed missed-event window. The server deny gate prevents
  // auth until resume, so the mutation cannot be delivered live.
  await Future.wait([
    author.open('/beacon/view/$beaconId'),
    helper.open('/beacon/view/$beaconId'),
  ]);
  await Future.wait([
    author.clickTestId('beacon.room.open'),
    helper.clickTestId('beacon.room.open'),
  ]);
  final suspended = await _controlSocket(
    qaToken,
    fixture.helperUserId,
    action: 'suspend',
  );
  _require(suspended.sessionsClosed > 0, 'QA gate closed no helper session');
  await author.sendChatMessage(gapMessage);
  _require(
    !await helper.hasText(gapMessage),
    'Gap mutation arrived while gated',
  );
  if (disabledPath != 'catch_up') {
    await _controlSocket(qaToken, fixture.helperUserId, action: 'resume');
  }
  timings['reconnect_catch_up_ms'] = await _measureUntil(
    () => helper.hasText(gapMessage),
    timeout: const Duration(seconds: 8),
  );
  _require(
    await helper.textCount(gapMessage) == 1,
    'Catch-up produced duplicate stable content',
  );

  // 6. Author Profile stays mounted while helper changes the friendship.
  await author.open('/profile/view/${fixture.helperUserId}');
  await author.waitForText('Trust: mutual');
  await helper.open('/profile/view/${fixture.authorUserId}');
  await helper.clickText('Show menu');
  await helper.clickText('Stop trusting');
  await helper.clickText('Remove');
  timings['profile_friendship_ms'] = await _measureUntil(
    () => author.hasText('Trust: one-way out'),
    timeout: const Duration(seconds: 5),
  );

  // Connected delivery budget is p95 <= 1.5s. A single run records samples;
  // the shell runner aggregates five consecutive runs as the exit gate.
  for (final entry in timings.entries) {
    final reconnect = entry.key == 'reconnect_catch_up_ms' ||
        entry.key == 'attention_reconnect_catch_up_ms';
    final budgetMs = reconnect ? 3000 : 1500;
    _require(
      entry.value <= budgetMs,
      '${entry.key}=${entry.value}ms exceeded ${budgetMs}ms',
    );
  }
}

Future<void> _clearAuthorAttentionBaseline(
  BrowserSession author,
  BrowserSession authorPeer,
) async {
  // QA bootstrap establishes a reciprocal connection. With the new-producer
  // gate enabled that setup event is a valid receipt, but not part of the
  // offer-help release journey, so settle it through the actual Updates UI.
  await Future.wait([
    author.open('/home/updates'),
    authorPeer.open('/home/updates'),
  ]);
  await Future.wait([
    author.waitForText('Updates'),
    authorPeer.waitForText('Updates'),
  ]);
  await author.clickText('Mark all seen');
  await _waitUntil(
    () async =>
        await author.hasTestId('updates-unread-count-0') &&
        await authorPeer.hasTestId('updates-unread-count-0'),
    timeout: const Duration(seconds: 5),
  );
}

String _beaconIdFromUrl(String rawUrl) {
  final match = RegExp('/beacon/view/([^/?#]+)').firstMatch(rawUrl);
  if (match == null) throw StateError('No beacon id in $rawUrl');
  return match.group(1)!;
}

Future<int> _measureUntil(
  FutureOr<bool> Function() condition, {
  required Duration timeout,
}) async {
  final stopwatch = Stopwatch()..start();
  await _waitUntil(condition, timeout: timeout);
  return stopwatch.elapsedMilliseconds;
}

Future<void> _waitUntil(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.timestamp().add(timeout);
  while (DateTime.timestamp().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Condition did not converge within $timeout');
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<Fixture> _bootstrap(String token, String runId) async {
  final response = await http.post(
    Uri.parse('$_apiOrigin/_qa/integration/bootstrap'),
    headers: {
      HttpHeaders.authorizationHeader: 'Bearer $token',
      HttpHeaders.contentTypeHeader: 'application/json',
    },
    body: jsonEncode({'runId': runId}),
  );
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException(
      'QA bootstrap ${response.statusCode}: ${response.body}',
    );
  }
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  return Fixture(
    authorEmail: body['authorEmail']! as String,
    authorUserId: body['authorUserId']! as String,
    helperEmail: body['helperEmail']! as String,
    helperUserId: body['helperUserId']! as String,
  );
}

Future<SocketControlResult> _controlSocket(
  String token,
  String userId, {
  required String action,
}) async {
  final response = await http.post(
    Uri.parse('$_apiOrigin/_qa/integration/realtime-socket'),
    headers: {
      HttpHeaders.authorizationHeader: 'Bearer $token',
      HttpHeaders.contentTypeHeader: 'application/json',
    },
    body: jsonEncode({'userId': userId, 'action': action}),
  );
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException(
      'QA realtime socket $action ${response.statusCode}: ${response.body}',
    );
  }
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  return SocketControlResult(
    suspended: body['suspended']! as bool,
    sessionsClosed: body['sessionsClosed']! as int,
  );
}

String _escapeGraphQlString(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

Future<String> _markAskViaApi({
  required String authorEmail,
  required String beaconId,
  required String targetPersonId,
  required String title,
  required String body,
}) async {
  final query =
      'mutation { markAsk(beaconId: "$beaconId", title: "${_escapeGraphQlString(title)}", targetPersonId: "$targetPersonId", body: "${_escapeGraphQlString(body)}") { id } }';
  final response = await _postGraphQlAuthenticated(
    email: authorEmail,
    query: query,
  );
  final errors = response['errors'];
  if (errors != null) {
    throw StateError('markAsk failed: $errors');
  }
  final data = response['data'] as Map<String, dynamic>?;
  final markAsk = data?['markAsk'] as Map<String, dynamic>?;
  final id = markAsk?['id'] as String?;
  if (id == null || id.isEmpty) {
    throw StateError('markAsk returned no id: $response');
  }
  return id;
}

Future<void> _acceptAskViaApi({
  required String helperEmail,
  required String itemId,
}) async {
  final query = 'mutation { acceptAsk(itemId: "$itemId") { id status } }';
  final response = await _postGraphQlAuthenticated(
    email: helperEmail,
    query: query,
  );
  final errors = response['errors'];
  if (errors != null) {
    throw StateError('acceptAsk failed: $errors');
  }
  final data = response['data'] as Map<String, dynamic>?;
  final acceptAsk = data?['acceptAsk'] as Map<String, dynamic>?;
  final status = acceptAsk?['status'];
  if (status != 1) {
    throw StateError('acceptAsk did not accept: $response');
  }
}

Future<Map<String, dynamic>> _postGraphQlAuthenticated({
  required String email,
  required String query,
}) async {
  final bearer = await _bearerTokenForEmail(email);
  final client = HttpClient();
  try {
    final gqlUri = Uri.parse('$_apiOrigin/api/v2/graphql');
    final gqlRequest = await client.postUrl(gqlUri);
    gqlRequest.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    gqlRequest.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    gqlRequest.write(jsonEncode({'query': query}));
    final gqlResponse = await gqlRequest.close();
    final gqlBody = await gqlResponse.transform(utf8.decoder).join();
    if (gqlResponse.statusCode != HttpStatus.ok) {
      throw StateError(
        'GraphQL HTTP ${gqlResponse.statusCode} for $email: $gqlBody',
      );
    }
    final decoded = jsonDecode(gqlBody);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('GraphQL returned non-object for $email: $gqlBody');
    }
    return decoded;
  } finally {
    client.close(force: true);
  }
}

Future<String> _bearerTokenForEmail(String email) async {
  final client = HttpClient();
  try {
    final loginUri = Uri.parse('$_apiOrigin/api/v2/auth/email/test-login');
    final loginRequest = await client.postUrl(loginUri);
    loginRequest.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    loginRequest.write(jsonEncode({'email': email}));
    final loginResponse = await loginRequest.close();
    final loginBody = await loginResponse.transform(utf8.decoder).join();
    if (loginResponse.statusCode != HttpStatus.ok) {
      throw StateError(
        'test-login failed for $email: ${loginResponse.statusCode} $loginBody',
      );
    }

    final sessionCookie = _sessionCookieFromResponse(loginResponse);
    if (sessionCookie == null) {
      throw StateError('test-login did not set session cookie for $email');
    }

    final tokenUri = Uri.parse('$_apiOrigin/api/v2/session/access-token');
    final tokenRequest = await client.postUrl(tokenUri);
    tokenRequest.headers.set(HttpHeaders.cookieHeader, sessionCookie);
    final tokenResponse = await tokenRequest.close();
    final tokenBody = await tokenResponse.transform(utf8.decoder).join();
    if (tokenResponse.statusCode != HttpStatus.ok) {
      throw StateError(
        'access-token failed for $email: ${tokenResponse.statusCode} $tokenBody',
      );
    }
    final decoded = jsonDecode(tokenBody) as Map<String, dynamic>;
    final token = decoded['access_token'] as String?;
    if (token == null || token.isEmpty) {
      throw StateError('access-token missing for $email: $tokenBody');
    }
    return token;
  } finally {
    client.close(force: true);
  }
}

String? _sessionCookieFromResponse(HttpClientResponse response) {
  final setCookies = response.headers[HttpHeaders.setCookieHeader];
  if (setCookies == null) {
    return null;
  }
  for (final raw in setCookies) {
    final nameValue = raw.split(';').first.trim();
    if (nameValue.startsWith('$_sessionCookieName=')) {
      return nameValue;
    }
  }
  return null;
}

Future<void> _assertNoUncaughtFlutterErrors(
  Iterable<BrowserSession> sessions,
) async {
  final pattern = RegExp(
    'FlutterError|Another exception was thrown|Uncaught (?:Error|Exception)|DartError',
  );
  for (final session in sessions) {
    final logs = await session.readBrowserLogs();
    final uncaught = logs.where(
      (entry) => pattern.hasMatch(entry.message ?? ''),
    );
    if (uncaught.isNotEmpty) {
      throw StateError(
        '${session.name} had uncaught Flutter errors:\n${uncaught.join('\n')}',
      );
    }
  }
}

final class BrowserSession {
  BrowserSession._(this.name, this.driver, this._artifactDir);

  final String name;
  final WebDriver driver;
  final Directory _artifactDir;
  final _browserLogs = <LogEntry>[];
  final _performanceLogs = <LogEntry>[];

  static Future<BrowserSession> start(
    String name,
    Directory artifactDir,
  ) async {
    final driver = await createDriver(
      uri: Uri.parse(_driverUri),
      spec: WebDriverSpec.W3c,
      desired: {
        Capabilities.browserName: Browser.chrome,
        Capabilities.acceptInsecureCerts: true,
        Capabilities.chromeOptions: {
          'args': [
            '--headless=new',
            '--no-sandbox',
            '--disable-dev-shm-usage',
            '--window-size=500,1000',
          ],
        },
        'goog:loggingPrefs': {'browser': 'ALL', 'performance': 'ALL'},
      },
    );
    return BrowserSession._(name, driver, artifactDir);
  }

  Future<void> login(String email) async {
    await driver.get(_appOrigin);
    final result = await driver.executeAsync(
      '''
      const done = arguments[arguments.length - 1];
      fetch('/api/v2/auth/email/test-login', {
        method: 'POST',
        credentials: 'include',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({email: arguments[0]})
      }).then(async response => done({
        status: response.status,
        body: await response.text()
      })).catch(error => done({error: String(error)}));
    ''',
      [email],
    );
    if (result is! Map || result['status'] != HttpStatus.ok) {
      throw StateError('$name login failed: $result');
    }
    await driver.refresh();
    await waitForText(
      'My Work',
      timeout: const Duration(seconds: 45),
    );
  }

  Future<void> open(String path) async {
    final route = '#$path';
    await driver.get('$_appOrigin/$route');
    await _waitUntil(
      () async => (await driver.currentUrl).contains(path.split('?').first),
    );
  }

  Future<void> setTestId(String id, String value) async {
    late WebElement editable;
    await _waitUntil(() async {
      final result = await driver.execute(
        '''
        const wanted = arguments[0];
        const visible = element => {
          const style = window.getComputedStyle(element);
          const rect = element.getBoundingClientRect();
          return style.visibility !== 'hidden' && style.display !== 'none' &&
            rect.width > 0 && rect.height > 0;
        };
        const tagged = Array.from(document.querySelectorAll('*')).filter(
          element => Array.from(element.attributes || []).some(
            attr => attr.value === wanted,
          ) && visible(element),
        );
        for (const anchor of tagged) {
          const input = anchor.matches(
            'input:not([disabled]), textarea:not([disabled]), [contenteditable="true"]',
          ) ? anchor : anchor.querySelector(
            'input:not([disabled]), textarea:not([disabled]), [contenteditable="true"]',
          );
          if (input && visible(input)) return input;
        }
        return null;
      ''',
        [id],
      );
      if (result is! WebElement) return false;
      editable = result;
      return true;
    });
    await driver.execute('arguments[0].focus();', [editable]);
    await editable.clear();
    await editable.sendKeys(value);
  }

  Future<void> clickTestId(String id) async {
    final element = await waitForTestId(id);
    final resolved = await driver.execute(
      '''
      const element = arguments[0];
      if (element.matches('[flt-tappable], button, a')) return element;
      return element.querySelector('[flt-tappable], button, a') || element;
    ''',
      [element],
    );
    final target = resolved is WebElement ? resolved : element;
    try {
      await target.click();
    } on WebDriverException {
      await driver.execute('arguments[0].click();', [target]);
    }
  }

  Future<void> clickText(String text) async {
    late WebElement element;
    await _waitUntil(() async {
      final found = await _elementByText(text);
      if (found == null) return false;
      element = found;
      return true;
    });
    try {
      await element.click();
    } on WebDriverException {
      await driver.execute('arguments[0].click();', [element]);
    }
  }

  Future<WebElement> waitForTestId(String id) async {
    late WebElement element;
    await _waitUntil(() async {
      final found = await _elementByTestId(id);
      if (found == null) return false;
      element = found;
      return true;
    });
    return element;
  }

  Future<void> waitForTestIdDisabled(String id) => _waitUntil(() async {
    final element = await _elementByTestId(id);
    if (element == null) return false;
    return await driver.execute(
          '''
      const e = arguments[0];
      return e.getAttribute('aria-disabled') === 'true' ||
        e.hasAttribute('disabled') || e.disabled === true;
    ''',
          [element],
        ) ==
        true;
  });

  Future<bool> hasTestId(String id) async => await _elementByTestId(id) != null;

  Future<void> waitForTestIdText(String id, String text) =>
      _waitUntil(() => testIdTextContains(id, text));

  Future<bool> testIdTextContains(String id, String text) async {
    final element = await _elementByTestId(id);
    if (element == null) return false;
    return await driver.execute(
          '''
      const root = arguments[0];
      const wanted = arguments[1];
      const nodes = [root, ...root.querySelectorAll('*')];
      return nodes.some(element => {
        const value = element.getAttribute('aria-label') ||
          element.innerText || element.textContent || '';
        return value.includes(wanted);
      });
    ''',
          [element, text],
        ) ==
        true;
  }

  Future<WebElement?> _elementByTestId(String id) async {
    final result = await driver.execute(
      '''
      const wanted = arguments[0];
      const elements = Array.from(document.querySelectorAll('*'));
      for (const element of elements) {
        for (const attr of Array.from(element.attributes || [])) {
          if (attr.value === wanted) return element;
        }
      }
      return null;
    ''',
      [id],
    );
    return result is WebElement ? result : null;
  }

  Future<WebElement?> _elementByText(String text) async {
    final result = await driver.execute(
      '''
      const wanted = arguments[0];
      const visible = element => {
        const style = window.getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        return style.visibility !== 'hidden' && style.display !== 'none' &&
          rect.width > 0 && rect.height > 0;
      };
      const actionable = element => element?.closest(
        '[flt-tappable], button, a, [role="button"], [role="tab"]',
      ) || element;
      const elements = Array.from(document.querySelectorAll('*')).filter(visible);
      const aria = elements.find(element =>
        (element.getAttribute('aria-label') || '').trim() === wanted);
      if (aria) return actionable(aria);
      const ariaContaining = elements.filter(element =>
        (element.getAttribute('aria-label') || '').includes(wanted));
      ariaContaining.sort((a, b) =>
        (a.getAttribute('aria-label') || '').length -
        (b.getAttribute('aria-label') || '').length);
      if (ariaContaining.length) return actionable(ariaContaining[0]);
      const exact = elements.filter(element =>
        (element.innerText || element.textContent || '').trim() === wanted);
      exact.sort((a, b) => a.childElementCount - b.childElementCount);
      return actionable(exact[0]) || null;
    ''',
      [text],
    );
    return result is WebElement ? result : null;
  }

  Future<bool> hasText(String text) async =>
      await driver.execute(
        '''
        const wanted = arguments[0];
        const body = (document.body.innerText || document.body.textContent || '');
        if (body.includes(wanted)) return true;
        return Array.from(document.querySelectorAll('[aria-label]')).some(
          element => (element.getAttribute('aria-label') || '').includes(wanted));
      ''',
        [text],
      ) ==
      true;

  Future<void> waitForText(
    String text, {
    Duration timeout = const Duration(seconds: 45),
  }) => _waitUntil(() => hasText(text), timeout: timeout);

  Future<void> waitForTextGone(String text) =>
      _waitUntil(() async => !await hasText(text));

  Future<void> dismissSnackBar(String message) async {
    late WebElement closeButton;
    await _waitUntil(() async {
      final result = await driver.execute(
        '''
        const snackBar = Array.from(document.querySelectorAll('[aria-label]')).find(
          element => element.getAttribute('aria-label') === arguments[0],
        );
        return snackBar?.querySelector('[role="button"][aria-owns]') || null;
        ''',
        [message],
      );
      if (result is! WebElement) return false;
      closeButton = result;
      return true;
    });
    await closeButton.click();
  }

  Future<Set<String>> collectUpdatesReceiptIds() async {
    final result = await driver.execute(
      '''
      const prefix = 'updates-receipt-';
      const ids = [];
      const elements = Array.from(document.querySelectorAll('*'));
      for (const element of elements) {
        for (const attr of Array.from(element.attributes || [])) {
          if (attr.value && attr.value.startsWith(prefix)) {
            ids.push(attr.value.slice(prefix.length));
          }
        }
      }
      return ids;
    ''',
      [],
    );
    return (result as List).map((value) => value as String).toSet();
  }

  Future<int> receiptIdCount(String receiptId) async {
    final testId = 'updates-receipt-$receiptId';
    final result = await driver.execute(
      '''
      const wanted = arguments[0];
      let count = 0;
      const elements = Array.from(document.querySelectorAll('*'));
      for (const element of elements) {
        for (const attr of Array.from(element.attributes || [])) {
          if (attr.value === wanted) count++;
        }
      }
      return count;
    ''',
      [testId],
    );
    return (result as num).toInt();
  }

  Future<int?> readQaHeadRefreshLatencyMs() async {
    await readBrowserLogs();
    final pattern = RegExp(
      r'attention_event=head_refresh_latency latency_ms=(\d+)',
    );
    for (final entry in _browserLogs.reversed) {
      final message = entry.message ?? '';
      final match = pattern.firstMatch(message);
      if (match != null) {
        return int.parse(match.group(1)!);
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> postGraphQl(String query) async {
    final result = await driver.executeAsync(
      '''
      const done = arguments[arguments.length - 1];
      fetch('/api/v2/graphql', {
        method: 'POST',
        credentials: 'include',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({query: arguments[0]})
      }).then(async response => {
        const text = await response.text();
        try {
          return JSON.parse(text);
        } catch (_) {
          return {errors: [{message: text}], status: response.status};
        }
      }).then(body => done(body))
        .catch(error => done({errors: [{message: String(error)}]}));
    ''',
      [query],
    );
    if (result is! Map) {
      throw StateError('$name GraphQL failed: $result');
    }
    return result.cast<String, dynamic>();
  }

  Future<int> textCount(String text) async {
    final result = await driver.execute(
      '''
      const wanted = arguments[0];
      const elements = Array.from(document.querySelectorAll('*'));
      const valueOf = element =>
        element.getAttribute('aria-label') || element.innerText ||
          element.textContent || '';
      const containing = elements.filter(element =>
        valueOf(element).includes(wanted));
      return containing.filter(element =>
        !Array.from(element.querySelectorAll('*')).some(descendant =>
          valueOf(descendant).includes(wanted))).length;
    ''',
      [text],
    );
    return (result as num).toInt();
  }

  Future<void> sendChatMessage(String message) async {
    await setTestId('room.message.input', message);
    await clickTestId('room.message.send');
  }

  Future<void> setNetworkLatency(Duration latency) async {
    await _cdp('Network.enable', const {});
    await _cdp('Network.emulateNetworkConditions', {
      'offline': false,
      'latency': latency.inMilliseconds,
      'downloadThroughput': -1,
      'uploadThroughput': -1,
      'connectionType': 'wifi',
    });
  }

  Future<void> blockGraphql(bool blocked) async {
    await _cdp('Network.enable', const {});
    await _cdp('Network.setBlockedURLs', {
      'urls': blocked ? ['*api/v2/graphql*'] : <String>[],
    });
  }

  Future<dynamic> _cdp(String command, Map<String, dynamic> params) => driver
      .postRequest('goog/cdp/execute', {'cmd': command, 'params': params});

  Future<List<LogEntry>> readBrowserLogs() async {
    _browserLogs.addAll(await driver.logs.get(LogType.browser).toList());
    return List.unmodifiable(_browserLogs);
  }

  Future<void> captureFailure() async {
    try {
      File('${_artifactDir.path}/$name-failure.png').writeAsBytesSync(
        await driver.captureScreenshotAsList(),
      );
    } catch (_) {}
    try {
      File('${_artifactDir.path}/$name-page.html').writeAsStringSync(
        await driver.pageSource,
      );
    } catch (_) {}
  }

  Future<void> finish() async {
    try {
      await readBrowserLogs();
      _performanceLogs.addAll(
        await driver.logs.get(LogType.performance).toList(),
      );
      File('${_artifactDir.path}/$name-browser.log').writeAsStringSync(
        _browserLogs.join('\n'),
      );
      File('${_artifactDir.path}/$name-network.log').writeAsStringSync(
        _performanceLogs.join('\n'),
      );
    } finally {
      await driver.quit();
    }
  }
}

final class Fixture {
  const Fixture({
    required this.authorEmail,
    required this.authorUserId,
    required this.helperEmail,
    required this.helperUserId,
  });

  final String authorEmail;
  final String authorUserId;
  final String helperEmail;
  final String helperUserId;
}

final class SocketControlResult {
  const SocketControlResult({
    required this.suspended,
    required this.sessionsClosed,
  });

  final bool suspended;
  final int sessionsClosed;
}
