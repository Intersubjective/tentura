// The graph composer follows pointer drags (the draft circle, a person node)
// through the interaction layer, not through the scene composition: a pointer
// move must not recompose or lay out the field. The composer re-reads who can
// be addressed when it opens and when the field changes — never on a timer.

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/constellation/ui/util/layout_geometry_adapters.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_composer_radius.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_composer_screen_harness.dart';

/// Moves the pressed [gesture] by [moves] equal steps of [step], pumping a
/// frame after each.
Future<void> _moveInSteps(
  WidgetTester tester,
  TestGesture gesture, {
  required Offset step,
  int moves = 20,
}) async {
  for (var i = 0; i < moves; i++) {
    await gesture.moveBy(step);
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  group('Dragging the composer draft with the pointer', () {
    testWidgets('20 pointer moves run no recomposition or layout', (
      tester,
    ) async {
      final cubit = await loadComposerHarnessCubit(
        ComposerHarnessRepository(),
      );
      final composer = buildComposerHarnessComposer();
      await pumpComposerHarnessScreen(tester, cubit: cubit, composer: composer);

      final controller = cubit.graphController;
      composer
        ..start(
          BeaconKind.post,
          controller.viewportLocalToScene(
            controller.viewportSize!.center(Offset.zero),
          ),
        )
        ..setRadius(120);
      await tester.pumpAndSettle();

      // Positive control: entering the composer did recompose the scene.
      expect(cubit.state.isComposing, isTrue);
      expect(cubit.layoutReconciliationCount, greaterThan(0));

      final origin = tester.getTopLeft(
        find.byType(ConstellationComposerHandle),
      );
      final centreBefore = composer.selection.center.offset;
      final reconciliations = cubit.layoutReconciliationCount;
      final layoutRuns = controller.relayoutInvocationCount;
      final composition = cubit.state.composition;

      // Inside the circle, away from the radius handle and from any person.
      final gesture = await tester.startGesture(
        origin +
            controller.sceneToViewportLocal(
              centreBefore + Offset(0, composer.selection.radius * 0.8),
            ),
      );
      await tester.pump();
      await _moveInSteps(tester, gesture, step: const Offset(2, 0));

      expect(
        composer.selection.center.offset.dx - centreBefore.dx,
        closeTo(40 / controller.cameraScale, 0.5),
        reason: 'the draft follows all twenty 2 px pointer moves',
      );
      expect(
        cubit.layoutReconciliationCount,
        reconciliations,
        reason: 'a draft drag must not recompose the field',
      );
      expect(
        cubit.state.composition,
        same(composition),
        reason: 'a draft drag must not compose the presentation again',
      );
      expect(
        controller.relayoutInvocationCount,
        layoutRuns,
        reason: 'a draft drag must not start a scene layout',
      );
      await gesture.up();
      await tester.pump();
    });
  });

  group('Dragging a person while composing', () {
    testWidgets('20 pointer moves run no recomposition or layout', (
      tester,
    ) async {
      final cubit = await loadComposerHarnessCubit(
        ComposerHarnessRepository(),
      );
      final composer = buildComposerHarnessComposer();
      await pumpComposerHarnessScreen(tester, cubit: cubit, composer: composer);

      final controller = cubit.graphController;
      composer
        ..start(
          BeaconKind.post,
          controller.viewportLocalToScene(
            controller.viewportSize!.center(Offset.zero),
          ),
        )
        // A circle too small to hold the person: no press lands on the draft.
        ..setRadius(5);
      await tester.pumpAndSettle();

      // The graph names the person `fp:<id>`; the composer knows them as `<id>`.
      final personNode = find.byKey(TestIds.key(TestIds.graphNode('a')));
      expect(personNode, findsOneWidget, reason: 'the person is on the field');
      final personBefore = controller.getPositionOrNullForId('fp:a')!;
      expect(cubit.layoutReconciliationCount, greaterThan(0));

      // Pick the person up past the drag slop, as a real pointer does.
      final gesture = await tester.startGesture(
        tester.getCenter(personNode),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      final pickedUp = controller.getPositionOrNullForId('fp:a')!;
      expect(pickedUp, isNot(personBefore), reason: 'the pointer has the node');

      final reconciliations = cubit.layoutReconciliationCount;
      final layoutRuns = controller.relayoutInvocationCount;
      final composition = cubit.state.composition;

      await _moveInSteps(tester, gesture, step: const Offset(2, 2));

      final moved = controller.getPositionOrNullForId('fp:a')!;
      expect(
        (moved - pickedUp).distance,
        closeTo(const Offset(40, 40).distance / controller.cameraScale, 1),
        reason: 'the person follows all twenty pointer moves',
      );
      expect(
        composer.selection.positions['a']?.offset,
        moved,
        reason: 'the composer sees where the person is now',
      );
      expect(
        cubit.layoutReconciliationCount,
        reconciliations,
        reason: 'moving a person must not recompose the field',
      );
      expect(
        cubit.state.composition,
        same(composition),
        reason: 'moving a person must not compose the presentation again',
      );
      expect(
        controller.relayoutInvocationCount,
        layoutRuns,
        reason: 'moving a person must not start a scene layout',
      );
      await gesture.cancel();
      await tester.pump();
    });
  });

  group('Composer people refresh', () {
    testWidgets('reads the people on open and never on a timer', (
      tester,
    ) async {
      var reads = 0;
      buildComposerHarnessComposer(
        peopleSnapshot: () async {
          reads++;
          return (positions: const <String, Offset>{}, eligible: {'a'});
        },
      ).start(BeaconKind.post, const Offset(400, 400));
      await tester.pump();
      expect(reads, 1, reason: 'opening the composer reads the people');

      await tester.pump(const Duration(seconds: 30));

      expect(
        reads,
        1,
        reason: 'there is no periodic candidate fetch while the composer sits',
      );
    });

    testWidgets('a field hint re-reads the people once and nothing polls', (
      tester,
    ) async {
      var peers = const ['a'];
      final repository = ComposerHarnessRepository(
        () => composerHarnessField(peers: peers),
      );
      final forward = ComposerHarnessForwardRepository();
      final store = composerHarnessControlledStore(repository);
      final cubit = await loadComposerHarnessCubit(
        repository,
        forward: forward,
        fixture: store.fixture,
      );
      // The people the screen's composer reads: the cubit's own candidates.
      final composer = buildComposerHarnessComposer(
        peopleSnapshot: cubit.composerPeople,
      );
      await pumpComposerHarnessScreen(tester, cubit: cubit, composer: composer);

      composer.start(BeaconKind.post, const Offset(400, 400));
      await tester.pumpAndSettle();
      expect(
        forward.candidateReads,
        1,
        reason: 'opening the composer reads the people',
      );
      final fieldReads = repository.fetches;

      // The server hints that the field changed; the lazy window then lets the
      // store read it in full while the composer is open.
      peers = const ['a', 'b'];
      store.realtime.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.constellationField,
          aggregateId: 'global',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await tester.pump();
      store.clock.advance(const Duration(seconds: 40));
      store.wakeUp.elapse(const Duration(seconds: 40));
      await tester.pump(const Duration(seconds: 40));
      await tester.pumpAndSettle();

      expect(
        repository.fetches,
        fieldReads + 1,
        reason: 'the hint brought the changed field in',
      );
      expect(
        forward.candidateReads,
        2,
        reason: 'a changed field refreshes who can be addressed, once',
      );

      store.clock.advance(const Duration(minutes: 2));
      store.wakeUp.elapse(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();

      expect(forward.candidateReads, 2, reason: 'and nothing polls afterwards');
    });
  });
}
