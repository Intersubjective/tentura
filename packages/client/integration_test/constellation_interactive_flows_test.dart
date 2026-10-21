import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_state.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_graph_scene.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/features/constellation/ui/util/layout_geometry_adapters.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_geometry.dart';

import 'support/browser_graphql_transport_probe.dart';
import 'support/e2e_test_helpers.dart';

// Issue #235 U40 web e2e for the interactive Constellation flows that
// constellation_protocol_release_test.dart (drag, failure) does not cover:
// data arriving mid-drag, Re-arrange and the map composer's person drag.

Finder _node(ConstellationAnchorTarget target) => find.byKey(
  TestIds.key(TestIds.graphNode(target.graphNodeId)),
);

Offset _position(WidgetTester tester, ConstellationAnchorTarget target) {
  final point = readConstellationCubit(tester).graphController.renderSnapshot
      .resolvePosition(constellationGraphNodeIdForTarget(target))!;
  return Offset(point.x, point.y);
}

Map<String, Offset> _allPositions(WidgetTester tester) {
  final snapshot = readConstellationCubit(
    tester,
  ).graphController.renderSnapshot;
  return {
    for (final id in snapshot.topology.nodesById.keys)
      if (snapshot.resolvePosition(id) case final point?)
        id: Offset(point.x, point.y),
  };
}

Offset _anchorPoint(double xUnits, double yUnits) {
  final point = constellationV1AnchorToPoint(
    ConstellationAnchorPosition(
      xUnits: xUnits,
      yUnits: yUnits,
      coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
    ),
  );
  return Offset(point.x, point.y);
}

void _expectPoint(Offset actual, Offset expected, {String? reason}) {
  expect(actual.dx, closeTo(expected.dx, 1), reason: reason);
  expect(actual.dy, closeTo(expected.dy, 1), reason: reason);
}

/// Placement writes the app itself sent; setup writes made through the test
/// helpers (client op ids `anchor-…`) share the browser transport.
List<Map<String, dynamic>> _appApplies(BrowserGraphqlTransportProbe network) =>
    [
      for (final entry in network.applies)
        if (((entry['variables'] as Map)['ops'] as List)
            .cast<Map<String, dynamic>>()
            .any(
              (op) => !(op['clientOpId'] as String).startsWith('anchor-'),
            ))
          entry,
    ];

ConstellationComposerCubit _composer(WidgetTester tester) =>
    tester.element(find.byType(ConstellationBody)).read();

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'data arriving mid-drag moves nothing until release, Re-arrange keeps '
    'pins and writes nothing, and a composer drag stays session-only',
    (tester) async {
      e2eDrainExceptions = false;
      await launchApp(app.main);
      final fixture = await bootstrapFixture(
        runId: uniqueRunId('interactive-flows'),
      );
      await loginAs(tester, fixture.authorEmail);
      final requestId = await createPublishedBeacon(
        title: uniqueRequestTitle('Interactive flows'),
      );
      await forwardBeaconTo(
        beaconId: requestId,
        recipientId: fixture.helperUserId,
      );
      final person = ConstellationAnchorTarget.person(fixture.helperUserId);
      final request = ConstellationAnchorTarget.beacon(requestId);
      await upsertConstellationAnchor(
        targetKind: 'PERSON',
        targetId: person.id,
        xUnits: -2,
        yUnits: 0,
      );
      await upsertConstellationAnchor(
        targetKind: 'BEACON',
        targetId: request.id,
        xUnits: 2,
        yUnits: 0,
      );
      await openConstellation(tester);
      await reloadConstellation(tester);
      await setConstellationViewMode(tester, ConstellationViewMode.map);
      await tapConstellationControl(
        tester,
        find.byKey(TestIds.key(TestIds.constellationFitAll)),
      );
      final network = BrowserGraphqlTransportProbe()..install();
      final traffic = <String, List<Map<String, dynamic>>>{};
      addTearDown(() {
        binding.reportData = {
          'completedSteps': traffic.keys.toList(),
          'network': traffic,
          'lastTraffic': network.entries,
        };
        network.dispose();
      });

      await runE2eStep(
        'refresh mid-drag: another writer and a full reload land while a '
        'node is held; nothing moves until release, then both apply',
        () async {
          network.clear();
          final cubit = readConstellationCubit(tester);
          final requestBefore = _position(tester, request);
          _expectPoint(requestBefore, _anchorPoint(2, 0));
          await tester.ensureVisible(_node(person));
          final gesture = await tester.startGesture(
            tester.getCenter(_node(person)),
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(40, 20));
          await tester.pump();
          await gesture.moveBy(const Offset(40, 20));
          await tester.pump();
          expect(
            cubit.state.placementPhase,
            ConstellationPlacementPhase.draggingExisting,
          );
          final held = _position(tester, person);

          // Another tab moves the Request: its realtime hint brings an
          // ANCHORS read while the pointer still holds the person.
          await upsertConstellationAnchor(
            targetKind: 'BEACON',
            targetId: request.id,
            xUnits: 2,
            yUnits: 1.5,
          );
          await pumpUntil(
            tester,
            () => network.fieldReads.any(
              (entry) =>
                  entry['operation'] == 'ConstellationAnchorsFetch' &&
                  entry['completed'] == true,
            ),
            label: 'ANCHORS read from the other writer while held',
            timeout: const Duration(seconds: 30),
          );
          // And a full reload (as a tab reselect does) completes mid-drag.
          bool isFull(Map<String, dynamic> entry) =>
              entry['operation'] == 'ConstellationFieldFetch';
          final fullReadsBefore = network.fieldReads.where(isFull).length;
          await cubit.load();
          await pumpUntil(
            tester,
            () =>
                network.fieldReads
                    .where((e) => isFull(e) && e['completed'] == true)
                    .length >
                fullReadsBefore,
            label: 'FULL read completed while held',
          );
          await pumpBounded(tester, frames: 24);
          expect(
            cubit.state.placementPhase,
            ConstellationPlacementPhase.draggingExisting,
            reason: 'the refresh must not take the node from the pointer',
          );
          _expectPoint(
            _position(tester, person),
            held,
            reason: 'the held node stays under the pointer',
          );
          _expectPoint(
            _position(tester, request),
            requestBefore,
            reason: 'data arriving mid-drag is not drawn before release',
          );
          expect(_appApplies(network), isEmpty);

          await gesture.up();
          await tester.pump();
          final dropped = _position(tester, person);
          await pumpUntil(
            tester,
            () =>
                _appApplies(network).isNotEmpty &&
                _appApplies(network).every((e) => e['completed'] == true) &&
                !cubit.state.hasPendingPlacementWrite,
            label: 'drop acknowledged',
          );
          await pumpBounded(tester, frames: 48);
          _expectPoint(
            _position(tester, person),
            dropped,
            reason: 'the dropped node stays where it was dropped',
          );
          _expectPoint(
            _position(tester, request),
            _anchorPoint(2, 1.5),
            reason: 'the other writer’s move is applied after release',
          );
          expect(_appApplies(network), hasLength(1));
          final op =
              ((_appApplies(network).single['variables'] as Map)['ops'] as List)
                      .single
                  as Map;
          expect(op['targetId'], person.id);
          final anchors = await fetchConstellationAnchors();
          final stored = constellationAnchorByTarget(
            anchors,
            targetKind: 'PERSON',
            targetId: person.id,
          )!;
          final position = op['position'] as Map;
          expect(
            stored['xUnits'],
            closeTo((position['xUnits'] as num).toDouble(), 1e-6),
          );
          expect(
            stored['yUnits'],
            closeTo((position['yUnits'] as num).toDouble(), 1e-6),
          );
          traffic['refreshMidDrag'] = network.entries;
        },
      );

      await runE2eStep(
        'Re-arrange re-lays out free nodes deterministically, keeps the pins '
        'and sends nothing',
        () async {
          final rearrange = find.byKey(
            TestIds.key(TestIds.constellationRearrange),
          );
          await pumpUntilVisible(
            tester,
            rearrange,
            label: 'Re-arrange after the user placed a node',
          );
          final personBefore = _position(tester, person);
          final requestBefore = _position(tester, request);
          network.clear();
          await tapConstellationControl(tester, rearrange);
          await pumpBounded(tester, frames: 48);
          _expectPoint(_position(tester, person), personBefore);
          _expectPoint(_position(tester, request), requestBefore);
          final first = _allPositions(tester);
          await tapConstellationControl(tester, rearrange);
          await pumpBounded(tester, frames: 48);
          final second = _allPositions(tester);
          expect(second.keys.toSet(), first.keys.toSet());
          for (final entry in first.entries) {
            _expectPoint(second[entry.key]!, entry.value, reason: entry.key);
          }
          expect(network.applies, isEmpty, reason: 'Re-arrange writes nothing');
          expect(network.fieldReads, isEmpty, reason: 'and reads nothing');
          final cubit = readConstellationCubit(tester);
          expect(cubit.isAnchored(person), isTrue);
          expect(cubit.isAnchored(request), isTrue);
          traffic['rearrange'] = network.entries;
        },
      );

      await runE2eStep(
        'composer: a person dragged into the circle joins the recipients '
        'without a write, and Cancel puts it back on its pin',
        () async {
          await tapConstellationControl(
            tester,
            find.byKey(TestIds.key(TestIds.constellationFitAll)),
          );
          final cubit = readConstellationCubit(tester);
          final pin = _position(tester, person);
          final ego = _position(
            tester,
            ConstellationAnchorTarget.person(fixture.authorUserId),
          );
          final away = pin + (pin - ego) / (pin - ego).distance * 160;
          cubit.panCameraTo((pin + away) / 2);
          await pumpBounded(tester, frames: 24);
          await startMapComposerAt(tester, scene: away);
          final composer = _composer(tester)..setRadius(30);
          await pumpBounded(tester, frames: 24);
          expect(cubit.state.isComposing, isTrue);
          _expectPoint(
            _position(tester, person),
            pin,
            reason: 'opening the composer does not move a pinned person',
          );
          expect(composer.selection.selected, isNot(contains(person.id)));
          final chip = find.byKey(
            Key('constellation.composer.chip.${person.id}'),
          );
          expect(chip, findsNothing);
          network.clear();

          final centre = composer.selection.center.offset;
          final controller = cubit.graphController;
          final from = _position(tester, person);
          final viewportDelta =
              controller.sceneToViewportLocal(centre) -
              controller.sceneToViewportLocal(from);
          final gesture = await tester.startGesture(
            tester.getCenter(_node(person)),
            kind: PointerDeviceKind.mouse,
          );
          const steps = 12;
          for (var i = 0; i < steps; i++) {
            await gesture.moveBy(viewportDelta / steps.toDouble());
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(
            cubit.isComposerDragActive,
            isTrue,
            reason: 'the pointer holds the person for the session',
          );
          await gesture.up();
          await tester.pump();
          final dropped = _position(tester, person);
          expect(
            (dropped - centre).distance,
            lessThan(4),
            reason: 'the person lands on the circle',
          );
          await pumpUntilVisible(
            tester,
            chip,
            label: 'dropped person becomes a recipient',
          );
          await tester.pump(const Duration(seconds: 1));
          await pumpBounded(tester, frames: 24);
          _expectPoint(
            _position(tester, person),
            dropped,
            reason: 'the person does not snap back while composing',
          );
          expect(_appApplies(network), isEmpty, reason: 'nothing is written');
          expect(
            network.fieldReads,
            isEmpty,
            reason: 'a composer drag neither recomposes nor refetches',
          );

          await tapAndSettle(
            tester,
            find.byKey(const Key('constellation.app_bar.cancel_composer')),
          );
          await pumpUntil(
            tester,
            () => !cubit.state.isComposing,
            label: 'composer closed',
          );
          await waitForConstellationLoaded(tester);
          await pumpBounded(tester, frames: 48);
          _expectPoint(
            _position(tester, person),
            pin,
            reason: 'a cancelled session puts the pinned person back',
          );
          expect(
            _appApplies(network),
            isEmpty,
            reason: 'Cancel writes nothing',
          );
          final stored = constellationAnchorByTarget(
            await fetchConstellationAnchors(),
            targetKind: 'PERSON',
            targetId: person.id,
          )!;
          _expectPoint(
            _anchorPoint(
              (stored['xUnits'] as num).toDouble(),
              (stored['yUnits'] as num).toDouble(),
            ),
            pin,
          );
          traffic['composer'] = network.entries;
        },
      );
    },
  );
}
