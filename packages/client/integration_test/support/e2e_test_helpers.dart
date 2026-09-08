import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/app/router/browse_deep_link.dart';
import 'package:tentura/consts.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/domain/capability/capability_group.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/dialog/beacon_send_confirmation_dialog.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/domain/entity/room_message.dart';
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
    label: 'loginAs($email) account',
  );
  debugPrint('[e2e] loginAs($email): done');
}

Future<void> logout(WidgetTester tester) async {
  final accountId = GetIt.I<AuthCubit>().state.currentAccountId;
  debugPrint('[e2e] logout: currentAccountId="$accountId"');
  if (accountId.isEmpty) {
    return;
  }
  // Clear root BeaconView overlays before sign-out. Auto-close can leave a
  // closed detail mounted; signing out from that route has hung accountId clears.
  final router = GetIt.I<RootRouter>();
  await router.replaceAll([const AuthLoginRoute()]);
  await tester.pump(const Duration(milliseconds: 150));
  await GetIt.I<AuthCubit>().signOut();
  debugPrint('[e2e] logout: signOut returned');
  await pumpUntil(
    tester,
    () => GetIt.I<AuthCubit>().state.currentAccountId.isEmpty,
    label: 'logout account cleared',
  );
  debugPrint('[e2e] logout: done');
}

/// Apply the same URL transformer used by app startup before warm navigation.
/// AutoRoute.navigatePath itself does not run the platform deep-link transformer.
Future<void> goToDeepLink(WidgetTester tester, String path) async {
  final router = GetIt.I<RootRouter>();
  final transformed = await router.deepLinkTransformer(Uri.parse(path));
  final browseStack = buildBrowseDeepLinkStack(transformed);
  if (browseStack == null) {
    await goToPath(tester, transformed.toString());
    return;
  }

  // Match RootRouter.openFromNotificationLink / deepLinkBuilder:
  // cold start builds Home+detail; warm keeps the mounted Home tab and pushes
  // the detail. replaceAll([home, detail]) on a warm app breaks AppBar back
  // after browser history.back().
  final tabs = router.innerRouterOf<TabsRouter>(HomeRoute.name);
  if (tabs == null) {
    unawaited(router.replaceAll([browseStack.home, browseStack.detail]));
  } else {
    final query = transformed.queryParameters.isEmpty
        ? ''
        : Uri(queryParameters: transformed.queryParameters).query;
    final target = query.isEmpty
        ? transformed.path
        : '${transformed.path}?$query';
    unawaited(router.pushPath(target));
  }
  await pumpUntil(tester, () {
    final current = Uri.parse(router.currentUrl);
    return current.path == transformed.path &&
        transformed.queryParameters.entries.every(
          (entry) => current.queryParameters[entry.key] == entry.value,
        );
  });
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
  await pumpUntil(
    tester,
    () => router.currentUrl.contains(path),
    label: 'goToPath($path)',
  );
  debugPrint('[e2e] goToPath($path): done (url=${router.currentUrl})');
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration step = const Duration(milliseconds: 200),
  Duration timeout = const Duration(seconds: 20),
  String label = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(step);
    if (condition()) {
      return;
    }
  }
  final dump = _screenDump();
  throw TimeoutException('Timed out waiting for $label. $dump');
}

/// Adds the user-action phase to asynchronous browser-test timeouts.
Future<T> runE2eStep<T>(
  String name,
  Future<T> Function() action,
) async {
  debugPrint('[e2e] checkpoint: $name');
  try {
    final result = await action();
    debugPrint('[e2e] checkpoint passed: $name');
    return result;
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
  var publish = '';
  final form = find.byKey(const Key('BeaconCreate.FormBody'));
  if (finderHasMatch(form)) {
    final state = form.evaluate().first.read<BeaconCreateCubit>().state;
    publish =
        ' draftId=${state.draftId} loading=${state.isLoading}'
        ' validationBlocker=${state.publishBlocker}';
  }
  final submit = find.byKey(TestIds.key(TestIds.forwardSubmit));
  if (finderHasMatch(submit)) {
    final state = submit.evaluate().first.read<ForwardCubit>().state;
    final outcome = state.lastDeliveryOutcome;
    publish +=
        ' selectedRecipientIds=${state.selectedIds}'
        ' deliveryOutcome=${outcome == null ? "pending" : "failed=${outcome.failed} delivered=${outcome.deliveredRecipientIds} skipped=${outcome.availabilitySkippedRecipientIds}"}';
  }
  return 'url=$url hud=[${hudKeys.join(',')}]$publish texts: $texts';
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
  String? label,
}) => pumpUntil(
  tester,
  () => finderHasMatch(finder),
  timeout: timeout,
  label: label ?? 'visible(${finder.description})',
);

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
    // Flush needs before Recipients: draft autosave from the title alone
    // creates an empty-needs draft; opening Recipients immediately then
    // loads an empty forward band (no "Seen helping with …").
    final formBody = find.byKey(const Key('BeaconCreate.FormBody'));
    await pumpUntilVisible(tester, formBody);
    final createCubit = tester.element(formBody).read<BeaconCreateCubit>();
    await pumpUntil(
      tester,
      () => createCubit.state.needs.contains(needSlug),
      label: 'create needs contain $needSlug',
    );
    await createCubit.flushAutosave();
  }

  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.requestRecipientsTab)),
  );
  // Next/Recipients is async (flush + step swap). Wait for recipients chrome
  // so callers do not race the form step.
  await pumpUntilVisible(
    tester,
    find.byKey(TestIds.key(TestIds.requestMakeLive)),
    timeout: const Duration(seconds: 60),
    label: 'recipients step Make live',
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
  await runE2eStep(
    'fill and persist draft',
    () => _createRequestToRecipientsTab(
      tester,
      authorEmail: fixture.authorEmail,
      title: title,
      needSlug: needSlug,
    ),
  );
  final createCubit = tester
      .element(find.byKey(const Key('BeaconCreate.FormBody')))
      .read<BeaconCreateCubit>();
  await runE2eStep(
    'draft persistence',
    () => pumpUntil(
      tester,
      () => createCubit.state.draftId?.isNotEmpty ?? false,
    ),
  );
  final selectRecipient = find.byKey(
    TestIds.key(TestIds.forwardRecipientCheckbox(fixture.helperUserId)),
  );
  await pumpUntilVisible(tester, selectRecipient);
  final forwardCubit = tester.element(selectRecipient).read<ForwardCubit>();
  await runE2eStep('recipient selection', () async {
    expect(
      forwardCubit.state.selectedIds,
      isNot(contains(fixture.helperUserId)),
    );
    await tapAndSettle(tester, selectRecipient);
    expect(
      forwardCubit.state.selectedIds,
      contains(fixture.helperUserId),
      reason: 'Recipient tap must change selection. ${_screenDump()}',
    );
  });
  final forwardSubmit = find.byKey(TestIds.key(TestIds.forwardSubmit));
  await runE2eStep(
    'enabled submit',
    () => pumpUntil(
      tester,
      () =>
          finderHasMatch(forwardSubmit) &&
          tester.widget<OutlinedButton>(forwardSubmit).onPressed != null,
      timeout: const Duration(seconds: 30),
    ),
  );
  await tapAndSettle(tester, forwardSubmit);
  await runE2eStep(
    'note confirmation',
    () => confirmUncoveredForwardNoteIfPresent(tester),
  );
  await runE2eStep('delivery confirmation', () async {
    await pumpUntilVisible(tester, find.byType(BeaconSendConfirmationDialog));
    final outcome = tester
        .widget<BeaconSendConfirmationDialog>(
          find.byType(BeaconSendConfirmationDialog),
        )
        .outcome;
    expect(outcome.failed, isFalse, reason: _screenDump());
    expect(outcome.deliveredRecipientIds, contains(fixture.helperUserId));
    expect(outcome.availabilitySkippedRecipientIds, isEmpty);
  });
  await runE2eStep('publication', () async {
    // Read-only verification of the UI publish command, never fixture setup.
    final beacon = await GetIt.I<BeaconRepository>().fetchBeaconById(
      createCubit.state.draftId!,
    );
    expect(beacon.id, createCubit.state.draftId);
    expect(
      beacon.status,
      BeaconStatus.open,
      reason: 'UI-created request must be published',
    );
  });
  await dismissOkDialogIfPresent(tester);
  await runE2eStep('navigation after publication', () async {
    await goToPath(tester, kPathMyWork);
    await pumpUntilVisible(tester, find.text(title));
  });
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

Future<void> enterChatIfNeeded(WidgetTester tester) async {
  final messageInput = find.byKey(TestIds.key(TestIds.roomMessageInput));
  if (messageInput.evaluate().isNotEmpty) {
    return;
  }
  final chatTab = find.byKey(TestIds.key(TestIds.beaconTabRoom));
  if (chatTab.evaluate().isEmpty) {
    throw StateError('Chat tab not found');
  }
  await tapAndSettle(tester, chatTab.first);
  await pumpUntilVisible(tester, messageInput);
}

Future<void> enterGeneralIfNeeded(WidgetTester tester) =>
    enterChatIfNeeded(tester);

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
  final messageTile = find.byWidgetPredicate(
    (widget) =>
        widget is RoomMessageTile &&
        widget.message.body == text &&
        !widget.message.id.startsWith('local:'),
  );
  await runE2eStep(
    'General message persisted',
    () => pumpUntilVisible(tester, messageTile),
  );
  return tester.widget<RoomMessageTile>(messageTile).message;
}

Future<void> _forceMyWorkDesk(WidgetTester tester) async {
  final router = GetIt.I<RootRouter>();
  final spec = HomeTabSpec.forTab(HomeTab.work);
  // Root BeaconView overlays survive popUntil/navigatePath after auto-close.
  // Pop what we can, hard-reset the stack, and align the browser URL so a
  // stale /beacon/view deep link cannot resurrect the detail.
  for (var i = 0; i < 8 && router.canPop(); i++) {
    await router.maybePop();
    await tester.pump(const Duration(milliseconds: 100));
  }
  await router.replaceAll([
    HomeRoute(
      children: [
        spec.shell(children: [spec.rootRoute()]),
      ],
    ),
  ]);
  web.window.history.replaceState(null, '', kPathMyWork);
  unawaited(router.navigatePath(kPathMyWork, includePrefixMatches: true));
  await pumpUntil(
    tester,
    () =>
        currentAppUrl() == kPathMyWork ||
        currentAppUrl().startsWith('$kPathMyWork?'),
    timeout: const Duration(seconds: 30),
    label: '_forceMyWorkDesk',
  );
}

/// My Work desk, reclaiming it if attention/deep-link reopens a detail.
Future<void> _awaitMyWorkDeskAction(
  WidgetTester tester,
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (!currentAppUrl().startsWith(kPathMyWork)) {
      await _forceMyWorkDesk(tester);
    }
    if (ready()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  throw TimeoutException(
    'Timed out waiting for My Work desk action. ${_screenDump()}',
  );
}

Future<void> showMyWorkList(WidgetTester tester) async {
  await _forceMyWorkDesk(tester);
  if (finderHasMatch(find.widgetWithText(TextButton, 'Archive')) ||
      finderHasMatch(find.textContaining('Drafts ('))) {
    return;
  }
  final backToList = find.byTooltip('Back to list');
  if (finderHasMatch(backToList)) {
    await tapAndSettle(tester, backToList.first);
  }
}

Future<void> popToChatIfNeeded(WidgetTester tester) async {
  final messageInput = find.byKey(TestIds.key(TestIds.roomMessageInput));
  if (finderHasMatch(messageInput)) {
    return;
  }
  final chatTab = find.byKey(TestIds.key(TestIds.beaconTabRoom));
  if (finderHasMatch(chatTab)) {
    await tapAndSettle(tester, chatTab.first);
    if (finderHasMatch(messageInput)) {
      return;
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
      break;
    }
    if (finderHasMatch(messageInput)) {
      return;
    }
  }
  await enterChatIfNeeded(tester);
}

Future<void> popToThreadsListIfNeeded(WidgetTester tester) =>
    popToChatIfNeeded(tester);

Finder _hudAction(String action) =>
    find.byKey(TestIds.key(TestIds.beaconHudAuthorAction(action)));

Future<void> closeRequestAndOpenReview(WidgetTester tester) async {
  await tapAndSettle(tester, find.byKey(TestIds.key(TestIds.beaconTabNow)));
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
///
/// Sending the last required review package auto-closes the review window on
/// the server (`EvaluationCase` → `_autoCloseReviewWindow`). In that case the
/// desk already shows the Finished card with Archive — do not wait for a Close
/// CTA that will never appear.
Future<void> triggerCloseNow(WidgetTester tester) async {
  await _forceMyWorkDesk(tester);
  final myWorkClose = find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('my_work.close_now.'),
  );
  final hudCloseNow = _hudAction('closeNow');
  final finishedArchive = find.widgetWithText(TextButton, 'Archive');
  await _awaitMyWorkDeskAction(
    tester,
    () =>
        finderHasMatch(myWorkClose) ||
        finderHasMatch(hudCloseNow) ||
        finderHasMatch(finishedArchive),
  );
  if (finderHasMatch(myWorkClose)) {
    await tapAndSettle(tester, myWorkClose.first);
  } else if (finderHasMatch(hudCloseNow)) {
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
  await _awaitMyWorkDeskAction(
    tester,
    () => finderHasMatch(find.widgetWithText(TextButton, 'Archive')),
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
