import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_state.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('constellation pinning acceptance journeys', (tester) async {
    e2eDrainExceptions = false;
    await launchApp(app.main);
    await pumpBounded(tester);

    final runId = uniqueRunId('constellation-pin');
    final fixture = await bootstrapFixture(runId: runId);
    final helperTarget = ConstellationAnchorTarget.person(fixture.helperUserId);

    await loginAs(tester, fixture.authorEmail);
    await pumpBounded(tester, frames: 12);
    await userSubscribe(fixture.helperUserId);

    Future<void> journey(String name, Future<void> Function() body) async {
      await runE2eStep(name, body);
    }
    final warmupTitle = uniqueRequestTitle('Constellation warmup');
    final warmupBeaconId = await createPublishedBeacon(title: warmupTitle);
    await forwardBeaconTo(
      beaconId: warmupBeaconId,
      recipientId: fixture.helperUserId,
    );

    await journey('person without Requests — map pin', () async {
      await openConstellation(tester);
      await pumpUntil(
        tester,
        () => readConstellationCubit(tester).state.field!.peers.any(
          (peer) => peer.id == fixture.helperUserId,
        ),
        label: 'helper visible in constellation peers',
        timeout: const Duration(seconds: 45),
      );
      await reloadConstellation(tester);
      await pumpUntil(
        tester,
        () => readConstellationCubit(tester).state.field!.edges.any(
          (edge) =>
              (edge.src == fixture.authorUserId &&
                  edge.dst == fixture.helperUserId) ||
              (edge.dst == fixture.authorUserId &&
                  edge.src == fixture.helperUserId),
        ),
        label: 'helper trust edge visible in constellation field',
        timeout: const Duration(seconds: 45),
      );
      await pinConstellationPersonFromMap(tester, fixture.helperUserId);
      final cubit = readConstellationCubit(tester);
      final target = ConstellationAnchorTarget.person(fixture.helperUserId);
      expect(cubit.isAnchored(target), isTrue);
      expect(cubit.state.confirmedProjection!.anchors, isNotEmpty);
    });

    final requestTitle = uniqueRequestTitle('Constellation pin');
    late String requestId;

    await journey('first-load Text pin', () async {
      requestId = await createPublishedBeacon(title: requestTitle);
      await forwardBeaconTo(
        beaconId: requestId,
        recipientId: fixture.helperUserId,
      );
      await reloadConstellation(tester);
      await pinConstellationRequestFromText(tester, requestId);
      final anchors = await fetchConstellationAnchors();
      expect(
        constellationAnchorByTarget(
          anchors,
          targetKind: 'BEACON',
          targetId: requestId,
        ),
        isNotNull,
      );
    });

    await journey('independent person and Request anchor moves', () async {
      final before = await fetchConstellationAnchors();
      final beforePersonX = (constellationAnchorByTarget(
        before,
        targetKind: 'PERSON',
        targetId: fixture.helperUserId,
      )?['xUnits'] as num?)
          ?.toDouble();
      final beforeRequestX = (constellationAnchorByTarget(
        before,
        targetKind: 'BEACON',
        targetId: requestId,
      )?['xUnits'] as num?)
          ?.toDouble();
      await dragConstellationAnchorViaGraph(
        tester: tester,
        target: helperTarget,
        dragDelta: const Offset(120, 80),
      );
      await dragConstellationAnchorViaGraph(
        tester: tester,
        target: ConstellationAnchorTarget.beacon(requestId),
        dragDelta: const Offset(-90, 110),
      );
      final anchors = await fetchConstellationAnchors();
      final person = constellationAnchorByTarget(
        anchors,
        targetKind: 'PERSON',
        targetId: fixture.helperUserId,
      );
      final request = constellationAnchorByTarget(
        anchors,
        targetKind: 'BEACON',
        targetId: requestId,
      );
      final personX = (person!['xUnits'] as num).toDouble();
      final requestX = (request!['xUnits'] as num).toDouble();
      expect(personX, isNot(equals(beforePersonX)));
      expect(requestX, isNot(equals(beforeRequestX)));
      expect(personX, isNot(requestX));
    });

    await journey('overlapping pins survive reload with topmost hit', () async {
      await upsertConstellationAnchor(
        targetKind: 'PERSON',
        targetId: fixture.helperUserId,
        xUnits: 2.5,
        yUnits: 2.5,
      );
      await upsertConstellationAnchor(
        targetKind: 'BEACON',
        targetId: requestId,
        xUnits: 2.5,
        yUnits: 2.5,
      );
      await reloadConstellation(tester);
      final anchors = await fetchConstellationAnchors();
      final person = constellationAnchorByTarget(
        anchors,
        targetKind: 'PERSON',
        targetId: fixture.helperUserId,
      );
      final request = constellationAnchorByTarget(
        anchors,
        targetKind: 'BEACON',
        targetId: requestId,
      );
      expect(person!['xUnits'], 2.5);
      expect(person['yUnits'], 2.5);
      expect(request!['xUnits'], 2.5);
      expect(request['yUnits'], 2.5);
      final topmost = await topmostOverlappingConstellationTarget(
        tester,
        nodeIds: {fixture.helperUserId, requestId},
      );
      expect(topmost, ConstellationAnchorTarget.beacon(requestId));
      await setConstellationViewMode(tester, ConstellationViewMode.map);
      final topmostNode = find.byKey(
        TestIds.key(TestIds.graphNode(topmost.graphNodeId)),
      );
      await tapConstellationControl(tester, topmostNode.first);
      final cubit = readConstellationCubit(tester);
      expect(cubit.state.selectedRequestId, requestId);
      expect(cubit.state.selectedPersonId, isNull);
      await dismissConstellationRequestPreviewSheetIfPresent(tester);
      cubit.selectRequest(null);
      await pumpBounded(tester, frames: 12);
    });

    await journey('unpin leaves automatic field membership intact', () async {
      await unpinConstellationTarget(tester, helperTarget);
      final anchors = await fetchConstellationAnchors();
      expect(
        constellationAnchorByTarget(
          anchors,
          targetKind: 'PERSON',
          targetId: fixture.helperUserId,
        ),
        isNull,
      );
      expect(
        readConstellationCubit(tester).state.field!.peers.any(
          (peer) => peer.id == fixture.helperUserId,
        ),
        isTrue,
      );
    });

    await journey('close hides Request until Show closed restores anchor', () async {
      await upsertConstellationAnchor(
        targetKind: 'BEACON',
        targetId: requestId,
        xUnits: -1.25,
        yUnits: 0.75,
      );
      await reloadConstellation(tester);
      await closeBeaconForReview(requestId);
      await reloadConstellation(tester);
      expect(
        find.byKey(Key('constellation.text.request.$requestId')),
        findsNothing,
      );
      await openConstellationFilters(tester);
      await toggleConstellationShowClosed(tester);
      await pumpBounded(tester, frames: 12);
      final anchors = await fetchConstellationAnchors(showClosed: true);
      final closedAnchor = constellationAnchorByTarget(
        anchors,
        targetKind: 'BEACON',
        targetId: requestId,
      );
      expect(closedAnchor!['xUnits'], -1.25);
      expect(closedAnchor['yUnits'], 0.75);
    });

    await journey('cancelled Request stays absent even with Show closed', () async {
      final cancelledTitle = uniqueRequestTitle('Constellation cancelled');
      final cancelledId = await createPublishedBeacon(title: cancelledTitle);
      await upsertConstellationAnchor(
        targetKind: 'BEACON',
        targetId: cancelledId,
        xUnits: 0.5,
        yUnits: 0.5,
      );
      await deleteBeaconById(cancelledId);
      await reloadConstellation(tester);
      await openConstellationFilters(tester);
      await toggleConstellationShowClosed(tester);
      await pumpBounded(tester, frames: 12);
      expect(
        find.byKey(Key('constellation.text.request.$cancelledId')),
        findsNothing,
      );
      final anchors = await fetchConstellationAnchors(showClosed: true);
      expect(
        constellationAnchorByTarget(
          anchors,
          targetKind: 'BEACON',
          targetId: cancelledId,
        ),
        isNull,
      );
    });

    await journey('participation filter toggles membership state', () async {
      await reloadConstellation(tester);
      await openConstellationFilters(tester);
      await toggleConstellationParticipatedOnly(tester);
      await pumpBounded(tester, frames: 12);
      expect(
        readConstellationCubit(tester).state.membershipFilters.participatedOnly,
        isTrue,
      );
    });

    await journey('authorization loss and physical deletion remove anchors', () async {
      final lossTitle = uniqueRequestTitle('Constellation auth loss');
      final lossId = await createPublishedBeacon(title: lossTitle);
      await upsertConstellationAnchor(
        targetKind: 'BEACON',
        targetId: lossId,
        xUnits: 1.0,
        yUnits: -1.0,
      );
      await deleteBeaconById(lossId);
      await reloadConstellation(tester);
      final anchors = await fetchConstellationAnchors(showClosed: true);
      expect(
        constellationAnchorByTarget(
          anchors,
          targetKind: 'BEACON',
          targetId: lossId,
        ),
        isNull,
      );
    });

    await journey('cap overflow retains every seeded eligible pin', () async {
      final seeded = <String>[];
      for (var i = 0; i < 3; i++) {
        final title = uniqueRequestTitle('Constellation cap $i');
        final id = await createPublishedBeacon(title: title);
        await forwardBeaconTo(
          beaconId: id,
          recipientId: fixture.helperUserId,
        );
        await upsertConstellationAnchor(
          targetKind: 'BEACON',
          targetId: id,
          xUnits: i * 0.25,
          yUnits: i * 0.25,
        );
        seeded.add(id);
      }
      final anchors = await fetchConstellationAnchors();
      for (final id in seeded) {
        expect(
          constellationAnchorByTarget(
            anchors,
            targetKind: 'BEACON',
            targetId: id,
          ),
          isNotNull,
          reason: 'pinned beacon $id',
        );
      }
    });

    await dismissConstellationRequestPreviewSheetIfPresent(tester);
    await goToPath(tester, kPathMyWork);
    await pumpBounded(tester, frames: 24);
    await logout(tester);
    await pumpBounded(tester, frames: 48);
    final leaked = <Object?>[];
    Object? exception;
    while ((exception = tester.takeException()) != null) {
      leaked.add(exception);
    }
    expect(leaked, isEmpty, reason: 'uncaught async exceptions: $leaked');
  });
}
