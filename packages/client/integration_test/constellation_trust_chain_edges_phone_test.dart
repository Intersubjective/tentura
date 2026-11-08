// Real browser, real stack, 375x667 phone in Russian: a viewer in a chain of
// explicit mutual trust (viewer ⇄ middle ⇄ far, no trust between viewer and
// far) opens the Field and selects the middle person, then the far person.
// Each hop must be drawn as one double blue (mutual trust) edge, with no grey
// edge beside it and no dashed viewer–far edge.
//
// The phone this smoke targets is a 375x667 viewport. BROWSER_DIMENSION sets
// the whole headless Chrome window, whose own toolbar takes 139 px, so the
// run uses a 375x806 window to give the app a 375x667 viewport (measured:
// a 375x667 window leaves a 375x528 viewport):
//   BROWSER_DIMENSION=375x806 ./scripts/run_client_integration_web_local.sh \
//     integration_test/constellation_trust_chain_edges_phone_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_edge_style.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/main.dart' as app;

import 'support/e2e_test_helpers.dart';

/// The app's viewport on the target phone (not the browser window size).
const _phoneViewport = Size(375, 667);

/// Kinds of every drawn edge between person [x] and person [y], either
/// direction.
List<ConstellationEdgeKind> _pairKinds(
  ConstellationCubit cubit,
  String x,
  String y,
) {
  final ids = {'fp:$x', 'fp:$y'};
  return [
    for (final edge
        in cubit.graphController.renderSnapshot.topology.edgesById.values)
      if (ids.contains(edge.payload.source.graphNodeId) &&
          ids.contains(edge.payload.destination.graphNodeId) &&
          edge.payload.source.graphNodeId !=
              edge.payload.destination.graphNodeId)
        ConstellationEdgeKind.values.byName(
          edge.payload.semanticId.split('#').last,
        ),
  ];
}

void _expectDoubleBlue(
  WidgetTester tester,
  ConstellationCubit cubit,
  (String, String, String) pair,
  String label,
) {
  final (x, y, name) = pair;
  final kinds = _pairKinds(cubit, x, y);
  expect(
    kinds,
    hasLength(1),
    reason: '$label: exactly one edge on $name, drawn $kinds',
  );
  final context = tester.element(find.byType(ConstellationBody));
  final scheme = Theme.of(context).colorScheme;
  final style = constellationEdgeStyle(kinds.single, context.tt, scheme);
  expect(style.twin, isTrue, reason: '$label: $name is a double stroke');
  expect(style.dash, 0, reason: '$label: $name is solid');
  expect(
    style.color,
    scheme.primary,
    reason: '$label: $name is the primary (blue) colour',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('on a 375x667 phone in Russian, a chain of mutual trust is '
      'drawn as one double blue edge per hop, with no indirect edge', (
    tester,
  ) async {
    e2eDrainExceptions = false;
    await launchApp(app.main);
    await pumpBounded(tester);

    // Eve ⇄ Carol and Carol ⇄ Bob trust each other explicitly; Eve and Bob
    // have no trust between them. Eve is the viewer.
    final fixture = await bootstrapWitnessFixture(
      runId: uniqueRunId('trust-chain-edges'),
    );
    final viewer = fixture.eveUserId;
    final middle = fixture.carolUserId;
    final far = fixture.bobUserId;
    await loginAs(tester, fixture.eveEmail);
    await pumpBounded(tester, frames: 12);

    final settings = GetIt.I<SettingsCubit>();
    final localeBefore = settings.state.localePreference;
    await settings.setLocalePreference(kLocalePreferenceRu);
    addTearDown(() => settings.setLocalePreference(localeBefore));
    await pumpBounded(tester, frames: 12);

    await openConstellation(tester);
    await setConstellationViewMode(tester, ConstellationViewMode.map);
    // Trust reaches the Field's visibility asynchronously: reload until the
    // far person, two steps away, is on it.
    bool chainOnField() {
      final ids = readConstellationCubit(
        tester,
      ).graphController.renderSnapshot.topology.nodesById.keys;
      return ids.contains('fp:$middle') && ids.contains('fp:$far');
    }

    var reloads = 0;
    await pumpUntilAsync(
      tester,
      () async {
        if (chainOnField()) {
          return true;
        }
        if (++reloads % 15 == 0) {
          await reloadConstellation(tester);
        }
        return chainOnField();
      },
      label: 'both people of the chain on the Field',
      timeout: const Duration(seconds: 90),
    );

    // Precondition: the Field the server sent holds explicit trust both
    // ways on viewer–middle and middle–far, and none between viewer and far.
    final field = readConstellationCubit(tester).state.field!;
    final explicit = {
      for (final edge in [
        ...field.edges,
        ...field.resolvedAnchorProjection.supportEdges,
      ])
        if (edge.tier == 1) (edge.src, edge.dst),
    };
    expect(
      explicit,
      containsAll([
        (viewer, middle),
        (middle, viewer),
        (middle, far),
        (far, middle),
      ]),
      reason: 'the fixture must give the chain viewer ⇄ middle ⇄ far',
    );
    expect(
      explicit.where(
        (e) =>
            (e.$1 == viewer && e.$2 == far) || (e.$1 == far && e.$2 == viewer),
      ),
      isEmpty,
      reason: 'the fixture must leave viewer and far without explicit trust',
    );

    final context = tester.element(find.byType(ConstellationBody));
    // The app's whole viewport, not the Field's own area under the app bars.
    expect(
      tester.view.physicalSize / tester.view.devicePixelRatio,
      _phoneViewport,
      reason: 'the app viewport must be 375x667 (a 375x806 window)',
    );
    expect(Localizations.localeOf(context).languageCode, 'ru');

    for (final (personId, label) in [
      (middle, 'middle person selected'),
      (far, 'far person selected'),
    ]) {
      await selectConstellationPersonNode(tester, personId);
      await pumpBounded(tester, frames: 24);
      expect(
        tester.takeException(),
        isNull,
        reason: '$label must render without overflow at 375x667',
      );
      final cubit = readConstellationCubit(tester);
      _expectDoubleBlue(tester, cubit, (
        viewer,
        middle,
        'viewer–middle',
      ), label);
      _expectDoubleBlue(tester, cubit, (middle, far, 'middle–far'), label);
      expect(
        _pairKinds(cubit, viewer, far),
        isEmpty,
        reason:
            '$label: the far person is reached through the middle one, '
            'so no indirect viewer–far edge',
      );
    }
  });
}
