import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_state.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_graph_scene.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_placement_marker.dart';
import 'package:tentura/features/like/data/gql/_g/like_user_by_id.req.gql.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'support/browser_graphql_transport_probe.dart';
import 'support/e2e_test_helpers.dart';

Finder _node(ConstellationAnchorTarget target) => find.byKey(
  TestIds.key(TestIds.graphNode(target.graphNodeId)),
);

Offset _position(WidgetTester tester, ConstellationAnchorTarget target) {
  final point = readConstellationCubit(tester).graphController.renderSnapshot
      .resolvePosition(constellationGraphNodeIdForTarget(target))!;
  return Offset(point.x, point.y);
}

({Offset origin, Offset probe, double scale}) _camera(WidgetTester tester) {
  final controller = readConstellationCubit(tester).graphController;
  return (
    origin: controller.sceneToViewportLocal(Offset.zero),
    probe: controller.sceneToViewportLocal(const Offset(500, 500)),
    scale: controller.cameraScale,
  );
}

Future<void> _drop(
  WidgetTester tester,
  ConstellationAnchorTarget target,
  Offset delta, {
  void Function()? beforeRelease,
}) async {
  final node = _node(target);
  await tester.ensureVisible(node);
  final camera = _camera(tester);
  final gesture = await tester.startGesture(
    tester.getCenter(node),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveBy(delta / 3);
  await tester.pump();
  expect(_camera(tester), camera);
  await gesture.moveBy(delta * (2 / 3));
  await tester.pump();
  expect(_camera(tester), camera);
  beforeRelease?.call();
  await gesture.up();
  await tester.pump();
  expect(_camera(tester), camera);
}

void _expectPoint(Offset actual, Offset expected) {
  expect(actual.dx, closeTo(expected.dx, 1));
  expect(actual.dy, closeTo(expected.dy, 1));
}

void _expectPersisted(
  List<Map<String, dynamic>> anchors,
  Map<String, dynamic> op,
) {
  final anchor = constellationAnchorByTarget(
    anchors,
    targetKind: op['targetKind'] as String,
    targetId: op['targetId'] as String,
  );
  expect(anchor, isNotNull);
  final position = op['position'] as Map<String, dynamic>;
  expect(
    anchor!['xUnits'],
    closeTo((position['xUnits'] as num).toDouble(), 1e-6),
  );
  expect(
    anchor['yUnits'],
    closeTo((position['yUnits'] as num).toDouble(), 1e-6),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'protocol release persists consecutive drops without camera movement, '
    'recovers an offline placement, and toggles trust without readbacks',
    (tester) async {
      e2eDrainExceptions = false;
      await launchApp(app.main);
      final fixture = await bootstrapFixture(
        runId: uniqueRunId('interactive-release'),
      );
      await loginAs(tester, fixture.authorEmail);
      final requestId = await createPublishedBeacon(
        title: uniqueRequestTitle('Interactive placement'),
      );
      await forwardBeaconTo(
        beaconId: requestId,
        recipientId: fixture.helperUserId,
      );
      // Setup uses the same authenticated GraphQL API as the application.
      // Start untrusted so the actual trust-toggle journey needs no withdrawal
      // confirmation dialog and can check the immediate speculative change.
      await postGraphQlAsUser(
        email: fixture.authorEmail,
        restoreEmail: fixture.authorEmail,
        request: GUserVoteReq(
          (b) => b.vars
            ..objectId = fixture.helperUserId
            ..amount = 0,
        ),
      );
      final person = ConstellationAnchorTarget.person(fixture.helperUserId);
      final request = ConstellationAnchorTarget.beacon(requestId);
      for (final (target, x) in [(person, -2.0), (request, 2.0)]) {
        await upsertConstellationAnchor(
          targetKind: target == person ? 'PERSON' : 'BEACON',
          targetId: target.id,
          xUnits: x,
          yUnits: 0,
        );
      }
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
          'network': traffic,
          'lastTraffic': network.entries,
        };
        network.dispose();
      });

      await runE2eStep(
        'consecutive drops have one apply each and no readback',
        () async {
          network
            ..clear()
            ..holdApply();
          final camera = _camera(tester);
          final beforeA = _position(tester, person);
          final beforeB = _position(tester, request);
          await _drop(tester, person, const Offset(90, 45));
          final droppedA = _position(tester, person);
          expect((droppedA - beforeA).distance, greaterThan(1));
          await pumpUntil(
            tester,
            () => network.applies.length == 1,
            label: 'first apply awaiting acknowledgement',
          );
          expect(network.applies.single['completed'], isFalse);
          // No settling helper or acknowledgement between A and B.
          await _drop(tester, request, const Offset(-70, 60));
          final droppedB = _position(tester, request);
          expect((droppedB - beforeB).distance, greaterThan(1));
          expect(_camera(tester), camera);
          network.release();
          await pumpUntil(
            tester,
            () =>
                network.applies.length == 2 &&
                network.applies.every((entry) => entry['completed'] == true),
            label: 'both placement acknowledgements',
          );
          await pumpBounded(tester, frames: 24);
          expect(network.applies, hasLength(2));
          final ops = [
            for (final entry in network.applies)
              ...((entry['variables'] as Map)['ops'] as List)
                  .cast<Map<String, dynamic>>(),
          ];
          expect(ops, hasLength(2));
          expect(ops.map((op) => op['targetId']), [person.id, request.id]);
          expect(
            network.fieldReads,
            isEmpty,
            reason: 'No ANCHORS or FULL after a drop',
          );
          expect(_camera(tester), camera);
          _expectPoint(_position(tester, person), droppedA);
          _expectPoint(_position(tester, request), droppedB);
          traffic['consecutiveDrops'] = network.entries;
          final anchors = await fetchConstellationAnchors();
          for (final op in ops) {
            _expectPersisted(anchors, op);
          }
          await runE2eStep(
            'both dropped nodes keep their positions after a full graph reload',
            () async {
              network.clear();
              await reloadConstellation(tester);
              expect(readConstellationCubit(tester).state.loadError, isNull);
              expect(
                network.fieldReads.any((entry) {
                  final variables = entry['variables'] as Map;
                  return entry['operation'] == 'ConstellationFieldFetch' &&
                      (variables['projection'] ?? 'FULL') == 'FULL' &&
                      entry['completed'] == true &&
                      entry['failed'] == false &&
                      entry['status'] == 200 &&
                      (entry['response'] as Map)['errors'] == null;
                }),
                isTrue,
                reason: 'Reload must consume a fresh successful FULL response.',
              );
              _expectPoint(_position(tester, person), droppedA);
              _expectPoint(_position(tester, request), droppedB);
              traffic['consecutiveDropsReload'] = network.entries;
            },
          );
        },
      );

      await runE2eStep(
        'offline drop stays put, shows notice and marker, and Retry persists',
        () async {
          await tapConstellationControl(
            tester,
            find.byKey(TestIds.key(TestIds.constellationFitAll)),
          );
          final l10n = L10n.of(tester.element(_node(person)))!;
          network.clear();
          await _drop(
            tester,
            person,
            const Offset(65, -40),
            beforeRelease: network.goOffline,
          );
          final dropped = _position(tester, person);
          final camera = _camera(tester);
          // The overdue notice is independent of the exhausted-retry marker.
          await tester.pump(const Duration(seconds: 14));
          expect(find.text(l10n.lazyWriteAckOverdue), findsNothing);
          await pumpUntilVisible(
            tester,
            find.text(l10n.lazyWriteAckOverdue),
            label: '15-second non-blocking saving notice',
            timeout: const Duration(seconds: 5),
          );
          final marker = find.descendant(
            of: find.byKey(ValueKey('constellation.placement.fp:${person.id}')),
            matching: find.byType(ConstellationPlacementMarker),
          );
          await pumpUntil(
            tester,
            () =>
                marker.evaluate().isNotEmpty &&
                tester.widget<ConstellationPlacementMarker>(marker).status ==
                    ConstellationPlacementMarkerStatus.notSaved,
            label: 'exhausted placement retry marker',
            timeout: const Duration(seconds: 45),
          );
          _expectPoint(_position(tester, person), dropped);
          expect(_camera(tester), camera);
          final failedOps = [
            for (final entry in network.applies)
              ...((entry['variables'] as Map)['ops'] as List)
                  .cast<Map<String, dynamic>>(),
          ];
          expect(network.applies, isNotEmpty);
          expect(
            network.applies.every((entry) => entry['failed'] == true),
            isTrue,
          );
          expect(failedOps.map((op) => op['clientOpId']).toSet(), hasLength(1));
          traffic['offlineDrop'] = network.entries;
          network
            ..restoreNetwork()
            ..clear();
          await tester.tap(marker);
          await tester.pump();
          await tester.tap(find.text(l10n.constellationPlacementRetry));
          await pumpUntil(
            tester,
            () =>
                network.applies.isNotEmpty &&
                network.applies.last['completed'] == true,
            label: 'Retry acknowledgement after connection restoration',
          );
          await pumpBounded(tester, frames: 24);
          expect(network.applies, hasLength(1));
          final retryOp =
              ((network.applies.single['variables'] as Map)['ops'] as List)
                      .single
                  as Map<String, dynamic>;
          expect(retryOp['clientOpId'], failedOps.first['clientOpId']);
          expect(network.fieldReads, isEmpty);
          expect(marker, findsNothing);
          expect(_camera(tester), camera);
          _expectPoint(_position(tester, person), dropped);
          traffic['retry'] = network.entries;
          _expectPersisted(await fetchConstellationAnchors(), retryOp);
          await reloadConstellation(tester);
          _expectPoint(_position(tester, person), dropped);
        },
      );

      await runE2eStep(
        'trust flips before acknowledgement with one write and no profile read',
        () async {
          await tapConstellationControl(
            tester,
            find.byKey(TestIds.key(TestIds.constellationFitAll)),
          );
          await tapConstellationMapNodeInScene(tester, person);
          final toggle = find.byKey(
            TestIds.key(TestIds.graphPersonContextTrust),
          );
          await pumpUntilVisible(tester, toggle, label: 'person trust toggle');
          await pumpBounded(tester, frames: 24);
          expect(tester.widget<Switch>(toggle).value, isFalse);
          network
            ..clear()
            ..holdTrust();
          await tester.tap(toggle);
          await tester.pump();
          expect(tester.widget<Switch>(toggle).value, isTrue);
          expect(tester.widget<Switch>(toggle).onChanged, isNotNull);
          final panel = find.byKey(
            TestIds.key(TestIds.graphPersonContextPanel),
          );
          expect(
            find.descendant(
              of: panel,
              matching: find.byType(CircularProgressIndicator),
            ),
            findsNothing,
          );
          await pumpUntil(
            tester,
            () => network.trustWrites.isNotEmpty,
            label: 'trust write',
          );
          expect(network.trustWrites, hasLength(1));
          expect(network.trustWrites.single['completed'], isFalse);
          expect(network.profileReads, isEmpty);
          expect(network.fieldReads, isEmpty);
          network.release();
          await pumpUntil(
            tester,
            () => network.trustWrites.single['completed'] == true,
            label: 'trust acknowledgement',
          );
          await pumpBounded(tester, frames: 24);
          expect(network.trustWrites, hasLength(1));
          expect(network.profileReads, isEmpty);
          expect(network.fieldReads, isEmpty);
          expect(tester.widget<Switch>(toggle).value, isTrue);
          traffic['trustToggle'] = network.entries;
        },
      );

      // This browser proof belongs to a newly versioned protocol release, not
      // the pre-cutover bundle. Keep the boundary fixed, independent of main.
      final version = (await PackageInfo.fromPlatform()).version;
      final parts = version.split('+').first.split('.').map(int.parse).toList();
      expect(
        parts[0] > 7 ||
            (parts[0] == 7 &&
                (parts[1] > 41 || (parts[1] == 41 && parts[2] > 23))),
        isTrue,
        reason: 'The built browser client must be newer than 7.41.23.',
      );
    },
  );
}
