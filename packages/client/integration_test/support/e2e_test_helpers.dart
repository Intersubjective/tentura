import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/coordination_item/ui/widget/coordination_item_overflow_menu.dart';
import 'package:tentura/ui/test_ids.dart';

class IntegrationFixture {
  const IntegrationFixture({
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

String uniqueRunId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';

String uniqueRequestTitle(String prefix) =>
    '$prefix ${DateTime.now().microsecondsSinceEpoch}';

/// Starts the real app, then restores the error handlers `flutter_test`
/// installed. The app's boot path overrides [FlutterError.onError] (and
/// friends); if they stay overridden, the test binding's failure reporting
/// asserts (binding.dart `_pendingExceptionDetails`) and a failing test hangs
/// `flutter drive` forever instead of failing cleanly.
Future<void> launchApp(Future<void> Function() start) async {
  final originalOnError = FlutterError.onError;
  final originalPlatformOnError = PlatformDispatcher.instance.onError;
  final originalErrorWidgetBuilder = ErrorWidget.builder;
  await start();
  FlutterError.onError = originalOnError;
  PlatformDispatcher.instance.onError = originalPlatformOnError;
  ErrorWidget.builder = originalErrorWidgetBuilder;
}

Future<IntegrationFixture> bootstrapFixture({
  required String runId,
}) async {
  final result = await _postJson(
    '/_qa/integration/bootstrap',
    {'runId': runId},
    includeCredentials: false,
    extraHeaders: _qaHeaders,
  );
  return IntegrationFixture(
    authorEmail: result['authorEmail']! as String,
    authorUserId: result['authorUserId']! as String,
    helperEmail: result['helperEmail']! as String,
    helperUserId: result['helperUserId']! as String,
  );
}

Future<void> loginAs(WidgetTester tester, String email) async {
  debugPrint('[e2e] loginAs($email): posting test-login');
  await _postJson(
    '/api/v2/auth/email/test-login',
    {'email': email},
    includeCredentials: true,
  );
  debugPrint('[e2e] loginAs($email): bootstrapping session');
  await GetIt.I<AuthCase>().tryBootstrapSession();
  await pumpUntil(
    tester,
    () => GetIt.I<AuthCubit>().state.currentAccountId.isNotEmpty,
  );
  debugPrint('[e2e] loginAs($email): done');
}

Future<void> logout(WidgetTester tester) async {
  final accountId = GetIt.I<AuthCubit>().state.currentAccountId;
  debugPrint('[e2e] logout: currentAccountId="$accountId"');
  if (accountId.isEmpty) {
    return;
  }
  await GetIt.I<AuthCubit>().signOut();
  debugPrint('[e2e] logout: signOut returned');
  await pumpUntil(
    tester,
    () => GetIt.I<AuthCubit>().state.currentAccountId.isEmpty,
  );
  debugPrint('[e2e] logout: done');
}

Future<void> goToPath(WidgetTester tester, String path) async {
  debugPrint('[e2e] goToPath($path)');
  final router = GetIt.I<RootRouter>();
  // navigatePath is idempotent (pops back to the route when it is already in
  // the stack, pushes otherwise) — pushPath silently no-ops when e.g. a Home
  // tab shell is active. includePrefixMatches is required for nested paths.
  // Don't await the Future (push-like futures resolve on pop, see
  // beacon_view_screen.dart); pump until the URL reflects the navigation.
  unawaited(router.navigatePath(path, includePrefixMatches: true));
  await pumpUntil(tester, () => router.currentUrl.startsWith(path));
  debugPrint('[e2e] goToPath($path): done (url=${router.currentUrl})');
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration step = const Duration(milliseconds: 200),
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(step);
    if (condition()) {
      return;
    }
  }
  throw TimeoutException('Timed out waiting for condition');
}

Future<void> pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) => pumpUntil(tester, () => finder.evaluate().isNotEmpty, timeout: timeout);

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  // finder.description, not $finder: toString() evaluates the finder and
  // throws "Bad state: No element" for empty `.first`-style finders.
  debugPrint('[e2e] tapAndSettle(${finder.description})');
  await pumpUntilVisible(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  debugPrint('[e2e] tapAndSettle(${finder.description}): done');
}

Future<void> dismissOkDialogIfPresent(WidgetTester tester) async {
  final okFinder = find.text('OK');
  if (okFinder.evaluate().isNotEmpty) {
    await tester.tap(okFinder.first);
    await tester.pumpAndSettle();
  }
}

Future<String> createAndForwardRequest(
  WidgetTester tester, {
  required IntegrationFixture fixture,
  required String title,
}) async {
  await loginAs(tester, fixture.authorEmail);
  await goToPath(tester, kPathBeaconNew);

  final titleField = find.byKey(TestIds.key(TestIds.requestTitle));
  await pumpUntilVisible(tester, titleField);
  debugPrint('[e2e] create: entering title');
  await tester.enterText(titleField, title);
  await tester.enterText(
    find.byKey(TestIds.key(TestIds.requestDescription)),
    'Integration test request for $title',
  );
  await tester.pumpAndSettle();

  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.requestRecipientsTab)),
  );

  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.forwardRecipient(fixture.helperUserId))),
  );
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.forwardSubmit)),
  );
  await dismissOkDialogIfPresent(tester);

  await goToPath(tester, kPathMyWork);
  await pumpUntilVisible(tester, find.text(title));
  return title;
}

Future<void> offerHelpFromInbox(
  WidgetTester tester, {
  required IntegrationFixture fixture,
  required String requestTitle,
}) async {
  await loginAs(tester, fixture.helperEmail);
  await goToPath(tester, kPathInbox);
  await pumpUntilVisible(tester, find.text(requestTitle));
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.inboxOfferHelp)).first,
  );
  await tester.enterText(
    find.byKey(TestIds.key(TestIds.helpOfferSearch)),
    'software',
  );
  await tester.pumpAndSettle();
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.capabilityChip('software'))).first,
  );
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.helpOfferSubmit)),
  );
}

Future<void> openRequestFromMyWork(
  WidgetTester tester, {
  required String requestTitle,
}) async {
  await goToPath(tester, kPathMyWork);
  await tapAndSettle(tester, find.text(requestTitle).first);
}

Future<void> openRequestFromInbox(
  WidgetTester tester, {
  required String requestTitle,
}) async {
  await goToPath(tester, kPathInbox);
  await tapAndSettle(tester, find.text(requestTitle).first);
}

Future<void> acceptHelpOffer(
  WidgetTester tester, {
  required IntegrationFixture fixture,
  required String requestTitle,
}) async {
  await loginAs(tester, fixture.authorEmail);
  await openRequestFromMyWork(tester, requestTitle: requestTitle);
  final peopleTab = find.byKey(TestIds.key(TestIds.beaconTabPeople));
  if (peopleTab.evaluate().isNotEmpty) {
    await tapAndSettle(tester, peopleTab.first);
  }
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.helpOfferAccept(fixture.helperUserId))),
  );
}

Future<void> removeHelperFromChat(
  WidgetTester tester, {
  required IntegrationFixture fixture,
}) async {
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.helpOfferRemove(fixture.helperUserId))),
  );
  await tester.enterText(
    find.byType(TextField).last,
    'Integration cleanup',
  );
  await tapAndSettle(tester, find.text('OK').last);
}

Future<void> enterChatIfNeeded(WidgetTester tester) async {
  final messageInput = find.byKey(TestIds.key(TestIds.roomMessageInput));
  if (messageInput.evaluate().isNotEmpty) {
    return;
  }
  final chatTab = find.byKey(TestIds.key(TestIds.beaconRoomOpen));
  if (chatTab.evaluate().isEmpty) {
    throw StateError('Room entry control not found');
  }
  await tapAndSettle(tester, chatTab.first);
  await pumpUntilVisible(tester, messageInput);
}

Future<void> sendRoomMessage(WidgetTester tester, String text) async {
  await enterChatIfNeeded(tester);
  await tester.enterText(
    find.byKey(TestIds.key(TestIds.roomMessageInput)),
    text,
  );
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.roomMessageSend)),
  );
}

Future<void> enterItemsIfNeeded(WidgetTester tester) async {
  final askButton = find.byKey(TestIds.key(TestIds.coordinationAskCreate));
  if (askButton.evaluate().isNotEmpty) {
    return;
  }
  final itemsTab = find.byKey(TestIds.key(TestIds.beaconTabItems));
  if (itemsTab.evaluate().isEmpty) {
    throw StateError('Items tab not found');
  }
  await tapAndSettle(tester, itemsTab.first);
  await pumpUntilVisible(tester, askButton);
}

Future<void> createCoordinationItem(
  WidgetTester tester, {
  required String launcherId,
  required String title,
  required String body,
}) async {
  await enterItemsIfNeeded(tester);
  await tapAndSettle(tester, find.byKey(TestIds.key(launcherId)));
  await pumpUntilVisible(
    tester,
    find.byKey(TestIds.key(TestIds.coordinationComposerBody)),
  );

  final titleFinder = find.byKey(
    TestIds.key(TestIds.coordinationComposerTitle),
  );
  if (titleFinder.evaluate().isNotEmpty) {
    await tester.enterText(titleFinder, title);
  }
  await tester.enterText(
    find.byKey(TestIds.key(TestIds.coordinationComposerBody)),
    body,
  );
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.coordinationComposerSubmit)),
  );
}

Future<void> resolveFirstCoordinationItem(WidgetTester tester) async {
  await enterItemsIfNeeded(tester);
  final menu = find
      .byType(
        PopupMenuButton<CoordinationItemCardMenuAction>,
      )
      .first;
  await tapAndSettle(tester, menu);
  await tapAndSettle(tester, find.text('Resolve').last);
}

Future<void> closeRequestAndOpenReview(WidgetTester tester) async {
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.beaconOverflowMenu)).first,
  );
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.beaconOverflowClose)).first,
  );
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.beaconCloseConfirm)).first,
  );
  await pumpUntilVisible(
    tester,
    find.byKey(TestIds.key(TestIds.evaluationSubmit)),
  );
}

Future<void> reviewParticipant(WidgetTester tester, String userId) async {
  final tile = find.byKey(TestIds.key(TestIds.evaluationParticipant(userId)));
  if (tile.evaluate().isEmpty) {
    return;
  }
  await tapAndSettle(tester, tile.first);
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.evaluationSave)),
  );
}

Future<Map<String, dynamic>> _postJson(
  String path,
  Map<String, Object?> body, {
  required bool includeCredentials,
  Map<String, String> extraHeaders = const {},
}) async {
  final headers = web.Headers();
  headers
    ..set('Content-Type', 'application/json')
    ..set('Accept', 'application/json');
  for (final entry in extraHeaders.entries) {
    headers.set(entry.key, entry.value);
  }

  final init = web.RequestInit(
    method: 'POST',
    credentials: includeCredentials ? 'include' : 'same-origin',
    headers: headers,
    body: jsonEncode(body).toJS,
  );
  final response = await web.window
      .fetch(
        Uri.base.resolve(path).toString().toJS,
        init,
      )
      .toDart;
  final text = (await response.text().toDart).toDart;
  if (response.status < 200 || response.status >= 300) {
    throw StateError('POST $path failed (${response.status}): $text');
  }
  return (jsonDecode(text) as Map).cast<String, dynamic>();
}

Map<String, String> get _qaHeaders {
  const token = String.fromEnvironment('QA_AUTH_TOKEN');
  if (token.isEmpty) {
    throw StateError('QA_AUTH_TOKEN dart-define is required');
  }
  return {'Authorization': 'Bearer $token'};
}
