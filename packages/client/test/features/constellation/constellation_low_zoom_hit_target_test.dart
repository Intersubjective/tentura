import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/domain/constellation_trust_badge.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_node_ring_layer.dart';

// #640: at low zoom the circles you tap or act on keep at least
// kMinInteractiveDimension on screen, are drawn larger than the node, and
// overlapping targets resolve to the nearest node.
void main() {
  const minTarget = kMinInteractiveDimension;
  // A 40 px person node at the bare zoom (camera scale 0.2).
  const lowZoomBody = 8.0;

  ConstellationPresentationFrame frameOf(
    List<(GraphNodeId, Offset, double)> nodes, {
    ConstellationDetailLevel detail = ConstellationDetailLevel.bare,
  }) => computeConstellationPresentationFrame(
    snapshot: const Object(),
    cameraRevision: 1,
    detail: detail,
    viewport: const Size(400, 400),
    nodesInPaintOrder: [
      for (final (id, centre, diameter) in nodes)
        ConstellationFrameNodeInput(
          id: id,
          centre: centre,
          bodyDiameter: diameter,
          badgeOverhang: 0,
          labelSize: Size.zero,
          priority: 2,
          ring: 1,
          labelCandidate: false,
        ),
    ],
    chips: const [],
    gap: 2,
    minTarget: minTarget,
    rtl: false,
  );

  group('tap target at low zoom', () {
    test('keeps at least kMinInteractiveDimension on screen', () {
      final frame = frameOf([('p', const Offset(200, 200), lowZoomBody)]);
      final body = frame.bodies['p']!;
      final target = frame.tapTargets['p']!;
      expect(body.width, lowZoomBody);
      expect(target.width, greaterThanOrEqualTo(minTarget));
      expect(target.height, greaterThanOrEqualTo(minTarget));
      expect(target.center, body.center);
    });

    test('a tap anywhere in the round target hits the tiny node', () {
      final frame = frameOf([('p', const Offset(200, 200), lowZoomBody)]);
      for (final p in const [
        Offset(223, 200),
        Offset(200, 177),
        Offset(216, 216),
      ]) {
        expect(frame.bodies['p']!.contains(p), isFalse);
        expect(resolveConstellationTap(frame, p), 'p', reason: '$p');
      }
    });

    test('the target is a circle: its square corner misses', () {
      final frame = frameOf([('p', const Offset(200, 200), lowZoomBody)]);
      const corner = Offset(222, 222);
      expect(frame.tapTargets['p']!.contains(corner), isTrue);
      expect(
        constellationTapTargetContains(frame.tapTargets['p']!, corner),
        isFalse,
      );
      expect(resolveConstellationTap(frame, corner), isNull);
    });
  });

  group('overlapping targets resolve to the nearest node', () {
    test('overlapping tap targets: nearest centre, not the later paint', () {
      final frame = frameOf([
        ('near', const Offset(200, 200), lowZoomBody),
        ('later', const Offset(230, 200), lowZoomBody),
      ]);
      const p = Offset(212, 200);
      expect(
        constellationTapTargetContains(frame.tapTargets['later']!, p),
        isTrue,
      );
      expect(resolveConstellationTap(frame, p), 'near');
      expect(resolveConstellationTap(frame, const Offset(218, 200)), 'later');
    });

    test('overlapping bodies: nearest centre, not the later paint', () {
      final frame = frameOf([
        ('near', const Offset(200, 200), 40),
        ('later', const Offset(225, 200), 40),
      ], detail: ConstellationDetailLevel.normal);
      const p = Offset(208, 200);
      expect(frame.bodies['near']!.contains(p), isTrue);
      expect(frame.bodies['later']!.contains(p), isTrue);
      expect(resolveConstellationTap(frame, p), 'near');
    });

    test(
      'a body under the pointer beats a nearer centre whose body misses',
      () {
        final frame = frameOf([
          ('big', const Offset(200, 200), 40),
          ('tiny', const Offset(226, 200), lowZoomBody),
        ], detail: ConstellationDetailLevel.normal);
        // Inside big's body, nearer tiny's centre, outside tiny's body.
        const p = Offset(218, 200);
        expect(frame.bodies['tiny']!.contains(p), isFalse);
        expect(resolveConstellationTap(frame, p), 'big');
      },
    );

    test('an exact tie keeps the later paint order', () {
      final frame = frameOf([
        ('first', const Offset(200, 200), lowZoomBody),
        ('second', const Offset(200, 200), lowZoomBody),
      ]);
      expect(resolveConstellationTap(frame, const Offset(210, 200)), 'second');
    });
  });

  group('action and trust rings', () {
    ConstellationNodeRingGeometry geometry(
      double bodyDiameter, {
      bool hasTrustRing = false,
    }) => constellationNodeRingGeometry(
      body: Rect.fromCircle(
        center: const Offset(100, 100),
        radius: bodyDiameter / 2,
      ),
      minTarget: minTarget,
      gap: 2,
      minTrustRadius: 9,
      badgeDiameter: 16,
      hasTrustRing: hasTrustRing,
      rtl: false,
    );

    test('at low zoom the action ring is the target size and larger than '
        'the node', () {
      for (final hasTrustRing in [false, true]) {
        final g = geometry(lowZoomBody, hasTrustRing: hasTrustRing);
        expect(g.showsActionRing, isTrue);
        expect(g.actionRadius * 2, greaterThanOrEqualTo(minTarget));
        expect(g.actionRadius, greaterThan(lowZoomBody / 2));
        expect(g.actionRadius, greaterThan(g.trustRadius));
      }
    });

    test('a node at least as large as a target draws no action ring', () {
      expect(geometry(minTarget).showsActionRing, isFalse);
      expect(geometry(80).showsActionRing, isFalse);
    });

    test('the trust ring hugs the body but never shrinks below its floor', () {
      expect(geometry(lowZoomBody, hasTrustRing: true).trustRadius, 9);
      final big = geometry(40, hasTrustRing: true);
      expect(big.trustRadius, greaterThan(20));
      expect(big.trustRadius, lessThan(big.actionRadius));
    });

    test('the badge sits on the ring at the bottom end', () {
      final g = geometry(40, hasTrustRing: true);
      expect((g.badgeCentre - g.centre).distance, closeTo(g.trustRadius, 1e-9));
      expect(g.badgeCentre.dx, greaterThan(g.centre.dx));
      expect(g.badgeCentre.dy, greaterThan(g.centre.dy));
      final rtl = constellationNodeRingGeometry(
        body: Rect.fromCircle(center: const Offset(100, 100), radius: 20),
        minTarget: minTarget,
        gap: 2,
        minTrustRadius: 9,
        badgeDiameter: 16,
        hasTrustRing: true,
        rtl: true,
      );
      expect(rtl.badgeCentre.dx, lessThan(rtl.centre.dx));
    });
  });

  group('ring layer paints', () {
    Future<void> pumpLayer(
      WidgetTester tester, {
      required ConstellationPresentationFrame frame,
      Map<GraphNodeId, ConstellationTrustBadge> trust = const {},
      GraphNodeId? selected,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: ConstellationNodeRingLayer(
                frame: frame,
                trustByGraphId: trust,
                selectedGraphId: selected,
              ),
            ),
          ),
        ),
      );
    }

    Finder rings() => find.byKey(const ValueKey('constellation.nodeRings'));

    testWidgets('a selected node at low zoom gets a target-size ring', (
      tester,
    ) async {
      final frame = frameOf([('p', const Offset(200, 200), lowZoomBody)]);
      await pumpLayer(tester, frame: frame, selected: 'p');
      final scheme = Theme.of(tester.element(rings())).colorScheme;
      expect(
        rings(),
        paints..circle(
          x: 200,
          y: 200,
          radius: minTarget / 2,
          color: scheme.secondary,
          style: PaintingStyle.stroke,
        ),
      );
    });

    testWidgets('mouse hover draws the action ring of the node a click hits', (
      tester,
    ) async {
      final frame = frameOf([
        ('near', const Offset(200, 200), lowZoomBody),
        ('far', const Offset(230, 200), lowZoomBody),
      ]);
      await pumpLayer(tester, frame: frame);
      final scheme = Theme.of(tester.element(rings())).colorScheme;
      expect(rings(), isNot(paints..circle()));

      final mouse = await tester.createGestureMouse();
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getTopLeft(rings()) + const Offset(212, 200));
      await tester.pump();

      final painter =
          tester.widget<CustomPaint>(rings()).painter!
              as ConstellationNodeRingPainter;
      expect(painter.hoveredGraphId, 'near');
      expect(
        rings(),
        paints..circle(
          x: 200,
          y: 200,
          radius: minTarget / 2,
          color: scheme.onSurfaceVariant,
        ),
      );
    });

    testWidgets('a node larger than a target gets no action ring', (
      tester,
    ) async {
      final frame = frameOf([
        ('p', const Offset(200, 200), 60),
      ], detail: ConstellationDetailLevel.normal);
      await pumpLayer(tester, frame: frame, selected: 'p');
      expect(rings(), isNot(paints..circle()));
    });
  });
}

extension on WidgetTester {
  Future<TestGesture> createGestureMouse() =>
      createGesture(kind: PointerDeviceKind.mouse);
}
