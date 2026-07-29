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
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_body.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
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
  final dump = _screenDump();
  throw TimeoutException('Timed out waiting for condition. $dump');
}

/// Current route, HUD author actions, and on-screen texts for timeout reports.
String _screenDump() {
  final texts = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data ?? '<rich>')
      .where((t) => t.trim().isNotEmpty)
      .take(40)
      .join(' | ');
  final hudKeys = <String>[];
  for (final action in [
    'resolveBlocker',
    'reviewOffers',
    'markEnoughHelp',
    'wrapUpForReview',
    'reviewContributions',
    'closeNow',
    'forward',
  ]) {
    final f = find.byKey(TestIds.key(TestIds.beaconHudAuthorAction(action)));
    if (finderHasMatch(f)) hudKeys.add(action);
  }
  String url = '?';
  try {
    url = GetIt.I<RootRouter>().currentUrl;
  } catch (_) {}
  return 'url=$url hud=[${hudKeys.join(',')}] texts: $texts';
}

/// `.first`-style finders throw StateError instead of returning an empty set.
bool finderHasMatch(Finder finder) {
  try {
    return finder.evaluate().isNotEmpty;
  } on StateError {
    return false;
  }
}

Future<void> pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) => pumpUntil(tester, () => finderHasMatch(finder), timeout: timeout);

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  // finder.description, not $finder: toString() evaluates the finder and
  // throws "Bad state: No element" for empty `.first`-style finders.
  debugPrint('[e2e] tapAndSettle(${finder.description})');
  await pumpUntilVisible(tester, finder);
  // Long scrollables (e.g. the evaluation sheet) can keep the target off
  // screen; ensureVisible is a no-op without a Scrollable ancestor.
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
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
    find.byKey(TestIds.key(TestIds.helpOfferMessage)),
    'I can help with software',
  );
  await tester.pumpAndSettle();
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.helpOfferBrowseCategories)),
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

Future<bool> tryPumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    await pumpUntil(
      tester,
      () => finder.evaluate().isNotEmpty,
      timeout: timeout,
    );
    return true;
  } on TimeoutException {
    return false;
  }
}

Future<void> acceptHelpOffer(
  WidgetTester tester, {
  required IntegrationFixture fixture,
  required String requestTitle,
}) async {
  await loginAs(tester, fixture.authorEmail);
  await openRequestFromMyWork(tester, requestTitle: requestTitle);
  final peopleTab = find.byKey(TestIds.key(TestIds.beaconTabPeople));
  if (await tryPumpUntilVisible(tester, peopleTab)) {
    await tapAndSettle(tester, peopleTab.first);
  }
  final accept = find.byKey(
    TestIds.key(TestIds.helpOfferAccept(fixture.helperUserId)),
  );
  final remove = find.byKey(
    TestIds.key(TestIds.helpOfferRemove(fixture.helperUserId)),
  );
  // Direct-forward recipients are auto-admitted (admit/decline
  // simplification): their card shows only "Remove from chat". Treat an
  // already-admitted helper as accepted.
  await pumpUntil(
    tester,
    () => accept.evaluate().isNotEmpty || remove.evaluate().isNotEmpty,
  );
  if (accept.evaluate().isNotEmpty) {
    await tapAndSettle(tester, accept);
  } else {
    debugPrint('[e2e] acceptHelpOffer: already admitted (auto-admit)');
  }
}

Future<void> removeHelperFromChat(
  WidgetTester tester, {
  required IntegrationFixture fixture,
}) async {
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.helpOfferRemove(fixture.helperUserId))),
  );
  // Remove opens HelpOfferAdmissionReasonDialog; a non-empty reason enables OK.
  final reasonField = find.byKey(TestIds.key(TestIds.admissionReasonInput));
  await pumpUntilVisible(tester, reasonField);
  await tester.enterText(reasonField, 'Integration cleanup');
  await tester.pumpAndSettle();
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.admissionReasonSubmit)),
  );
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

Finder _hudAction(String action) =>
    find.byKey(TestIds.key(TestIds.beaconHudAuthorAction(action)));

Future<void> closeRequestAndOpenReview(WidgetTester tester) async {
  // The author closes via the operational HUD primary action (not the overflow
  // menu). The HUD is a small state machine that depends on closure readiness:
  //   markEnoughHelp → wrapUpForReview → (close) → reviewContributions.
  // Drive it until the review screen is reached, handling whichever action the
  // HUD currently offers.
  await pumpUntil(
    tester,
    () =>
        finderHasMatch(_hudAction('markEnoughHelp')) ||
        finderHasMatch(_hudAction('wrapUpForReview')) ||
        finderHasMatch(_hudAction('reviewContributions')),
    timeout: const Duration(seconds: 30),
  );

  if (finderHasMatch(_hudAction('markEnoughHelp'))) {
    await tapAndSettle(tester, _hudAction('markEnoughHelp').first);
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.beaconHudMarkEnoughHelpConfirm)),
    );
    await pumpUntilVisible(
      tester,
      _hudAction('wrapUpForReview'),
      timeout: const Duration(seconds: 30),
    );
  }

  await tapAndSettle(tester, _hudAction('wrapUpForReview').first);
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.beaconCloseConfirm)).first,
  );

  // Close completes → review window opens → HUD offers review contributions.
  await pumpUntilVisible(
    tester,
    _hudAction('reviewContributions'),
    timeout: const Duration(seconds: 30),
  );
  await tapAndSettle(tester, _hudAction('reviewContributions').first);

  await pumpUntilVisible(
    tester,
    find.byKey(TestIds.key(TestIds.evaluationSubmit)),
  );
}

Future<void> reviewParticipant(
  WidgetTester tester,
  String userId, {
  // EvaluationTrustSelection.name of the category to pick; `zero` needs no
  // intensity step and no reason tag, so Save succeeds right away.
  String trustOption = 'zero',
}) async {
  final tile = find.byKey(TestIds.key(TestIds.evaluationParticipant(userId)));
  if (tile.evaluate().isEmpty) {
    return;
  }
  await tapAndSettle(tester, tile.first);
  // The trust control validates on Save: a completed selection is required
  // before the sheet closes.
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.evaluationTrustOption(trustOption))),
  );
  final saveButton = find.byKey(TestIds.key(TestIds.evaluationSave));
  await tapAndSettle(tester, saveButton);
  // The sheet pops only when the save round-trip succeeded.
  await pumpUntil(tester, () => saveButton.evaluate().isEmpty);
}

/// Bounded pumps for screens with repeating animations (e.g. the trust graph).
Future<void> pumpBounded(
  WidgetTester tester, {
  int frames = 4,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

String currentAppUrl() => GetIt.I<RootRouter>().currentUrl;

Future<String> ensureQaUserId(WidgetTester tester, String email) async {
  await loginAs(tester, email);
  final userId = GetIt.I<AuthCubit>().state.currentAccountId;
  await logout(tester);
  return userId;
}

Future<void> userSubscribe(String objectUserId) async {
  await _postGraphQl(
    'mutation { userSubscribe(objectId: "$objectUserId") }',
  );
}

Future<void> openConnectionsGraph(WidgetTester tester, String profileId) async {
  await goToPath(tester, '$kPathGraph/$profileId');
  await pumpUntilVisible(
    tester,
    find.byKey(TestIds.key(TestIds.graphResetToEgo)),
  );
  await pumpBounded(tester, frames: 12);
}

Future<void> waitForGraphReady(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  await pumpUntil(
    tester,
    () {
      final cubit = readGraphCubit(tester);
      return !cubit.state.isLoading;
    },
    timeout: timeout,
  );
  await pumpBounded(tester);
}

NodeDetails? graphNodeById(WidgetTester tester, String userId) {
  for (final node in readGraphCubit(tester).graphController.nodes) {
    if (node.id == userId) {
      return node;
    }
  }
  return null;
}

Future<NodeDetails> waitForGraphNeighbor(WidgetTester tester) async {
  await pumpUntil(
    tester,
    () => find.byType(GraphNodeWidget).evaluate().length > 1,
    timeout: const Duration(seconds: 45),
  );
  final meId = readGraphCubit(tester).state.me.id;
  return tester
      .widgetList<GraphNodeWidget>(find.byType(GraphNodeWidget))
      .firstWhere(
        (node) => node.nodeDetails.id != meId,
      )
      .nodeDetails;
}

Future<void> waitForGraphNode(
  WidgetTester tester,
  String userId, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  await pumpUntil(
    tester,
    () => graphNodeById(tester, userId) != null,
    timeout: timeout,
  );
}

Future<void> selectGraphNode(WidgetTester tester, String userId) async {
  await waitForGraphNode(tester, userId);
  final node = graphNodeById(tester, userId);
  if (node == null) {
    throw StateError('graph node $userId is not rendered');
  }

  final cubit = readGraphCubit(tester);
  // Canvas transforms make widget geometry unsuitable for browser automation.
  // The integration still uses the running app's cubit and visible controls.
  cubit.selectNode(node);
  await pumpBounded(tester);
  debugPrint('[e2e] selectGraphNode($userId): focus=${cubit.state.focus}');
}

Future<String> selectGraphNeighbor(WidgetTester tester) async {
  final helperLabel = find.textContaining('IT helper');
  await pumpUntilVisible(
    tester,
    helperLabel,
    timeout: const Duration(seconds: 45),
  );
  await tester.tap(helperLabel.first);
  await pumpBounded(tester);
  return readGraphCubit(tester).state.focus;
}

Future<void> expandFocusedGraphNode(WidgetTester tester) async {
  final expand = find.byKey(TestIds.key(TestIds.graphExpand));
  await pumpUntilVisible(tester, expand);
  await tester.tap(expand);
  await pumpBounded(tester, frames: 12);
  debugPrint(
    '[e2e] expandFocusedGraphNode: focus=${readGraphCubit(tester).state.focus}',
  );
}

Future<void> tapGraphBack(WidgetTester tester) async {
  await tapGraphControl(
    tester,
    find.byKey(TestIds.key(TestIds.graphBack)),
  );
}

Future<void> tapGraphResetToEgo(WidgetTester tester) async {
  await tapGraphControl(
    tester,
    find.byKey(TestIds.key(TestIds.graphResetToEgo)),
  );
}

Future<void> tapGraphControl(WidgetTester tester, Finder finder) async {
  await pumpUntilVisible(tester, finder);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await pumpBounded(tester);
}

GraphCubit readGraphCubit(WidgetTester tester) =>
    tester.element(find.byType(GraphBody)).read<GraphCubit>();

Future<Map<String, dynamic>> _postGraphQl(String query) async {
  return _postJson(
    '/api/v2/graphql',
    {'query': query},
    includeCredentials: true,
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
