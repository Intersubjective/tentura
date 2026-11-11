// Public API setup followed by the real browser's main Activity feed.
// Run at a 375x667 viewport (Chrome window 375x806), in both locales.
import 'package:ferry/ferry.dart' show OperationRequest;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/features/beacon_view/data/gql/_g/beacon_help_offer_accept.req.gql.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_path_chain_row.dart';
import 'package:tentura/features/closure/data/gql/_g/beacon_close.req.gql.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart'
    show ConstellationEdgeKind;
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/forward/data/gql/_g/beacon_offer_help.req.gql.dart';
import 'package:tentura/features/forward/data/gql/_g/forward_beacon.req.gql.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/features/invitation/data/gql/_g/invitation_accept.req.gql.dart';
import 'package:tentura/features/invitation/data/gql/_g/invitation_create.req.gql.dart';
import 'package:tentura/features/profile/data/gql/_g/profile_update.req.gql.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

class _Journey {
  const _Journey(this.people, this.id, this.title);
  final IntegrationWitnessFixture people;
  final String id;
  final String title;

  Future<Map<String, dynamic>> asUser(
    String email,
    OperationRequest<Object?, Object?> request,
  ) => postGraphQlAsUser(
    email: email,
    restoreEmail: people.bobEmail,
    request: request,
  );

  Future<void> close() async {
    await asUser(
      people.aliceEmail,
      GBeaconCloseReq((b) => b.vars.beaconId = id),
    );
  }
}

Future<_Journey> _acceptedRequest(WidgetTester tester, String locale) async {
  await launchApp(app.main);
  e2eDrainExceptions = false;
  await pumpSettleBounded(tester);
  // setSurfaceSize alone leaves Flutter web MediaQuery at the real window
  // size. Require the runner's 375x806 Chrome window to deliver 375x667.
  expect(
    tester.view.physicalSize / tester.view.devicePixelRatio,
    const Size(375, 667),
    reason: 'this browser journey must run in a real 375x667 viewport',
  );
  final context = tester.element(find.byType(Navigator).first);
  expect(MediaQuery.sizeOf(context), const Size(375, 667));
  final people = await bootstrapWitnessFixture(
    runId: uniqueRunId('helped-card'),
  );
  await logout(tester);
  await loginAs(tester, people.aliceEmail);
  // Fresh QA accounts share the default name. Give the four participants
  // distinct names through the profile API before freezing the receipt path.
  for (final person in [
    (people.aliceEmail, people.aliceUserId, 'Anna'),
    (people.bobEmail, people.bobUserId, 'Boris'),
    (people.carolEmail, people.carolUserId, 'Kira'),
    (people.eveEmail, people.eveUserId, 'Vera'),
  ]) {
    final updated = await postGraphQlAsUser(
      email: person.$1,
      restoreEmail: people.aliceEmail,
      request: GProfileUpdateReq((b) => b.vars.displayName = person.$3),
    );
    expect(((updated['data'] as Map)['userUpdate'] as Map)['id'], person.$2);
  }
  // The fixture has only a one-way Alice -> Bob vouch. Use the normal contact
  // invitation so this is an actual routable four-person forwarding chain.
  final invitation = await postGraphQlAsUser(
    email: people.aliceEmail,
    restoreEmail: people.aliceEmail,
    request: GInvitationCreateReq((b) => b.vars.addresseeName = 'Bob'),
  );
  final invitationId =
      ((invitation['data'] as Map)['invitationCreate'] as Map)['id'] as String;
  await postGraphQlAsUser(
    email: people.bobEmail,
    restoreEmail: people.aliceEmail,
    request: GInvitationAcceptReq((b) => b.vars.id = invitationId),
  );
  final title = uniqueRequestTitle('Help found through friends');
  final id = await createPublishedBeacon(title: title);
  await forwardBeaconTo(beaconId: id, recipientId: people.bobUserId);
  final journey = _Journey(people, id, title);
  for (final hop in [
    (people.bobEmail, people.carolUserId),
    (people.carolEmail, people.eveUserId),
  ]) {
    final forwarded = await journey.asUser(
      hop.$1,
      GForwardBeaconReq(
        (b) => b.vars
          ..beaconId = id
          ..recipientIds.add(hop.$2),
      ),
    );
    expect(
      ((forwarded['data'] as Map)['beaconForward']
          as Map)['deliveredRecipientIds'],
      contains(hop.$2),
    );
  }
  await journey.asUser(
    people.eveEmail,
    GBeaconOfferHelpReq((b) => b.vars.beaconId = id),
  );
  await journey.asUser(
    people.aliceEmail,
    GAcceptHelpOfferReq(
      (b) => b.vars
        ..beaconId = id
        ..offerUserId = people.eveUserId,
    ),
  );
  await logout(tester);
  await loginAs(tester, people.bobEmail);
  await GetIt.I<SettingsCubit>().setLocalePreference(locale);
  await pumpBounded(tester, frames: 12);
  return journey;
}

Finder _card(String id) => find.byWidgetPredicate(
  (widget) => widget is RequestAttentionCard && widget.beacon.id == id,
);

Finder _row(String id) => find.descendant(
  of: _card(id),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is AttentionMiniCard &&
        widget.receipt.presentationKey == 'forward_helped',
  ),
);

Future<void> _activity(WidgetTester tester) async {
  await goToPath(tester, kPathInbox);
  await GetIt.I<AttentionCase>().refresh();
  await pumpUntilVisible(tester, find.byType(ActivityStreamView));
  await pumpBounded(tester, frames: 20);
}

Future<L10n> _expectRow(
  WidgetTester tester,
  _Journey journey, {
  required bool done,
}) async {
  await pumpUntilVisible(
    tester,
    _row(journey.id),
    label: 'forward-helped row on main Activity Request card',
  );
  final row = _row(journey.id);
  await tester.ensureVisible(row);
  await pumpBounded(tester);
  final l10n = L10n.of(tester.element(row))!;
  final ru = l10n.localeName == 'ru';
  final headline = ru ? '✨ Ваша пересылка помогла' : '✨ Your forward helped';
  expect(
    find.descendant(
      of: row,
      matching: find.text(
        done ? '$headline · ${ru ? 'Готово' : 'Done'} ✓' : headline,
      ),
    ),
    findsOneWidget,
  );
  final action = find.descendant(
    of: row,
    matching: find.text(l10n.updatesForwardHelpedSeePath),
  );
  expect(action.hitTestable(), findsOneWidget);
  final dismiss = find.descendant(
    of: row,
    matching: find.byKey(AttentionMiniCard.dismissKey),
  );
  expect(dismiss.hitTestable(), findsOneWidget);
  final icon = tester.widget<Icon>(
    find.descendant(of: dismiss, matching: find.byIcon(Icons.close)),
  );
  expect(icon.semanticLabel?.trim(), isNotEmpty);
  expect(
    find.descendant(
      of: dismiss,
      matching: find.bySemanticsLabel(icon.semanticLabel!),
    ),
    findsWidgets,
  );
  expect(tester.takeException(), isNull);
  return l10n;
}

Future<void> _dismiss(WidgetTester tester, _Journey journey) async {
  await tester.tap(
    find.descendant(
      of: _row(journey.id),
      matching: find.byKey(AttentionMiniCard.dismissKey),
    ),
  );
  await pumpUntil(
    tester,
    () => !finderHasMatch(_row(journey.id)),
    label: 'forward-helped row dismissed',
  );
  await _activity(tester);
  expect(
    _row(journey.id),
    findsNothing,
    reason: 'receipt stays cleared after a server-backed feed reload',
  );
}

// Accept either supported destination. Both branches assert the rendered
// Request and people/path, not merely that a navigation callback ran.
Future<void> _expectLanding(
  WidgetTester tester,
  _Journey journey,
  L10n l10n, {
  required bool closed,
}) async {
  await pumpUntil(
    tester,
    () =>
        finderHasMatch(
          find.byKey(const Key('constellation.selection_unavailable')),
        ) ||
        finderHasMatch(find.byType(HelpPathChainRow)) ||
        (finderHasMatch(
              find.byKey(const Key('constellation.forward_tree.close')),
            ) &&
            [
              journey.people.aliceUserId,
              journey.people.bobUserId,
              journey.people.carolUserId,
              journey.people.eveUserId,
            ].every(
              (person) => finderHasMatch(
                find.byKey(TestIds.key(TestIds.graphNode(person))),
              ),
            )),
    label: 'Request help path landing view',
  );
  expect(
    find.byKey(const Key('constellation.selection_unavailable')),
    findsNothing,
  );
  expect(find.text(l10n.constellationSelectionUnavailable), findsNothing);
  expect(findRequestTitle(journey.title), findsWidgets);
  if (finderHasMatch(find.byType(HelpPathChainRow))) {
    final path = tester.widget<HelpPathChainRow>(
      find.byType(HelpPathChainRow).first,
    );
    expect(
      path.path.map((node) => node.userId),
      containsAll([journey.people.bobUserId, journey.people.eveUserId]),
    );
    for (final id in [journey.people.bobUserId, journey.people.eveUserId]) {
      final node = path.path.singleWhere((node) => node.userId == id);
      expect(node.displayName, isNotNull);
      expect(
        find.descendant(
          of: find.byType(HelpPathChainRow).first,
          matching: find.text(node.displayName!),
        ),
        findsOneWidget,
        reason: 'the selected help path renders both the viewer and its helper',
      );
    }
    final bounds = tester.getRect(find.byType(HelpPathChainRow).first);
    for (final node in path.path.where((node) => node.displayName != null)) {
      final name = find.descendant(
        of: find.byType(HelpPathChainRow).first,
        matching: find.text(node.displayName!),
      );
      expect(name, findsOneWidget);
      final rect = tester.getRect(name);
      expect(rect.left, greaterThanOrEqualTo(bounds.left));
      expect(rect.right, lessThanOrEqualTo(bounds.right));
    }
  } else {
    expect(find.byType(ConstellationBody), findsOneWidget);
    final cubit = readConstellationCubit(tester);
    expect(cubit.state.forwardTreeOverlay?.beaconId, journey.id);
    expect(
      cubit.state.forwardTreeOverlay?.helpOffererFocusId,
      journey.people.eveUserId,
    );
    for (final person in [
      journey.people.aliceUserId,
      journey.people.bobUserId,
      journey.people.carolUserId,
      journey.people.eveUserId,
    ]) {
      expect(
        find.byKey(TestIds.key(TestIds.graphNode(person))),
        findsOneWidget,
      );
    }
    final renderedHelpEdges = cubit
        .graphController
        .renderSnapshot
        .topology
        .edgesById
        .values
        .where(
          (edge) =>
              cubit.edgeKindByPair[edge.payload.semanticId] ==
              ConstellationEdgeKind.helpBranch,
        );
    expect(
      renderedHelpEdges,
      isNotEmpty,
      reason: 'the Field must actually draw the successful help path',
    );
    expect(
      renderedHelpEdges.any(
        (edge) =>
            edge.payload.source.graphNodeId ==
                'fp:${journey.people.bobUserId}' ||
            edge.payload.destination.graphNodeId ==
                'fp:${journey.people.bobUserId}',
      ),
      isTrue,
    );
    final successfulPairs = {
      for (final edge in renderedHelpEdges)
        (edge.payload.source.graphNodeId, edge.payload.destination.graphNodeId),
    };
    expect(
      successfulPairs,
      containsAll([
        ('fp:${journey.people.aliceUserId}', 'fp:${journey.people.bobUserId}'),
        ('fp:${journey.people.bobUserId}', 'fp:${journey.people.carolUserId}'),
        ('fp:${journey.people.carolUserId}', 'fp:${journey.people.eveUserId}'),
      ]),
      reason:
          'the painted successful branch connects the author through the viewer to this helper',
    );
  }
  if (closed && finderHasMatch(find.byType(HelpPathChainRow))) {
    expect(find.text(l10n.closureHelpPathTitle), findsWidgets);
  }
  expect(tester.takeException(), isNull);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final locale in ['en', 'ru']) {
    for (final closed in [false, true]) {
      testWidgets(
        'Show on Field opens the ${closed ? 'closed' : 'open'} Request and its help path in $locale',
        (tester) async {
          // Disposed in the body: flutter_test checks for live handles before
          // tearDowns run.
          final semantics = binding.ensureSemantics();
          try {
            final journey = await _acceptedRequest(tester, locale);
            if (closed) await journey.close();
            await _activity(tester);
            final l10n = await _expectRow(tester, journey, done: closed);
            await tester.tap(
              find.descendant(
                of: _row(journey.id),
                matching: find.text(l10n.updatesForwardHelpedSeePath),
              ),
            );
            await _expectLanding(tester, journey, l10n, closed: closed);
          } finally {
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
    testWidgets(
      'the browser dismisses an accepted row and receives a dismissible Done row after close in $locale',
      (tester) async {
        final semantics = binding.ensureSemantics();
        try {
          final journey = await _acceptedRequest(tester, locale);
          await _activity(tester);
          await _expectRow(tester, journey, done: false);
          await _dismiss(tester, journey);
          await journey.close();
          await _activity(tester);
          await _expectRow(tester, journey, done: true);
          await _dismiss(tester, journey);
        } finally {
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
