import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/widget/item_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_body.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';

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

/// Four-role witness-admission fixture (G3b): Alice/Eve are separate egos
/// who each mutually befriend Carol; Alice alone casts a one-way explicit
/// vouch for Bob (Bob does not vouch back). See
/// `QaIntegrationController.witnessFixture` for the exact server-side
/// construction.
class IntegrationWitnessFixture {
  const IntegrationWitnessFixture({
    required this.aliceEmail,
    required this.aliceUserId,
    required this.bobEmail,
    required this.bobUserId,
    required this.carolEmail,
    required this.carolUserId,
    required this.eveEmail,
    required this.eveUserId,
  });

  final String aliceEmail;
  final String aliceUserId;
  final String bobEmail;
  final String bobUserId;
  final String carolEmail;
  final String carolUserId;
  final String eveEmail;
  final String eveUserId;
}

Future<IntegrationWitnessFixture> bootstrapWitnessFixture({
  required String runId,
}) async {
  final result = await _postJson(
    '/_qa/integration/witness-fixture',
    {'runId': runId},
    includeCredentials: false,
    extraHeaders: _qaHeaders,
  );
  return IntegrationWitnessFixture(
    aliceEmail: result['aliceEmail']! as String,
    aliceUserId: result['aliceUserId']! as String,
    bobEmail: result['bobEmail']! as String,
    bobUserId: result['bobUserId']! as String,
    carolEmail: result['carolEmail']! as String,
    carolUserId: result['carolUserId']! as String,
    eveEmail: result['eveEmail']! as String,
    eveUserId: result['eveUserId']! as String,
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
  //
  // Browse details are root routes. A cold direct link builds its semantic
  // Home source below the detail; warm navigation pushes the root detail above
  // the already-mounted Home tab. The URL therefore remains [path].
  unawaited(router.navigatePath(path, includePrefixMatches: true));
  await pumpUntil(tester, () => router.currentUrl.contains(path));
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

/// Adds the user-action phase to asynchronous browser-test timeouts.
Future<T> runE2eStep<T>(
  String name,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } on TimeoutException catch (error) {
    throw StateError('$name timed out: $error');
  }
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

/// English group-header text (this suite hardcodes English strings
/// throughout rather than resolving l10n — see the pre-existing `'OK'`/
/// `'Resolve'` finders below) for the accordion section a capability slug's
/// chip lives under in `CapabilityChipSet` (Requirements sheet, evaluation
/// ack-tags — both instantiate it with no search `query`, so sections start
/// collapsed and must be expanded by tapping the header first).
String _capabilityGroupLabelFor(String slug) {
  final group = CapabilityTag.fromSlug(slug)?.group;
  return switch (group) {
    CapabilityGroup.logistics => 'Logistics',
    CapabilityGroup.communication => 'Communication',
    CapabilityGroup.knowledge => 'Knowledge',
    CapabilityGroup.care => 'Care & support',
    CapabilityGroup.resources => 'Resources',
    CapabilityGroup.technical => 'Technical',
    CapabilityGroup.special => 'Other',
    null => throw ArgumentError('unknown capability slug: $slug'),
  };
}

Future<void> dismissOkDialogIfPresent(WidgetTester tester) async {
  final okFinder = find.text('OK');
  if (okFinder.evaluate().isNotEmpty) {
    await tester.tap(okFinder.first);
    await tester.pumpAndSettle();
  }
}

/// Logs in as [authorEmail], fills title/description, optionally adds
/// [needSlug] as a request "need" via the Requirements sheet, and lands on
/// the Recipients tab (which requires an already-persisted beaconId — the
/// create flow auto-saves a draft once the title/description are entered).
/// Shared prefix for [createAndForwardRequest] and
/// [createRequestReachRecipientsTab].
/// Web integration tests often update [TextEditingController] text without
/// firing [TextFormField.onChanged], leaving [BeaconCreateCubit] stale.
void syncBeaconCreateDraftFields(
  WidgetTester tester, {
  required String title,
  required String description,
}) {
  final cubit = tester
      .element(find.byKey(const Key('BeaconCreate.FormBody')))
      .read<BeaconCreateCubit>();
  cubit
    ..setTitle(title)
    ..setDescription(description);
}

Future<void> _createRequestToRecipientsTab(
  WidgetTester tester, {
  required String authorEmail,
  required String title,
  String? needSlug,
}) async {
  final description = 'Integration test request for $title';
  await loginAs(tester, authorEmail);
  await goToPath(tester, kPathBeaconNew);

  final titleField = find.byKey(TestIds.key(TestIds.requestTitle));
  await pumpUntilVisible(tester, titleField);
  debugPrint('[e2e] create: entering title');
  await tester.tap(titleField);
  await tester.pumpAndSettle();
  await tester.enterText(titleField, title);
  await tester.enterText(
    find.byKey(TestIds.key(TestIds.requestDescription)),
    description,
  );
  syncBeaconCreateDraftFields(
    tester,
    title: title,
    description: description,
  );
  await tester.pumpAndSettle();

  if (needSlug != null) {
    await tapAndSettle(tester, find.text('Requirements').first);
    // CapabilityChipSet groups tags into collapsed accordion sections when
    // no search query is active (the Requirements sheet has no search
    // field) — the group header must be expanded before its chips exist.
    final chipFinder = find.byKey(
      TestIds.key(TestIds.capabilityChip(needSlug)),
    );
    if (!await tryPumpUntilVisible(tester, chipFinder)) {
      await tapAndSettle(
        tester,
        find.text(_capabilityGroupLabelFor(needSlug)).first,
      );
      await pumpUntilVisible(tester, chipFinder);
    }
    await tapAndSettle(tester, chipFinder.first);
    await tapAndSettle(tester, find.text('Save').first);
  }

  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.requestRecipientsTab)),
  );
}

/// Creates a request as [viewerEmail] and stops on the Recipients tab
/// without forwarding to anyone — used to observe the forward band
/// (`ForwardBandStrip`, same widget used here and on the standalone Forward
/// screen — see `recipients_tab.dart`/`forward_beacon_screen.dart`) as a
/// read-only probe of what evidence that ego currently sees, without
/// completing an actual forward.
Future<String> createRequestReachRecipientsTab(
  WidgetTester tester, {
  required String viewerEmail,
  required String title,
  required String needSlug,
}) async {
  await _createRequestToRecipientsTab(
    tester,
    authorEmail: viewerEmail,
    title: title,
    needSlug: needSlug,
  );
  return title;
}

Future<void> confirmUncoveredForwardNoteIfPresent(WidgetTester tester) async {
  final withoutNote = find.text('Send without a shared note');
  if (await tryPumpUntilVisible(
    tester,
    withoutNote,
    timeout: const Duration(seconds: 3),
  )) {
    await tapAndSettle(tester, withoutNote);
  }
}

Future<String> createAndForwardRequest(
  WidgetTester tester, {
  required IntegrationFixture fixture,
  required String title,
  // Capability slug to add as a request "need" via the Requirements sheet.
  // Left unselected (null) preserves prior behavior for existing callers —
  // D8's outcome-tag candidate set is beacon.needs ∪ activeHelpOffer(subject)
  // .helpTypes, so a request with no explicit needs can still surface
  // capability evidence purely through the helper's own offered help type.
  String? needSlug,
}) async {
  await _createRequestToRecipientsTab(
    tester,
    authorEmail: fixture.authorEmail,
    title: title,
    needSlug: needSlug,
  );

  final recipient = find.byKey(
    TestIds.key(TestIds.forwardRecipient(fixture.helperUserId)),
  );
  await pumpUntilVisible(tester, recipient);
  final selectRecipient = find.descendant(
    of: recipient,
    matching: find.bySemanticsLabel('Select'),
  );
  await pumpUntilVisible(tester, selectRecipient);
  await tapAndSettle(tester, selectRecipient);
  final forwardSubmit = find.byKey(TestIds.key(TestIds.forwardSubmit));
  await pumpUntil(
    tester,
    () {
      if (!finderHasMatch(forwardSubmit)) return false;
      return tester.widget<OutlinedButton>(forwardSubmit).onPressed != null;
    },
    timeout: const Duration(seconds: 30),
  );
  await tapAndSettle(
    tester,
    forwardSubmit,
  );
  await confirmUncoveredForwardNoteIfPresent(tester);
  await dismissOkDialogIfPresent(tester);

  await goToPath(tester, kPathMyWork);
  await pumpUntilVisible(tester, find.text(title));
  return title;
}

Future<void> offerHelpFromInbox(
  WidgetTester tester, {
  required IntegrationFixture fixture,
  required String requestTitle,
  String capabilitySlug = 'software',
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
    'I can help with $capabilitySlug',
  );
  await tester.pumpAndSettle();
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.helpOfferBrowseCategories)),
  );
  await tester.enterText(
    find.byKey(TestIds.key(TestIds.helpOfferSearch)),
    capabilitySlug,
  );
  await tester.pumpAndSettle();
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.capabilityChip(capabilitySlug))).first,
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

/// Ends the acknowledged helper's participation through the current People UI.
///
/// The retired discussion-removal control used [helpOfferRemove]. An admitted
/// committer now exposes only the distinct `End participation` action, which
/// releases their current stake while retaining its history.
Future<void> endHelperParticipation(
  WidgetTester tester, {
  required IntegrationFixture fixture,
}) async {
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.helpOfferRelease(fixture.helperUserId))),
  );
  // Ending participation opens HelpOfferAdmissionReasonDialog; a non-empty
  // reason enables confirmation.
  final reasonField = find.byKey(TestIds.key(TestIds.admissionReasonInput));
  await pumpUntilVisible(tester, reasonField);
  await tester.enterText(reasonField, 'Integration cleanup');
  await tester.pumpAndSettle();
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.admissionReasonSubmit)),
  );
}

Future<void> enterGeneralIfNeeded(WidgetTester tester) async {
  final threadsTab = find.byKey(TestIds.key(TestIds.beaconTabThreads));
  if (threadsTab.evaluate().isEmpty) {
    throw StateError('Threads tab not found');
  }
  await tapAndSettle(tester, threadsTab.first);
  final generalRow = find.byKey(
    TestIds.key(TestIds.requestThread(RequestThread.generalId)),
  );
  await tapAndSettle(tester, generalRow);
}

Future<RoomMessage> sendRoomMessage(WidgetTester tester, String text) async {
  final messageInput = find.byKey(TestIds.key(TestIds.roomMessageInput));
  if (messageInput.evaluate().isEmpty) {
    await enterGeneralIfNeeded(tester);
  }
  await tester.enterText(
    find.byKey(TestIds.key(TestIds.roomMessageInput)),
    text,
  );
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.roomMessageSend)),
  );
  // Sent messages are rendered as "You: <body>" for the author, rather than
  // as a bare body Text widget.
  final messageText = find.textContaining(text);
  await pumpUntilVisible(tester, messageText);
  return tester
      .widget<RoomMessageTile>(
        find
            .ancestor(
              of: messageText,
              matching: find.byType(RoomMessageTile),
            )
            .first,
      )
      .message;
}

Future<void> showMyWorkList(WidgetTester tester) async {
  await goToPath(tester, kPathMyWork);
  if (finderHasMatch(find.text('Archive')) ||
      finderHasMatch(find.textContaining('Drafts ('))) {
    return;
  }
  final backToList = find.byTooltip('Back to list');
  if (finderHasMatch(backToList)) {
    await tapAndSettle(tester, backToList.first);
  }
}

Future<void> popToThreadsListIfNeeded(WidgetTester tester) async {
  final askButton = find.byKey(TestIds.key(TestIds.coordinationAskCreate));
  final askLabel = find.text('Ask');
  if (finderHasMatch(askButton) || finderHasMatch(askLabel)) {
    return;
  }
  final messageInput = find.byKey(TestIds.key(TestIds.roomMessageInput));
  if (finderHasMatch(messageInput)) {
    final backToThreads = find.byTooltip('Back to Threads');
    if (finderHasMatch(backToThreads)) {
      await tapAndSettle(tester, backToThreads.first);
      if (finderHasMatch(askButton) || finderHasMatch(askLabel)) {
        return;
      }
    }
    final detailsTab = find.byKey(TestIds.key(TestIds.beaconDetailsOpen));
    final threadsTab = find.byKey(TestIds.key(TestIds.beaconTabThreads));
    if (finderHasMatch(detailsTab) && finderHasMatch(threadsTab)) {
      await tapAndSettle(tester, detailsTab.first);
      await tapAndSettle(tester, threadsTab.first);
      if (finderHasMatch(askButton) || finderHasMatch(askLabel)) {
        return;
      }
    }
  }
  for (var attempt = 0; attempt < 3; attempt++) {
    final back = find.byType(BackButton);
    final arrowBack = find.byIcon(Icons.arrow_back);
    if (finderHasMatch(back)) {
      await tapAndSettle(tester, back.first);
    } else if (finderHasMatch(arrowBack)) {
      await tapAndSettle(tester, arrowBack.first);
    } else {
      final threadsTab = find.byKey(TestIds.key(TestIds.beaconTabThreads));
      if (threadsTab.evaluate().isEmpty) {
        throw StateError('Threads tab not found');
      }
      final detailsTab = find.byKey(TestIds.key(TestIds.beaconDetailsOpen));
      if (finderHasMatch(detailsTab)) {
        await tapAndSettle(tester, detailsTab.first);
      }
      await tapAndSettle(tester, threadsTab.first);
    }
    if (await tryPumpUntilVisible(
      tester,
      askButton,
      timeout: const Duration(seconds: 3),
    )) {
      return;
    }
  }
}

Future<void> enterThreadsIfNeeded(WidgetTester tester) async {
  final askButton = find.byKey(TestIds.key(TestIds.coordinationAskCreate));
  final askLabel = find.text('Ask');
  if (await tryPumpUntilVisible(
        tester,
        askButton,
        timeout: const Duration(milliseconds: 500),
      ) ||
      await tryPumpUntilVisible(
        tester,
        askLabel,
        timeout: const Duration(milliseconds: 500),
      )) {
    return;
  }
  await popToThreadsListIfNeeded(tester);
  if (!finderHasMatch(askButton) && !finderHasMatch(askLabel)) {
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isNotEmpty) {
      await tester.drag(scrollables.first, const Offset(0, 320));
      await tester.pumpAndSettle();
    }
  }
  await pumpUntil(
    tester,
    () => finderHasMatch(askButton) || finderHasMatch(askLabel),
    timeout: const Duration(seconds: 30),
  );
}

Future<RequestThread> createCoordinationItem(
  WidgetTester tester, {
  required String launcherId,
  required String title,
  String? body,
}) async {
  await enterThreadsIfNeeded(tester);
  final launcher = find.byKey(TestIds.key(launcherId));
  final visibleLabel = switch (launcherId) {
    TestIds.coordinationAskCreate => 'Ask',
    TestIds.coordinationPromiseCreate => 'Commitment',
    _ => null,
  };
  // The wide Ask/Commitment controls carry their key on the HUD wrapper, not
  // its inner button. Tap their rendered labels; the icon-only Blocker uses
  // its keyed wrapper (and has no rendered text label).
  if (visibleLabel != null && finderHasMatch(find.text(visibleLabel))) {
    await tapAndSettle(tester, find.text(visibleLabel).first);
  } else if (finderHasMatch(launcher)) {
    await tapAndSettle(tester, launcher.first);
  } else {
    throw StateError('Coordination launcher not found: $launcherId');
  }
  await pumpUntilVisible(
    tester,
    find.byKey(TestIds.key(TestIds.coordinationComposerTitle)),
  );

  await tester.enterText(
    find.byKey(TestIds.key(TestIds.coordinationComposerTitle)),
    title,
  );
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.coordinationComposerSubmit)),
  );
  final itemTitle = find.text(title);
  // A Promise without another admitted target saves as a draft. Drafts are
  // intentionally collapsed by default, so reveal that fold before asserting
  // the saved item is rendered.
  if (!await tryPumpUntilVisible(
    tester,
    itemTitle,
    timeout: const Duration(seconds: 2),
  )) {
    final draftsFold = find.textContaining('Drafts (');
    if (finderHasMatch(draftsFold)) {
      await tapAndSettle(tester, draftsFold.first);
    }
  }
  await pumpUntilVisible(tester, itemTitle);
  await popToThreadsListIfNeeded(tester);
  return tester
      .widget<ItemCard>(
        find
            .ancestor(of: find.text(title), matching: find.byType(ItemCard))
            .first,
      )
      .thread;
}

/// Resolves the specified active item. Drafts are also listed in the Threads
/// UI, so a positional overflow-menu finder can target a draft that correctly
/// has no Resolve action.
Future<void> resolveCoordinationItem(
  WidgetTester tester, {
  required String title,
}) async {
  await enterThreadsIfNeeded(tester);
  final itemTitle = find.text(title);
  await pumpUntilVisible(tester, itemTitle);
  final itemCard = find
      .ancestor(
        of: itemTitle,
        matching: find.byType(ItemCard),
      )
      .first;
  if (!finderHasMatch(itemCard)) {
    throw StateError(
      'coordination item card missing for "$title": ${_screenDump()}',
    );
  }
  final itemId = tester.widget<ItemCard>(itemCard).thread.item!.id;
  final menu = find.byKey(TestIds.key(TestIds.coordinationItemMenu(itemId)));
  if (!await tryPumpUntilVisible(tester, menu)) {
    final menuKeys = find
        .byType(PopupMenuButton<Object?>)
        .evaluate()
        .map((e) => e.widget.key)
        .join(', ');
    throw StateError(
      'resolve menu missing for item=$itemId title="$title" menus=[$menuKeys]: '
      '${_screenDump()}',
    );
  }
  await tapAndSettle(tester, menu);
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.coordinationItemResolve(itemId))),
  );
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

/// After every required reviewer has finished or skipped, closes the request
/// via My Work's "Close request" card CTA when visible, otherwise the beacon
/// detail HUD `closeNow` action (and its confirm sheet).
Future<void> triggerCloseNow(WidgetTester tester) async {
  await goToPath(tester, kPathMyWork);
  final myWorkClose = find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('my_work.close_now.'),
  );
  final hudCloseNow = _hudAction('closeNow');
  await pumpUntil(
    tester,
    () => finderHasMatch(myWorkClose) || finderHasMatch(hudCloseNow),
    timeout: const Duration(seconds: 45),
  );
  if (finderHasMatch(myWorkClose)) {
    await tapAndSettle(tester, myWorkClose.first);
  } else {
    await tapAndSettle(tester, hudCloseNow.first);
    await pumpUntilVisible(
      tester,
      find.text('Close request now?'),
      timeout: const Duration(seconds: 30),
    );
    // Sheet action shares the HUD label; prefer the last match (sheet button).
    await tapAndSettle(tester, find.text('Close now').last);
  }
  // Close may leave the author on embedded beacon detail; Archive is on the list.
  await showMyWorkList(tester);
  await pumpUntilVisible(
    tester,
    find.text('Archive'),
    timeout: const Duration(seconds: 30),
  );
}

/// Mark every remaining card cannot-evaluate (if needed) then send the package.
Future<void> sendCompleteReviewPackage(WidgetTester tester) async {
  await pumpUntilVisible(
    tester,
    find.byKey(TestIds.key(TestIds.evaluationSubmit)),
  );
  for (var i = 0; i < 12; i++) {
    final submit = tester.widget<FilledButton>(
      find.byKey(TestIds.key(TestIds.evaluationSubmit)),
    );
    if (submit.onPressed != null) {
      break;
    }
    final canEvaluateOn = find.byWidgetPredicate(
      (widget) => widget is SwitchListTile && widget.value,
    );
    expect(canEvaluateOn, findsWidgets);
    await tapAndSettle(tester, canEvaluateOn.first);
    final confirm = find.text('Cannot evaluate');
    if (confirm.evaluate().isNotEmpty) {
      await tapAndSettle(tester, confirm.last);
    }
  }
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.evaluationSubmit)),
  );
}

Future<void> reviewParticipant(
  WidgetTester tester,
  String userId, {
  String impact = 'zero',
  List<String> ackTags = const [],
}) async {
  final tile = find.byKey(TestIds.key(TestIds.evaluationParticipant(userId)));
  expect(
    tile,
    findsOneWidget,
    reason: 'evaluation participant $userId must be present',
  );
  await tapAndSettle(tester, tile.first);
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.evaluationImpact(impact))),
  );
  if (ackTags.isNotEmpty) {
    final field = find.byKey(TestIds.key(TestIds.evaluationCapabilityField));
    expect(
      field,
      findsOneWidget,
      reason: 'acknowledgement field must be present for positive impact',
    );
    await tapAndSettle(tester, field);
    for (final slug in ackTags) {
      final tag = CapabilityTag.fromSlug(slug);
      expect(tag, isNotNull, reason: 'unknown capability slug: $slug');
      final group = _capabilityGroupLabelFor(slug);
      final chip = find.byKey(TestIds.key(TestIds.capabilityChip(slug)));
      if (chip.evaluate().isEmpty) {
        final groupFinder = find.text(group);
        expect(
          groupFinder,
          findsOneWidget,
          reason: 'capability group $group must be present',
        );
        await tapAndSettle(tester, groupFinder);
      }
      expect(
        chip,
        findsOneWidget,
        reason: 'capability chip $slug must be visible',
      );
      await tapAndSettle(tester, chip);
    }
    final done = find.byKey(TestIds.key(TestIds.evaluationCapabilityDone));
    expect(done, findsOneWidget, reason: 'capability Done must be present');
    await tapAndSettle(tester, done);
  }
  final saveButton = find.byKey(TestIds.key(TestIds.evaluationSave));
  await tapAndSettle(tester, saveButton);
  await pumpUntil(tester, () => saveButton.evaluate().isEmpty);
  final impactLabel = switch (impact) {
    'pos1' => 'Helped somewhat',
    'pos2' => 'Helped a lot',
    'neg1' => 'Hurt somewhat',
    'neg2' => 'Hurt a lot',
    'zero' => 'No real effect',
    _ => throw ArgumentError('unknown evaluation impact: $impact'),
  };
  expect(
    find.descendant(of: tile, matching: find.text(impactLabel)),
    findsOneWidget,
    reason: 'submitted impact label must be visible for participant $userId',
  );
  if (ackTags.isNotEmpty) {
    await tapAndSettle(tester, tile);
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.evaluationCapabilityField)),
    );
    final l10n = L10n.of(tester.element(find.byType(Scaffold).first))!;
    for (final slug in ackTags) {
      final tag = CapabilityTag.fromSlug(slug);
      expect(tag, isNotNull, reason: 'unknown capability slug: $slug');
      final label = tag!.labelOf(l10n);
      expect(
        find.textContaining(label),
        findsWidgets,
        reason: 'saved acknowledgement $slug must survive reload',
      );
    }
    final reopenedSaveButton = find.byKey(
      TestIds.key(TestIds.evaluationSave),
    );
    expect(
      reopenedSaveButton,
      findsOneWidget,
      reason: 'reopened review sheet must show Save',
    );
    Navigator.of(tester.element(reopenedSaveButton)).pop();
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => reopenedSaveButton.evaluate().isEmpty);
  }
}

Future<void> toggleRoutingMute(
  WidgetTester tester, {
  required String capabilityLabel,
  required String groupLabel,
}) async {
  await goToPath(tester, kPathRoutingMute);
  final switchFinder = find.widgetWithText(SwitchListTile, capabilityLabel);
  if (!await tryPumpUntilVisible(tester, switchFinder)) {
    await tapAndSettle(tester, find.text(groupLabel).first);
    await pumpUntilVisible(tester, switchFinder);
  }
  await tapAndSettle(tester, switchFinder.first);
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
  // Graph browse details are canonical root routes, with Network as their
  // semantic Home source on a cold link.
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
  final cubit = readGraphCubit(tester);
  bool isFixtureHelper(NodeDetails node) =>
      node is UserNode &&
      node.id != cubit.state.me.id &&
      node.label.startsWith('IT helper');
  try {
    await pumpUntil(
      tester,
      () => cubit.graphController.nodes.any(isFixtureHelper),
      timeout: const Duration(seconds: 45),
    );
  } on TimeoutException {
    final nodes = cubit.graphController.nodes
        .map((node) => '${node.runtimeType}:${node.id}:${node.label}')
        .join(', ');
    throw StateError('fixture helper is absent from graph nodes: $nodes');
  }
  final helper = cubit.graphController.nodes.singleWhere(
    isFixtureHelper,
  );
  // The graph canvas applies transforms independently of the label widgets,
  // so WidgetTester taps can land outside the node. Select through the live
  // cubit, as [selectGraphNode] does, after proving that the rendered graph
  // contains the fixture neighbour.
  cubit.selectNode(helper);
  await pumpBounded(tester);
  return cubit.state.focus;
}

Future<void> expandEgoNeighbourhood(WidgetTester tester) async {
  final cubit = readGraphCubit(tester);
  final ego = cubit.graphController.nodes.singleWhere(
    (node) => node.id == cubit.state.me.id,
  );
  await cubit.expandNode(ego);
  await pumpBounded(tester, frames: 12);
  debugPrint(
    '[e2e] expandEgoNeighbourhood: focus=${readGraphCubit(tester).state.focus}',
  );
}

Future<void> expandFocusedGraphNode(WidgetTester tester) async {
  final cubit = readGraphCubit(tester);
  final focus = cubit.state.focus;
  if (focus.isEmpty) {
    throw StateError('cannot expand graph node without a focused node');
  }
  final node = cubit.graphController.nodes.singleWhere(
    (node) => node.id == focus,
  );
  // Graph expansion is now a node action (the old graph.expand control was
  // removed). As with [expandEgoNeighbourhood], Canvas transforms make a
  // browser tap on the rendered node unreliable, so drive the running cubit
  // command after the helper has been selected from the rendered graph.
  await cubit.expandNode(node);
  await pumpBounded(tester, frames: 12);
  debugPrint(
    '[e2e] expandFocusedGraphNode: focus=${cubit.state.focus}',
  );
}

Future<void> tapGraphBack(WidgetTester tester) async {
  readGraphCubit(tester).popFocus();
  await pumpBounded(tester);
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
