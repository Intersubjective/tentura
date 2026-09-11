// ignore_for_file: tentura_lints/no_raw_graphql_in_dart
// Shared WebDriver session helpers for multiclient browser proofs.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:webdriver/async_io.dart' hide TimeoutException;

const multiclientAppOrigin = 'https://dev.lvh.me:9443';
const multiclientApiOrigin = 'http://127.0.0.1:2080';
const multiclientDriverUri = 'http://127.0.0.1:4444/';
const multiclientSessionCookieName = '__Host-tentura_session';

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
      uri: Uri.parse(multiclientDriverUri),
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
    await driver.get(multiclientAppOrigin);
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
    await driver.get('$multiclientAppOrigin/$route');
    await waitUntil(
      () async => (await driver.currentUrl).contains(path.split('?').first),
    );
  }

  Future<void> setTestId(String id, String value) async {
    late WebElement editable;
    await waitUntil(() async {
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
    await waitUntil(() async {
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
    await waitUntil(() async {
      final found = await _elementByTestId(id);
      if (found == null) return false;
      element = found;
      return true;
    });
    return element;
  }

  Future<void> waitForTestIdDisabled(String id) => waitUntil(() async {
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
      waitUntil(() => testIdTextContains(id, text));

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
  }) => waitUntil(() => hasText(text), timeout: timeout);

  Future<void> waitForTextGone(String text) =>
      waitUntil(() async => !await hasText(text));

  Future<void> dismissSnackBar(String message) async {
    late WebElement closeButton;
    await waitUntil(() async {
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
    final fromWindow = await driver.execute(
      'return window.__tenturaQaHeadRefreshLatencyMs ?? null;',
      [],
    );
    if (fromWindow is num) {
      return fromWindow.toInt();
    }
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

Future<int> measureUntil(
  FutureOr<bool> Function() condition, {
  required Duration timeout,
}) async {
  final stopwatch = Stopwatch()..start();
  await waitUntil(condition, timeout: timeout);
  return stopwatch.elapsedMilliseconds;
}

Future<void> waitUntil(
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

void requireTruth(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<Fixture> bootstrapFixture(String token, String runId) async {
  final response = await http.post(
    Uri.parse('$multiclientApiOrigin/_qa/integration/bootstrap'),
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

Future<SocketControlResult> controlRealtimeSocket(
  String token,
  String userId, {
  required String action,
}) async {
  final response = await http.post(
    Uri.parse('$multiclientApiOrigin/_qa/integration/realtime-socket'),
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

String escapeGraphQlString(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

Future<String> createBeaconViaApi({
  required String authorEmail,
  required String title,
}) async {
  final query =
      'mutation { beaconCreate(title: "${escapeGraphQlString(title)}", description: "${escapeGraphQlString(title)}", draft: false) { id } }';
  final response = await postGraphQlAuthenticated(
    email: authorEmail,
    query: query,
  );
  final errors = response['errors'];
  if (errors != null) {
    throw StateError('beaconCreate failed: $errors');
  }
  final data = response['data'] as Map<String, dynamic>?;
  final beaconCreate = data?['beaconCreate'] as Map<String, dynamic>?;
  final id = beaconCreate?['id'] as String?;
  if (id == null || id.isEmpty) {
    throw StateError('beaconCreate returned no id: $response');
  }
  return id;
}

Future<void> forwardBeaconViaApi({
  required String authorEmail,
  required String beaconId,
  required String recipientId,
}) async {
  final query =
      'mutation { beaconForward(id: "$beaconId", recipientIds: ["$recipientId"]) { deliveredRecipientIds } }';
  final response = await postGraphQlAuthenticated(
    email: authorEmail,
    query: query,
  );
  final errors = response['errors'];
  if (errors != null) {
    throw StateError('beaconForward failed: $errors');
  }
  final data = response['data'] as Map<String, dynamic>?;
  final beaconForward = data?['beaconForward'] as Map<String, dynamic>?;
  final delivered =
      (beaconForward?['deliveredRecipientIds'] as List?)?.cast<String>() ??
      const <String>[];
  if (!delivered.contains(recipientId)) {
    throw StateError('beaconForward did not deliver to recipient: $response');
  }
}

Future<void> _offerHelpViaApi({
  required String helperEmail,
  required String beaconId,
  required String message,
}) async {
  final query =
      'mutation { beaconOfferHelp(id: "$beaconId", message: "${escapeGraphQlString(message)}") }';
  final response = await postGraphQlAuthenticated(
    email: helperEmail,
    query: query,
  );
  final errors = response['errors'];
  if (errors != null) {
    throw StateError('beaconOfferHelp failed: $errors');
  }
  final data = response['data'] as Map<String, dynamic>?;
  if (data?['beaconOfferHelp'] != true) {
    throw StateError('beaconOfferHelp did not succeed: $response');
  }
}

Future<void> _acceptHelpOfferViaApi({
  required String authorEmail,
  required String beaconId,
  required String offerUserId,
}) async {
  final query =
      'mutation { acceptHelpOffer(id: "$beaconId", offerUserId: "$offerUserId") { beaconId } }';
  final response = await postGraphQlAuthenticated(
    email: authorEmail,
    query: query,
  );
  final errors = response['errors'];
  if (errors != null) {
    throw StateError('acceptHelpOffer failed: $errors');
  }
  final data = response['data'] as Map<String, dynamic>?;
  final acceptHelpOffer = data?['acceptHelpOffer'] as Map<String, dynamic>?;
  if (acceptHelpOffer?['beaconId'] != beaconId) {
    throw StateError('acceptHelpOffer did not resolve: $response');
  }
}

Future<String> _createPublishedChildViaApi({
  required String helperEmail,
  required String parentBeaconId,
  required String title,
  required String clientCommandId,
}) async {
  final query =
      'mutation { beaconChildCreate(parentBeaconId: "$parentBeaconId", '
      'clientCommandId: "$clientCommandId", '
      'title: "${escapeGraphQlString(title)}", '
      'description: "${escapeGraphQlString(title)}", draft: false) '
      '{ outcome beaconId } }';
  final response = await postGraphQlAuthenticated(
    email: helperEmail,
    query: query,
  );
  final errors = response['errors'];
  if (errors != null) {
    throw StateError('beaconChildCreate failed: $errors');
  }
  final data = response['data'] as Map<String, dynamic>?;
  final result = data?['beaconChildCreate'] as Map<String, dynamic>?;
  final beaconId = result?['beaconId'] as String?;
  if (beaconId == null || beaconId.isEmpty) {
    throw StateError('beaconChildCreate returned no beaconId: $response');
  }
  return beaconId;
}

Future<Map<String, dynamic>> postGraphQlAuthenticated({
  required String email,
  required String query,
}) async {
  final bearer = await bearerTokenForEmail(email);
  final client = HttpClient();
  try {
    final gqlUri = Uri.parse('$multiclientApiOrigin/api/v2/graphql');
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

Future<String> bearerTokenForEmail(String email) async {
  final client = HttpClient();
  try {
    final loginUri = Uri.parse('$multiclientApiOrigin/api/v2/auth/email/test-login');
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

    final sessionCookie = sessionCookieFromResponse(loginResponse);
    if (sessionCookie == null) {
      throw StateError('test-login did not set session cookie for $email');
    }

    final tokenUri = Uri.parse('$multiclientApiOrigin/api/v2/session/access-token');
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

String? sessionCookieFromResponse(HttpClientResponse response) {
  final setCookies = response.headers[HttpHeaders.setCookieHeader];
  if (setCookies == null) {
    return null;
  }
  for (final raw in setCookies) {
    final nameValue = raw.split(';').first.trim();
    if (nameValue.startsWith('$multiclientSessionCookieName=')) {
      return nameValue;
    }
  }
  return null;
}

Future<List<Map<String, dynamic>>> fetchConstellationAnchorsViaApi({
  required String email,
  bool showClosed = false,
  bool participatedOnly = false,
}) async {
  final response = await postGraphQlAuthenticated(
    email: email,
    query:
        'query { constellationField(showClosed: $showClosed, participatedOnly: $participatedOnly, projection: ANCHORS) { anchorProjection { revision anchors { targetKind targetId xUnits yUnits coordinateSpaceVersion revision } } } }',
  );
  final errors = response['errors'];
  if (errors != null) {
    throw StateError('constellationField failed: $errors');
  }
  final data = response['data'] as Map<String, dynamic>?;
  final field = data?['constellationField'] as Map<String, dynamic>?;
  final projection = field?['anchorProjection'] as Map<String, dynamic>?;
  final anchors =
      (projection?['anchors'] as List?)?.cast<Map<String, dynamic>>() ??
      const <Map<String, dynamic>>[];
  return anchors;
}

Future<Map<String, dynamic>> upsertConstellationAnchorViaApi({
  required String email,
  required String targetKind,
  required String targetId,
  required double xUnits,
  required double yUnits,
  int coordinateSpaceVersion = 1,
}) async {
  final response = await postGraphQlAuthenticated(
    email: email,
    query:
        'mutation { constellationAnchorUpsert(targetKind: $targetKind, targetId: "$targetId", xUnits: $xUnits, yUnits: $yUnits, coordinateSpaceVersion: $coordinateSpaceVersion) { anchor { targetKind targetId xUnits yUnits coordinateSpaceVersion revision } revision } }',
  );
  final errors = response['errors'];
  if (errors != null) {
    throw StateError('constellationAnchorUpsert failed: $errors');
  }
  final data = response['data'] as Map<String, dynamic>?;
  final result = data?['constellationAnchorUpsert'] as Map<String, dynamic>?;
  final anchor = result?['anchor'] as Map<String, dynamic>?;
  if (anchor == null) {
    throw StateError('constellationAnchorUpsert returned no anchor: $response');
  }
  return anchor;
}

Future<void> deleteConstellationAnchorViaApi({
  required String email,
  required String targetKind,
  required String targetId,
}) async {
  final response = await postGraphQlAuthenticated(
    email: email,
    query:
        'mutation { constellationAnchorDelete(targetKind: $targetKind, targetId: "$targetId") { targetKind targetId revision } }',
  );
  final errors = response['errors'];
  if (errors != null) {
    throw StateError('constellationAnchorDelete failed: $errors');
  }
}

Map<String, dynamic>? anchorByTarget(
  List<Map<String, dynamic>> anchors, {
  required String targetKind,
  required String targetId,
}) {
  for (final anchor in anchors) {
    if (anchor['targetKind'] == targetKind && anchor['targetId'] == targetId) {
      return anchor;
    }
  }
  return null;
}

Future<void> assertNoUncaughtFlutterErrors(
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

