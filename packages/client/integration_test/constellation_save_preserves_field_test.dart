import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/widget/linear_pi_active.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'saving an arranged node and pressing Done preserves the browser Field',
    (tester) async {
      e2eDrainExceptions = false;
      await launchApp(app.main);
      await pumpBounded(tester);
      final fixture = await bootstrapFixture(runId: uniqueRunId('field-save'));
      await loginAs(tester, fixture.authorEmail);
      await userSubscribe(fixture.helperUserId);
      final request = await createPublishedBeacon(
        title: uniqueRequestTitle('Field arrangement'),
      );
      await forwardBeaconTo(
        beaconId: request,
        recipientId: fixture.helperUserId,
      );
      await upsertConstellationAnchor(
        targetKind: 'PERSON',
        targetId: fixture.helperUserId,
        xUnits: 1,
        yUnits: 1,
      );
      await openConstellation(tester);
      await reloadConstellation(tester);
      final cubit = readConstellationCubit(tester);
      await cubit.setShowClosed(true);
      cubit.setFilterTiming(const TimingFilterUndated());
      await selectConstellationPersonNode(tester, fixture.helperUserId);
      await pumpBounded(tester, frames: 120);
      await tester.tap(find.byKey(const Key('constellation.camera.arrange')));
      await pumpBounded(tester, frames: 24);
      final selection = maybeConstellationSelection(
        tester.element(find.byType(ConstellationBody)),
      )!;
      final target = ConstellationAnchorTarget.person(fixture.helperUserId);
      selection.toggle(target);
      cubit.graphController.zoomBy(1.1);
      await pumpBounded(tester, frames: 24);
      expect(selection.state.arranging, isTrue);
      expect(selection.state.contains(target), isTrue);
      final before = cubit.state;
      expect(before.status, isA<StateIsSuccess>());
      expect(before.selectedPersonId, fixture.helperUserId);
      final oldAnchor = before.confirmedProjection!.anchors.singleWhere(
        (anchor) => anchor.target == target,
      );
      final camera = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .clone();
      final emissions = <ConstellationState>[];
      final subscription = cubit.stream.listen(emissions.add);
      addTearDown(subscription.cancel);

      await dragConstellationAnchorViaGraph(
        tester: tester,
        target: target,
        dragDelta: const Offset(60, 40),
      );
      await pumpUntil(
        tester,
        () => cubit.state.confirmedProjection!.anchors.any(
          (anchor) =>
              anchor.target == target && anchor.position != oldAnchor.position,
        ),
        label: 'server acknowledgement of the moved person',
        timeout: const Duration(seconds: 30),
      );
      final saved = cubit.state.confirmedProjection!.anchors.singleWhere(
        (anchor) => anchor.target == target,
      );
      expect(saved.revision.compareTo(oldAnchor.revision), greaterThan(0));
      expect(cubit.isAnchored(target), isTrue);
      expect(find.byType(LinearPiActive), findsNothing);
      expect(find.byType(TenturaCircularProgress), findsNothing);

      await tester.tap(find.byKey(const Key('constellation.arranging.done')));
      // The web sentinel traverses browser history asynchronously. Let its
      // popstate and any subsequent route/store publications finish as well.
      final visibleStates = <ConstellationState>[];
      var sawLoadingIndicator = false;
      for (var frame = 0; frame < 120; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        sawLoadingIndicator |=
            find.byType(LinearPiActive).evaluate().isNotEmpty ||
            find.byType(TenturaCircularProgress).evaluate().isNotEmpty;
        if (find.byType(ConstellationBody).evaluate().isNotEmpty) {
          visibleStates.add(readConstellationCubit(tester).state);
        }
      }
      expect(selection.state.arranging, isFalse);
      final after = readConstellationCubit(tester).state;
      expect(after.status, isA<StateIsSuccess>());
      expect(after.field, isNotNull);
      expect(
        after.field!.loadedAt,
        before.field!.loadedAt,
        reason: 'Done must keep the existing Field snapshot after the save',
      );
      expect(
        after.selectedPersonId,
        before.selectedPersonId,
        reason: 'Done must preserve the selected person',
      );
      expect(after.filters, before.filters);
      expect(after.membershipFilters, before.membershipFilters);
      expect(after.loadGeneration, before.loadGeneration);
      expect(emissions, isNotEmpty);
      expect(visibleStates, isNotEmpty);
      expect(
        sawLoadingIndicator,
        isFalse,
        reason: 'Done must not flash the Field loading indicator',
      );
      for (final state in [...emissions, ...visibleStates]) {
        expect(state.status, isA<StateIsSuccess>());
        expect(state.field, isNotNull);
        expect(state.selectedPersonId, before.selectedPersonId);
        expect(state.filters, before.filters);
        expect(state.membershipFilters, before.membershipFilters);
      }
      final afterSelection = maybeConstellationSelection(
        tester.element(find.byType(ConstellationBody)),
      )!;
      expect(afterSelection.state.contains(target), isTrue);
      expect(
        find.byKey(const Key('constellation.selection.rings')),
        findsOneWidget,
      );
      expect(find.byType(LinearPiActive), findsNothing);
      expect(find.byType(TenturaCircularProgress), findsNothing);
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!
            .value,
        camera,
      );
      expect(
        after.composition!.anchorOverlay.anchors
            .singleWhere(
              (anchor) => anchor.target == target,
            )
            .position,
        saved.position,
      );
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
