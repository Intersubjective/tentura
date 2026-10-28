@TestOn('vm')
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';

import 'fixtures/constellation_reference_fixture.dart';

// At this zoom the reference field is in the district detail level and the
// label collision policy leaves these nodes without a placed label.
const _zoom = 0.5;
const _hiddenPerson = 'fp:in';
const _hiddenPersonName = 'invite6';
const _hiddenRequest = 'fr:req-ego-1';
const _hiddenRequestTitle = 'Тентура: Autumn release planning';
const _labelledPerson = 'fp:am';
const _labelledPersonName = 'agent m9x4u2k7';

void main() {
  group('Hidden node label on pointer hover', () {
    late ConstellationPresentationFrameHolder holder;

    Future<void> mountZoomedOut(WidgetTester tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      holder = ConstellationPresentationFrameHolder();
      await pumpConstellationBody(
        tester,
        cubit,
        size: const Size(1200, 900),
        locale: const Locale('en'),
        presentationFrameHolder: holder,
      );
      await tester.pumpAndSettle();
      cubit.graphController.zoomBy(_zoom / cubit.graphController.cameraScale);
      await tester.pumpAndSettle();
    }

    Offset viewportOrigin(WidgetTester tester) => tester.getTopLeft(
      find.byKey(const ValueKey('constellation.nodeRings')),
    );

    /// Where a pointer lands on [id]'s node, and a spot that is no node's.
    Offset centreOf(WidgetTester tester, GraphNodeId id) {
      final frame = holder.frame!;
      final centre = frame.bodies[id]!.center;
      expect(
        resolveConstellationTap(frame, centre),
        id,
        reason: 'the pointer has to land on $id for the test to mean anything',
      );
      return viewportOrigin(tester) + centre;
    }

    Offset emptySpot(WidgetTester tester) {
      final frame = holder.frame!;
      for (var y = 5.0; y < 900; y += 25) {
        for (var x = 5.0; x < 1200; x += 25) {
          if (resolveConstellationTap(frame, Offset(x, y)) == null) {
            return viewportOrigin(tester) + Offset(x, y);
          }
        }
      }
      fail('no empty spot on the Field');
    }

    testWidgets('a mouse over a person whose label was left out shows the '
        'name, and the name goes when the mouse leaves', (tester) async {
      await mountZoomedOut(tester);
      expect(
        holder.frame!.labels,
        isNot(contains(_hiddenPerson)),
        reason: 'the person must have lost its label for this to apply',
      );
      expect(find.text(_hiddenPersonName), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: emptySpot(tester));
      await tester.pump();
      expect(find.text(_hiddenPersonName), findsNothing);

      await mouse.moveTo(centreOf(tester, _hiddenPerson));
      await tester.pump();
      expect(find.text(_hiddenPersonName), findsOneWidget);

      await mouse.moveTo(emptySpot(tester));
      await tester.pump();
      expect(find.text(_hiddenPersonName), findsNothing);
    });

    testWidgets('a mouse over a Request whose label was left out shows its '
        'title', (tester) async {
      await mountZoomedOut(tester);
      expect(holder.frame!.labels, isNot(contains(_hiddenRequest)));
      expect(find.text(_hiddenRequestTitle), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: emptySpot(tester));
      await mouse.moveTo(centreOf(tester, _hiddenRequest));
      await tester.pump();
      expect(find.text(_hiddenRequestTitle), findsOneWidget);

      await mouse.moveTo(emptySpot(tester));
      await tester.pump();
      expect(find.text(_hiddenRequestTitle), findsNothing);
    });

    testWidgets('a mouse over a node that already has a label does not '
        'draw its name a second time', (tester) async {
      await mountZoomedOut(tester);
      expect(holder.frame!.labels, contains(_labelledPerson));
      expect(find.text(_labelledPersonName), findsOneWidget);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: emptySpot(tester));
      await mouse.moveTo(centreOf(tester, _labelledPerson));
      await tester.pump();

      expect(find.text(_labelledPersonName), findsOneWidget);
    });

    testWidgets('a touch pointer held on a node whose label was left out '
        'shows no name, where a mouse at the same spot does', (tester) async {
      await mountZoomedOut(tester);
      final spot = centreOf(tester, _hiddenPerson);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: emptySpot(tester));
      await mouse.moveTo(spot);
      await tester.pump();
      expect(
        find.text(_hiddenPersonName),
        findsOneWidget,
        reason: 'the mouse reveals the name at this very spot',
      );
      await mouse.moveTo(emptySpot(tester));
      await mouse.removePointer();
      await tester.pump();
      expect(find.text(_hiddenPersonName), findsNothing);

      final touch = await tester.startGesture(
        spot,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(_hiddenPersonName), findsNothing);

      await touch.moveBy(const Offset(2, 2));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(_hiddenPersonName), findsNothing);
      await touch.cancel();
      await tester.pump();
    });
  });
}
