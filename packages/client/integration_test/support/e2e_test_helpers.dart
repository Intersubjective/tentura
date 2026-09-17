import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui' show Offset, PlatformDispatcher, PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/dialog/beacon_send_confirmation_dialog.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/widget/graph_layout_view.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_graph_scene.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_body.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_state.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
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
///
/// Also forces [FakeAccessibilityFeatures.disableAnimations] so widgets that
/// use [AnimationController.repeat] (e.g. [LinearPiActive]) do not prevent
/// [WidgetTester.pumpAndSettle] from completing.
Future<void> launchApp(Future<void> Function() start) async {
  final originalOnError = FlutterError.onError;
  final originalPlatformOnError = PlatformDispatcher.instance.onError;
  final originalErrorWidgetBuilder = ErrorWidget.builder;
  final binding = IntegrationTestWidgetsFlutterBinding.instance;
  binding.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
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
    drainTesterExceptions(tester);
    if (condition()) {
      return;
    }
  }
  final dump = _screenDump();
  throw TimeoutException('Timed out waiting for $label. $dump');
}

Future<void> pumpUntilAsync(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration step = const Duration(milliseconds: 200),
  Duration timeout = const Duration(seconds: 20),
  String label = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(step);
    drainTesterExceptions(tester);
    if (await condition()) {
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

/// Bounded settle for web integration tests.
///
/// [WidgetTester.pumpAndSettle] never returns while any
/// [AnimationController.repeat] ticker is mounted (default 10‑minute timeout).
/// Prefer this helper: it waits for a short idle streak of stable transient
/// callback counts, then returns even if a loading bar is still repeating.
Future<void> pumpSettleBounded(
  WidgetTester tester, {
  Duration step = const Duration(milliseconds: 100),
  Duration timeout = const Duration(seconds: 20),
}) async {
  final wallEnd = DateTime.now().add(timeout);
  await tester.pump();
  var stable = 0;
  var lastCallbacks = tester.binding.transientCallbackCount;
  while (DateTime.now().isBefore(wallEnd)) {
    await tester.pump(step);
    drainTesterExceptions(tester);
    final callbacks = tester.binding.transientCallbackCount;
    // Infinite progress tickers keep a constant non-zero callback count.
    // Treat "unchanged for 3 steps" as settled enough for interaction.
    if (callbacks == lastCallbacks) {
      stable++;
      if (stable >= 3) return;
    } else {
      stable = 0;
      lastCallbacks = callbacks;
    }
  }
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  // finder.description, not $finder: toString() evaluates the finder and
  // throws "Bad state: No element" for empty `.first`-style finders.
  debugPrint('[e2e] tapAndSettle(${finder.description})');
  await pumpUntilVisible(tester, finder);
  // Long scrollables (e.g. the evaluation sheet) can keep the target off
  // screen; ensureVisible is a no-op without a Scrollable ancestor.
  await tester.ensureVisible(finder);
  await pumpSettleBounded(tester);
  drainTesterExceptions(tester);
  await tester.tap(finder);
  await pumpSettleBounded(tester);
  drainTesterExceptions(tester);
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
    CapabilityGroup.rpg => 'RPG',
    CapabilityGroup.special => 'Other',
    null => throw ArgumentError('unknown capability slug: $slug'),
  };
}

Future<void> dismissOkDialogIfPresent(WidgetTester tester) async {
  final okFinder = find.text('OK');
  if (okFinder.evaluate().isNotEmpty) {
    await tester.tap(okFinder.first);
    await pumpSettleBounded(tester);
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
  await pumpSettleBounded(tester);
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
  await pumpSettleBounded(tester);
  // Bounded settle no longer idles for the 1s autosave debounce; flush so
  // Recipients (which requires a persisted draft id) does not race it.
  final formBody = find.byKey(const Key('BeaconCreate.FormBody'));
  await pumpUntilVisible(tester, formBody);
  await tester.element(formBody).read<BeaconCreateCubit>().flushAutosave();
  await pumpUntil(
    tester,
    () {
      final cubit = tester.element(formBody).read<BeaconCreateCubit>();
      return cubit.state.draftId?.isNotEmpty ?? false;
    },
    timeout: const Duration(seconds: 45),
    label: 'draft id after flushAutosave',
  );

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
  final sheetTitle = find.text('Shared note');
  if (await tryPumpUntilVisible(
    tester,
    sheetTitle,
    timeout: const Duration(seconds: 3),
  )) {
    // Empty optional note: primary Forward commits without a skip-send CTA.
    final primary = find.descendant(
      of: find.byType(FilledButton),
      matching: find.textContaining('Forward to'),
    );
    expect(
      primary,
      findsWidgets,
      reason: 'Uncovered sheet must expose an always-enabled Forward CTA',
    );
    await tapAndSettle(tester, primary.first);
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

Future<void> goToInboxTriage(
  WidgetTester tester, {
  String? beaconId,
}) async {
  await goToPath(tester, kPathInbox);
  await pumpSettleBounded(tester);
  if (beaconId != null) {
    await pumpUntilVisible(
      tester,
      find.bySemanticsIdentifier(TestIds.activityOffer(beaconId)),
    );
  } else {
    await pumpUntilVisible(
      tester,
      find.bySemanticsIdentifier(TestIds.activityForYouHeader),
    );
  }
}

Future<void> offerHelpFromInbox(
  WidgetTester tester, {
  required IntegrationFixture fixture,
  required String requestTitle,
  String capabilitySlug = 'software',
}) async {
  await loginAs(tester, fixture.helperEmail);
  await goToInboxTriage(tester);
  await pumpUntilVisible(tester, find.text(requestTitle));
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.inboxOfferHelp)).first,
  );
  await tester.enterText(
    find.byKey(TestIds.key(TestIds.helpOfferMessage)),
    'I can help with $capabilitySlug',
  );
  await pumpSettleBounded(tester);
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.helpOfferBrowseCategories)),
  );
  await tester.enterText(
    find.byKey(TestIds.key(TestIds.helpOfferSearch)),
    capabilitySlug,
  );
  await pumpSettleBounded(tester);
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
  await goToInboxTriage(tester);
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
  await pumpSettleBounded(tester);
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
    final cannotEvaluate = find.byWidgetPredicate(
      (widget) =>
          widget is TextButton &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'evaluation.cannot_evaluate.',
          ) &&
          widget.onPressed != null,
    );
    expect(cannotEvaluate, findsWidgets);
    await tapAndSettle(tester, cannotEvaluate.first);
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
    await pumpSettleBounded(tester);
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
bool e2eDrainExceptions = true;

void drainTesterExceptions(WidgetTester tester) {
  if (!e2eDrainExceptions) {
    return;
  }
  while (tester.takeException() != null) {}
}

Future<void> pumpBounded(
  WidgetTester tester, {
  int frames = 4,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
    drainTesterExceptions(tester);
  }
}

String currentAppUrl() => GetIt.I<RootRouter>().currentUrl;

/// English [L10n.myWorkEmptyActiveTitle] — this suite hardcodes English strings.
const _myWorkEmptyActiveTitle = 'No active work yet';

/// Waits until [HomeActivationCubit] has hydrated latches for [accountId] and
/// both My Work and Inbox projections have settled (or Inbox failed).
Future<void> awaitActivationSettled(
  WidgetTester tester,
  String accountId,
) async {
  await pumpUntil(
    tester,
    () {
      final state = GetIt.I<HomeActivationCubit>().state;
      return state.hydrated &&
          state.boundAccountId == accountId &&
          state.signals.isSettled;
    },
    label: 'awaitActivationSettled($accountId)',
  );
}

/// Asserts the first-run orientation panel is shown or hidden. When hidden,
/// also requires the ordinary empty title or a non-empty card list so a spinner
/// or blank body cannot pass.
Future<void> expectOrientationPanel(
  WidgetTester tester, {
  required bool visible,
}) async {
  final panel = find.byKey(TestIds.key(TestIds.orientationPanel));
  if (visible) {
    expect(panel, findsOneWidget, reason: _screenDump());
    return;
  }
  expect(panel, findsNothing, reason: _screenDump());
  final hasEmptyTitle = finderHasMatch(find.text(_myWorkEmptyActiveTitle));
  final hasCards = _myWorkShowsCards();
  expect(
    hasEmptyTitle || hasCards,
    isTrue,
    reason:
        'Hidden orientation must show empty title or card list; ${_screenDump()}',
  );
  expect(
    finderHasMatch(find.byType(CircularProgressIndicator)),
    isFalse,
    reason: 'Spinner must not pass as hidden orientation; ${_screenDump()}',
  );
}

bool _myWorkShowsCards() {
  return finderHasMatch(
    find.byWidgetPredicate(
      (widget) {
        if (widget.key is! ValueKey<String>) return false;
        final value = (widget.key! as ValueKey<String>).value;
        return value.startsWith('authored') || value.startsWith('helpOffered');
      },
    ),
  );
}

Future<void> openDebugSettings(WidgetTester tester) async {
  await goToPath(tester, kPathDebugSettings);
}

Future<void> setOrientationOverride(
  WidgetTester tester,
  OrientationDebugOverride mode,
) async {
  final segment = switch (mode) {
    OrientationDebugOverride.auto =>
      find.byKey(TestIds.key(TestIds.debugOrientationAuto)),
    OrientationDebugOverride.show =>
      find.byKey(TestIds.key(TestIds.debugOrientationShow)),
    OrientationDebugOverride.hide =>
      find.byKey(TestIds.key(TestIds.debugOrientationHide)),
  };
  await tapAndSettle(tester, segment);
  await pumpUntil(
    tester,
    () => GetIt.I<HomeActivationCubit>().state.debugOverride == mode,
    label: 'setOrientationOverride($mode)',
  );
}

Future<void> resetFirstRunOrientation(WidgetTester tester) async {
  await tapAndSettle(
    tester,
    find.byKey(TestIds.key(TestIds.debugOrientationReset)),
  );
  await pumpUntil(
    tester,
    () {
      final state = GetIt.I<HomeActivationCubit>().state;
      return !state.dismissedLatch && !state.activatedLatch;
    },
    label: 'resetFirstRunOrientation',
  );
}

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
  final tokenResponse = await _postJson(
    '/api/v2/session/access-token',
    const <String, Object?>{},
    includeCredentials: true,
  );
  final token = tokenResponse['access_token'] as String?;
  if (token == null || token.isEmpty) {
    throw StateError('access-token missing for GraphQL: $tokenResponse');
  }
  return _postJson(
    '/api/v2/graphql',
    {'query': query},
    includeCredentials: true,
    extraHeaders: {'Authorization': 'Bearer $token'},
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

String _escapeGraphQlString(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

ConstellationCubit readConstellationCubit(WidgetTester tester) =>
    tester.element(find.byType(ConstellationBody)).read<ConstellationCubit>();

Future<void> openConstellation(WidgetTester tester) async {
  await goToPath(tester, kPathConstellation);
  await pumpUntilVisible(
    tester,
    find.byKey(const Key('constellation.app_bar.view_mode')),
    label: 'constellation view mode toggle',
  );
  await waitForConstellationLoaded(tester);
}

Future<void> waitForConstellationLoaded(WidgetTester tester) async {
  await pumpUntil(
    tester,
    () {
      final cubit = readConstellationCubit(tester);
      return cubit.state.field != null && cubit.state.composition != null;
    },
    label: 'constellation field loaded',
    timeout: const Duration(seconds: 45),
  );
  await pumpBounded(tester);
}

Future<void> setConstellationViewMode(
  WidgetTester tester,
  ConstellationViewMode mode,
) async {
  readConstellationCubit(tester).setViewMode(mode);
  await pumpBounded(tester, frames: 8);
}

Finder _singleWidgetMatch(Finder finder) {
  final matches = finder.evaluate();
  if (matches.length <= 1) {
    return finder;
  }
  return finder.at(0);
}

Future<void> tapConstellationControl(WidgetTester tester, Finder finder) async {
  final target = _singleWidgetMatch(finder);
  await pumpUntilVisible(tester, target);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await pumpBounded(tester, frames: 24);
}

Finder _constellationGraphLayoutFinder() {
  return find.descendant(
    of: find.byType(ConstellationBody),
    matching: find.byType(GraphLayoutView),
  );
}

/// Scene centre → global screen position for [NodeDragGesture] hit testing.
///
/// [NodeDragGesture] receives [PointerDownEvent.localPosition] in
/// [GraphLayoutView] scene space (inside [InteractiveViewer]'s child). Map scene
/// points with [RenderBox.localToGlobal], not [GraphController.sceneToViewportLocal].
Offset _globalForConstellationScene(WidgetTester tester, Offset scene) {
  final layoutFinder = _constellationGraphLayoutFinder();
  if (!finderHasMatch(layoutFinder)) {
    throw StateError('constellation GraphLayoutView not in tree');
  }
  final box = tester.renderObject<RenderBox>(layoutFinder);
  final global = box.localToGlobal(scene);
  assert(() {
    final cubit = readConstellationCubit(tester);
    final viewportLocal = cubit.graphController.sceneToViewportLocal(scene);
    if ((viewportLocal - scene).distance > 1) {
      final misMapped = box.localToGlobal(viewportLocal);
      debugPrint(
        '[e2e] constellation scene map scene=$scene '
        'viewportLocal=$viewportLocal globalViaScene=$global '
        'globalViaViewportMisMap=$misMapped',
      );
    }
    return true;
  }());
  return global;
}

/// Pointer tap at a scene point so [NodeDragGesture] hit-tests and fires
/// [GraphView.onNodeTap] (CanvasKit / web integration safe).
Future<void> tapConstellationSceneCentre(
  WidgetTester tester,
  Offset scene,
) async {
  final layoutFinder = _constellationGraphLayoutFinder();
  await pumpUntilVisible(
    tester,
    layoutFinder,
    label: 'constellation map graph layout',
    timeout: const Duration(seconds: 45),
  );
  await tester.ensureVisible(layoutFinder);
  final global = _globalForConstellationScene(tester, scene);
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.down(global);
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await pumpBounded(tester, frames: 24);
}

/// Scene-coordinate tap for overlapping map nodes (CanvasKit-safe).
Future<void> tapConstellationMapNodeInScene(
  WidgetTester tester,
  ConstellationAnchorTarget target,
) async {
  await setConstellationViewMode(tester, ConstellationViewMode.map);
  await pumpBounded(tester, frames: 24);
  final cubit = readConstellationCubit(tester);
  final graphId = constellationGraphNodeIdForTarget(target);
  await pumpUntil(
    tester,
    () =>
        cubit.graphController.renderSnapshot.resolvePosition(graphId) != null &&
        cubit.graphController.scene.layoutOutcome
            is GraphLayoutOutcomeSucceeded,
    label: 'constellation scene layout for $graphId',
    timeout: const Duration(seconds: 45),
  );
  final point = cubit.graphController.renderSnapshot.resolvePosition(graphId);
  if (point == null) {
    throw StateError('no scene position for constellation node $graphId');
  }
  final scene = Offset(point.x, point.y);
  await tapConstellationSceneCentre(tester, scene);
}

Future<void> pinConstellationPersonFromMap(
  WidgetTester tester,
  String personId,
) async {
  await setConstellationViewMode(tester, ConstellationViewMode.map);
  final target = ConstellationAnchorTarget.person(personId);
  final graphNode = find.byKey(TestIds.key(TestIds.graphNode(personId)));
  if (finderHasMatch(graphNode)) {
    await tapConstellationControl(tester, graphNode);
  } else {
    await selectConstellationPersonNode(tester, personId);
  }
  final pinButton = find.byKey(TestIds.key(TestIds.constellationPinTarget));
  await pumpUntilVisible(
    tester,
    pinButton,
    label: 'constellation person pin control',
    timeout: const Duration(seconds: 45),
  );
  await pumpUntil(
    tester,
    () {
      final cubit = readConstellationCubit(tester);
      if (!cubit.placementActionsEnabled || !cubit.canPinTarget(target)) {
        return false;
      }
      if (!finderHasMatch(pinButton)) {
        return false;
      }
      final button = tester.widget<OutlinedButton>(pinButton);
      return button.onPressed != null;
    },
    label: 'constellation person pin enabled',
    timeout: const Duration(seconds: 20),
  );
  final writesBefore = readConstellationCubit(tester).writeCount;
  await tapConstellationControl(tester, pinButton);
  await pumpBounded(tester, frames: 12);
  await pumpUntil(
    tester,
    () {
      final cubit = readConstellationCubit(tester);
      return cubit.isAnchored(target) ||
          cubit.writeCount > writesBefore ||
          cubit.state.placementFailureMessage != null;
    },
    label: 'person anchor write started or confirmed',
    timeout: const Duration(seconds: 20),
  );
  final cubit = readConstellationCubit(tester);
  if (cubit.state.placementFailureMessage != null) {
    throw StateError(
      'person pin failed: ${cubit.state.placementFailureMessage}',
    );
  }
  if (!cubit.isAnchored(target) && cubit.writeCount <= writesBefore) {
    throw StateError('person pin tap did not start anchor write');
  }
  await pumpUntil(
    tester,
    () => readConstellationCubit(tester).isAnchored(target),
    label: 'person anchor confirmed in cubit',
    timeout: const Duration(seconds: 30),
  );
}

Future<void> ensureConstellationTextRequestVisible(
  WidgetTester tester,
  String requestId,
) async {
  await pumpUntil(
    tester,
    () {
      final field = readConstellationCubit(tester).state.field;
      return field?.requests.any((request) => request.id == requestId) ?? false;
    },
    label: 'request present in constellation field',
    timeout: const Duration(seconds: 45),
  );
  await setConstellationViewMode(tester, ConstellationViewMode.text);
  final cubit = readConstellationCubit(tester);
  final authorId = cubit.state.field!.requests
      .firstWhere((request) => request.id == requestId)
      .authorId;
  final hidden = cubit.overflowHiddenCountByAuthor[authorId] ?? 0;
  if (hidden > 0 && !cubit.isSatelliteOverflowExpanded(authorId)) {
    final overflow = find.byKey(Key('constellation.overflow.$authorId'));
    if (finderHasMatch(overflow)) {
      await tapConstellationControl(tester, overflow);
    } else {
      cubit.toggleSatelliteOverflow(authorId);
      await pumpBounded(tester, frames: 12);
    }
  }
  final requestRow = find.byKey(Key('constellation.text.request.$requestId'));
  await pumpUntilVisible(tester, requestRow, label: 'constellation text request');
}

Future<void> pinConstellationRequestFromText(
  WidgetTester tester,
  String requestId,
) async {
  await ensureConstellationTextRequestVisible(tester, requestId);
  final requestRow = find.byKey(Key('constellation.text.request.$requestId'));
  final pinButton = find.descendant(
    of: requestRow,
    matching: find.byKey(TestIds.key(TestIds.constellationPinTarget)),
  );
  await pumpUntil(
    tester,
    () => readConstellationCubit(tester).placementActionsEnabled,
    label: 'constellation placement actions enabled',
    timeout: const Duration(seconds: 20),
  );
  await tapConstellationControl(tester, pinButton);
  final target = ConstellationAnchorTarget.beacon(requestId);
  await pumpUntil(
    tester,
    () => readConstellationCubit(tester).isAnchored(target),
    label: 'request anchor confirmed',
    timeout: const Duration(seconds: 30),
  );
}

Future<void> dismissConstellationRequestPreviewSheetIfPresent(
  WidgetTester tester,
) async {
  final preview = find.byKey(const Key('constellation.request_preview'));
  if (!finderHasMatch(preview)) {
    return;
  }
  final barriers = find.byType(ModalBarrier);
  if (finderHasMatch(barriers)) {
    await tester.tap(barriers.last);
    await pumpBounded(tester, frames: 12);
  }
  if (finderHasMatch(preview)) {
    await tester.drag(preview, const Offset(0, 500));
    await pumpBounded(tester, frames: 24);
  }
}

Future<void> unpinConstellationTarget(
  WidgetTester tester,
  ConstellationAnchorTarget target,
) async {
  await dismissConstellationRequestPreviewSheetIfPresent(tester);
  if (target.kind == ConstellationAnchorTargetKind.person) {
    await setConstellationViewMode(tester, ConstellationViewMode.map);
    await selectConstellationPersonNode(tester, target.id);
  } else {
    await ensureConstellationTextRequestVisible(tester, target.id);
    await tapConstellationControl(
      tester,
      find.byKey(Key('constellation.text.request.${target.id}')),
    );
  }
  await pumpUntil(
    tester,
    () => readConstellationCubit(tester).placementActionsEnabled,
    label: 'placement actions enabled before unpin',
    timeout: const Duration(seconds: 20),
  );
  final Finder unpin = switch (target.kind) {
    ConstellationAnchorTargetKind.person => find.descendant(
        of: find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        matching: find.byKey(TestIds.key(TestIds.constellationUnpinTarget)),
      ),
    ConstellationAnchorTargetKind.beacon => find.descendant(
        of: find.byKey(Key('constellation.text.request.${target.id}')),
        matching: find.byKey(TestIds.key(TestIds.constellationUnpinTarget)),
      ),
  };
  await pumpUntilVisible(tester, unpin, label: 'constellation unpin target');
  await pumpUntil(
    tester,
    () {
      final cubit = readConstellationCubit(tester);
      if (!cubit.placementActionsEnabled || !cubit.isAnchored(target)) {
        return false;
      }
      if (!finderHasMatch(unpin)) {
        return false;
      }
      final button = tester.widget<OutlinedButton>(unpin);
      return button.onPressed != null;
    },
    label: 'constellation unpin enabled',
    timeout: const Duration(seconds: 20),
  );
  final writesBefore = readConstellationCubit(tester).writeCount;
  await tapConstellationControl(tester, unpin);
  await pumpBounded(tester, frames: 12);
  await pumpUntil(
    tester,
    () {
      final cubit = readConstellationCubit(tester);
      return !cubit.isAnchored(target) ||
          cubit.writeCount > writesBefore ||
          cubit.state.placementFailureMessage != null;
    },
    label: 'constellation unpin write started or confirmed',
    timeout: const Duration(seconds: 20),
  );
  final cubit = readConstellationCubit(tester);
  if (cubit.state.placementFailureMessage != null) {
    throw StateError(
      'unpin failed: ${cubit.state.placementFailureMessage}',
    );
  }
  if (cubit.isAnchored(target) && cubit.writeCount <= writesBefore) {
    throw StateError('unpin tap did not start anchor delete');
  }
  await pumpUntil(
    tester,
    () => !readConstellationCubit(tester).isAnchored(target),
    label: 'anchor removed in cubit',
    timeout: const Duration(seconds: 30),
  );
}

Future<void> selectConstellationPersonNode(
  WidgetTester tester,
  String personId,
) async {
  final cubit = readConstellationCubit(tester);
  cubit.selectPerson(personId);
  await pumpBounded(tester);
}

Future<void> dragConstellationAnchorViaGraph({
  required WidgetTester tester,
  required ConstellationAnchorTarget target,
  required Offset dragDelta,
}) async {
  await setConstellationViewMode(tester, ConstellationViewMode.map);
  await pumpBounded(tester, frames: 24);
  final nodeFinder = find.byKey(TestIds.key(TestIds.graphNode(target.graphNodeId)));
  await pumpUntilVisible(
    tester,
    nodeFinder,
    label: 'constellation graph node ${target.graphNodeId}',
    timeout: const Duration(seconds: 45),
  );
  await tester.ensureVisible(nodeFinder);
  // GraphView node drag (P07): touch needs ~500ms long-press; mouse needs
  // pointer-down then move past slop. Hold before move for both paths.
  final gesture = await tester.startGesture(tester.getCenter(nodeFinder));
  await tester.pump(const Duration(milliseconds: 550));
  await gesture.moveBy(dragDelta);
  await pumpBounded(tester, frames: 12);
  await gesture.up();
  await pumpBounded(tester, frames: 24);
  await pumpUntil(
    tester,
    () =>
        readConstellationCubit(tester).state.placementPhase ==
        ConstellationPlacementPhase.idle,
    label: 'constellation drag settled',
    timeout: const Duration(seconds: 20),
  );
}

Future<ConstellationAnchorTarget> topmostOverlappingConstellationTarget(
  WidgetTester tester, {
  required Set<String> nodeIds,
}) async {
  final cubit = readConstellationCubit(tester);
  final ordered = cubit.orderedNodesForPaint().reversed;
  for (final node in ordered) {
    if (nodeIds.contains(node.id)) {
      final target = cubit.anchorTargetForNode(node);
      if (target != null) {
        return target;
      }
    }
  }
  throw StateError('no overlapping constellation targets in paint order');
}

Future<void> openConstellationFilters(WidgetTester tester) async {
  final filtersButton = find.byKey(const Key('constellation.app_bar.filters'));
  await pumpUntilVisible(tester, filtersButton, label: 'constellation filters');
  await tapConstellationControl(tester, filtersButton);
}

Future<void> toggleConstellationShowClosed(WidgetTester tester) async {
  final showClosed = find.byKey(TestIds.key(TestIds.constellationFilterShowClosed));
  if (!finderHasMatch(showClosed)) {
    await openConstellationFilters(tester);
  }
  await pumpUntilVisible(
    tester,
    showClosed,
    label: 'constellation show closed filter',
  );
  await tapConstellationControl(tester, showClosed);
}

Future<void> toggleConstellationParticipatedOnly(WidgetTester tester) async {
  final participatedOnly = find.byKey(
    TestIds.key(TestIds.constellationFilterParticipatedOnly),
  );
  if (!finderHasMatch(participatedOnly)) {
    await openConstellationFilters(tester);
  }
  await pumpUntilVisible(
    tester,
    participatedOnly,
    label: 'constellation participated-only filter',
  );
  await tapConstellationControl(tester, participatedOnly);
}

Future<List<Map<String, dynamic>>> fetchConstellationAnchors({
  bool showClosed = false,
  bool participatedOnly = false,
}) async {
  final response = await _postGraphQl(
    'query { constellationField(showClosed: $showClosed, participatedOnly: $participatedOnly, projection: ANCHORS) { anchorProjection { revision anchors { targetKind targetId xUnits yUnits coordinateSpaceVersion revision } } } }',
  );
  final errors = response['errors'];
  if (errors != null) {
    throw StateError('constellationField query failed: $errors');
  }
  final data = response['data'] as Map<String, dynamic>?;
  final field = data?['constellationField'] as Map<String, dynamic>?;
  final projection = field?['anchorProjection'] as Map<String, dynamic>?;
  return (projection?['anchors'] as List?)?.cast<Map<String, dynamic>>() ??
      const [];
}

Map<String, dynamic>? constellationAnchorByTarget(
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

Future<Map<String, dynamic>> upsertConstellationAnchor({
  required String targetKind,
  required String targetId,
  required double xUnits,
  required double yUnits,
  int coordinateSpaceVersion = 1,
}) async {
  final x = xUnits.toDouble().toStringAsFixed(4);
  final y = yUnits.toDouble().toStringAsFixed(4);
  final response = await _postGraphQl(
    'mutation { constellationAnchorUpsert(targetKind: $targetKind, targetId: "$targetId", xUnits: $x, yUnits: $y, coordinateSpaceVersion: $coordinateSpaceVersion) { anchor { targetKind targetId xUnits yUnits coordinateSpaceVersion revision } } }',
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

Future<void> deleteConstellationAnchor({
  required String targetKind,
  required String targetId,
}) async {
  final response = await _postGraphQl(
    'mutation { constellationAnchorDelete(targetKind: $targetKind, targetId: "$targetId") { targetKind targetId revision } }',
  );
  final errors = response['errors'];
  if (errors != null) {
    throw StateError('constellationAnchorDelete failed: $errors');
  }
}

Future<String> createPublishedBeacon({
  required String title,
  String? description,
}) async {
  final body = description ?? title;
  final response = await _postGraphQl(
    'mutation { beaconCreate(title: "${_escapeGraphQlString(title)}", description: "${_escapeGraphQlString(body)}", draft: false) { id } }',
  );
  final errors = response['errors'];
  if (errors != null) {
    throw StateError('beaconCreate failed: $errors');
  }
  final data = response['data'] as Map<String, dynamic>?;
  final id = (data?['beaconCreate'] as Map<String, dynamic>?)?['id'] as String?;
  if (id == null || id.isEmpty) {
    throw StateError('beaconCreate returned no id: $response');
  }
  return id;
}

Future<void> forwardBeaconTo({
  required String beaconId,
  required String recipientId,
}) async {
  final response = await _postGraphQl(
    'mutation { beaconForward(id: "$beaconId", recipientIds: ["$recipientId"]) { deliveredRecipientIds } }',
  );
  final errors = response['errors'];
  if (errors != null) {
    throw StateError('beaconForward failed: $errors');
  }
}

Future<void> closeBeaconForReview(String beaconId) async {
  final response = await _postGraphQl(
    'mutation { beaconClose(id: "$beaconId", expectedRequiresReviewWindow: false) { id } }',
  );
  final errors = response['errors'];
  if (errors != null) {
    throw StateError('beaconClose failed: $errors');
  }
}

Future<void> deleteBeaconById(String beaconId) async {
  final response = await _postGraphQl(
    'mutation { beaconDeleteById(id: "$beaconId") }',
  );
  final errors = response['errors'];
  if (errors != null) {
    throw StateError('beaconDeleteById failed: $errors');
  }
}

Future<void> reloadConstellation(WidgetTester tester) async {
  if (!finderHasMatch(find.byType(ConstellationBody))) {
    await openConstellation(tester);
    return;
  }
  await readConstellationCubit(tester).load();
  await waitForConstellationLoaded(tester);
}
