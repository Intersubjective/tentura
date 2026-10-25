import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_nearest_ring.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_ring_caption.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'fixtures/constellation_arrange_harness.dart';

/// While a node is dragged, the trust ring nearest to it is highlighted with
/// a caption naming how many trust steps from the viewer that ring is.

const _gap = kConstellationRingUnitPixels;
const ({double x, double y}) _ego = (x: 100, y: -40);

({double x, double y}) _at(double distance, [double angle = 0]) => (
  x: _ego.x + math.cos(angle) * distance,
  y: _ego.y + math.sin(angle) * distance,
);

void main() {
  group('nearest ring while dragging', () {
    test('a point on a ring snaps to that ring', () {
      final ring = constellationNearestRing(centre: _ego, point: _at(2 * _gap));

      expect(ring.steps, 2);
      expect(ring.radius, closeTo(2 * _gap, 1e-9));
    });

    test('a point between two rings snaps to the closer one', () {
      expect(
        constellationNearestRing(centre: _ego, point: _at(2.4 * _gap)).steps,
        2,
      );
      expect(
        constellationNearestRing(centre: _ego, point: _at(2.6 * _gap)).steps,
        3,
      );
    });

    test('the direction from the viewer does not matter', () {
      for (final angle in [0.0, 1.0, 2.5, -2.0, math.pi]) {
        final ring = constellationNearestRing(
          centre: _ego,
          point: _at(3 * _gap, angle),
        );
        expect(ring.steps, 3, reason: 'angle $angle');
      }
    });

    test(
      'a point on the viewer snaps to the first ring, never to step zero',
      () {
        expect(constellationNearestRing(centre: _ego, point: _ego).steps, 1);
        expect(
          constellationNearestRing(centre: _ego, point: _at(0.2 * _gap)).steps,
          1,
        );
      },
    );
  });

  group('ring caption', () {
    Future<void> pump(WidgetTester tester, int steps) => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: ConstellationRingCaption(steps: steps)),
      ),
    );

    testWidgets('reads the number of steps', (tester) async {
      await pump(tester, 3);

      expect(find.text('3 steps'), findsOneWidget);
    });

    testWidgets('shows the new count when given another step count', (
      tester,
    ) async {
      await pump(tester, 3);
      await pump(tester, 4);

      expect(find.text('4 steps'), findsOneWidget);
      expect(find.text('3 steps'), findsNothing);
    });
  });

  group('ring caption on the Field', () {
    Future<void> dragThreeStepsOut(
      WidgetTester tester,
      ArrangeHarness harness,
    ) async {
      await pumpArrangeBody(tester, harness.cubit, arrangeV2Enabled: true);
      final ego = harness.cubit.graphController.getPositionForId('fp:ego');
      harness.cubit.beginDragExisting(target: arrangePersonOne);
      harness.cubit.updateDragPresentation(
        nodeId: 'fp:p1',
        sceneCentre: ego + const Offset(3 * _gap, 0),
      );
      await tester.pump();
    }

    testWidgets('shows the steps of the nearest ring while dragging', (
      tester,
    ) async {
      final harness = await arrangeHarness();

      await dragThreeStepsOut(tester, harness);

      expect(find.text('3 steps'), findsOneWidget);
    });

    testWidgets('moves to the new nearest ring as the drag point moves', (
      tester,
    ) async {
      final harness = await arrangeHarness();
      await dragThreeStepsOut(tester, harness);
      final ego = harness.cubit.graphController.getPositionForId('fp:ego');

      for (final steps in [5, 2, 4]) {
        harness.cubit.updateDragPresentation(
          nodeId: 'fp:p1',
          sceneCentre: ego + Offset(0, steps * _gap),
        );
        await tester.pump();

        expect(find.text('$steps steps'), findsOneWidget, reason: '$steps');
        expect(find.byType(ConstellationRingCaption), findsOneWidget);
      }
    });

    testWidgets('shows no caption when nothing is being dragged', (
      tester,
    ) async {
      final harness = await arrangeHarness();

      await pumpArrangeBody(tester, harness.cubit, arrangeV2Enabled: true);

      expect(find.byType(ConstellationRingCaption), findsNothing);
    });
  });
}
