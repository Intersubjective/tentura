import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/features/constellation/domain/entity/constellation_anchor.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_state.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('constellation pinning acceptance journeys', (tester) async {
    await launchApp(app.main);
    await pumpBounded(tester);

    final runId = uniqueRunId('constellation-pin');
    final fixture = await bootstrapFixture(runId: runId);
    final helperTarget = ConstellationAnchorTarget.person(fixture.helperUserId);

    await loginAs(tester, fixture.authorEmail);

    await runE2eStep('person without Requests — map pin', () async {
      await openConstellation(tester);
      await pinConstellationPersonFromMap(tester, fixture.helperUserId);
      final anchors = await fetchConstellationAnchors();
      final anchor = constellationAnchorByTarget(
        anchors,
        targetKind: 'PERSON',
        targetId: fixture.helperUserId,
      );
      expect(anchor, isNotNull);
      expect((anchor!['xUnits'] as num).toDouble(), isNot(0.0));
    });

    final requestTitle = uniqueRequestTitle('Constellation pin');
    late String requestId;

    await runE2eStep('first-load Text pin', () async {
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

    await runE2eStep('independent person and Request anchor moves', () async {
      const personCentre = Offset(2200, 2100);
      const requestCentre = Offset(1800, 2300);
      await moveConstellationAnchorViaCubit(
        tester: tester,
        target: helperTarget,
        sceneCentre: personCentre,
      );
      await moveConstellationAnchorViaCubit(
        tester: tester,
        target: ConstellationAnchorTarget.beacon(requestId),
        sceneCentre: requestCentre,
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
      expect((person!['xUnits'] as num).toDouble(), closeTo(1.18, 0.2));
      expect((request!['xUnits'] as num).toDouble(), closeTo(-1.46, 0.2));
    });

    await runE2eStep('overlapping pins survive reload with stable coordinates', () async {
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
      expect(
        find.byKey(TestIds.key(TestIds.constellationPinMarker)),
        findsWidgets,
      );
    });

    await runE2eStep('unpin leaves automatic field membership intact', () async {
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
      await setConstellationViewMode(tester, ConstellationViewMode.map);
      expect(
        find.byKey(TestIds.key(TestIds.graphNode(fixture.helperUserId))),
        findsWidgets,
      );
    });

    await runE2eStep('close hides Request until Show closed restores anchor', () async {
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

    await runE2eStep('cancelled Request stays absent even with Show closed', () async {
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

    await runE2eStep('participation filter toggles membership state', () async {
      await reloadConstellation(tester);
      await openConstellationFilters(tester);
      await toggleConstellationParticipatedOnly(tester);
      await pumpBounded(tester, frames: 12);
      expect(
        readConstellationCubit(tester).state.membershipFilters.participatedOnly,
        isTrue,
      );
    });

    await runE2eStep('authorization loss and physical deletion remove anchors', () async {
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

    await runE2eStep('cap overflow retains every seeded eligible pin', () async {
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
  });
}
