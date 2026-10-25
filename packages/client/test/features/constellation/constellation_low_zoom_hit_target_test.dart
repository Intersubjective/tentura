import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/domain/constellation_trust_chain.dart';
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
    ConstellationDetailLevel detail = ConstellationDetailLevel.overview,
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
      ], detail: ConstellationDetailLevel.close);
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
        ], detail: ConstellationDetailLevel.close);
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

  group('action ring and trust disc', () {
    ConstellationNodeRingGeometry geometry(double bodyDiameter) =>
        constellationNodeRingGeometry(
          body: Rect.fromCircle(
            center: const Offset(100, 100),
            radius: bodyDiameter / 2,
          ),
          minTarget: minTarget,
          gap: 2,
          minTrustRadius: 9,
          badgeDiameter: 16,
          rtl: false,
        );

    test('at low zoom the action ring is the target size and larger than '
        'the node', () {
      final g = geometry(lowZoomBody);
      expect(g.showsActionRing, isTrue);
      expect(g.actionRadius * 2, greaterThanOrEqualTo(minTarget));
      expect(g.actionRadius, greaterThan(lowZoomBody / 2));
    });

    test('a node at least as large as a target draws no action ring', () {
      expect(geometry(minTarget).showsActionRing, isFalse);
      expect(geometry(80).showsActionRing, isFalse);
    });

    test('the disc circle hugs the body but never shrinks below its floor', () {
      expect(geometry(lowZoomBody).trustRadius, 9);
      final big = geometry(40);
      expect(big.trustRadius, greaterThan(20));
    });

    test('the badge sits on the ring at the top start', () {
      final g = geometry(40);
      expect((g.badgeCentre - g.centre).distance, closeTo(g.trustRadius, 1e-9));
      expect(g.badgeCentre.dx, lessThan(g.centre.dx));
      expect(g.badgeCentre.dy, lessThan(g.centre.dy));
      final rtl = constellationNodeRingGeometry(
        body: Rect.fromCircle(center: const Offset(100, 100), radius: 20),
        minTarget: minTarget,
        gap: 2,
        minTrustRadius: 9,
        badgeDiameter: 16,
        rtl: true,
      );
      expect(rtl.badgeCentre.dx, greaterThan(rtl.centre.dx));
    });

    test('the reserved overhang covers the glyph disc at every zoom', () {
      final tt = TenturaTokens.light;
      for (final diameter in [6.0, 8.0, 16.0, 24.0, 40.0, 60.0]) {
        final overhang = constellationNodeBadgeOverhang(
          base: 0,
          bodyDiameter: diameter,
          hasTrustBadge: true,
          tt: tt,
        );
        final body = Rect.fromCircle(center: Offset.zero, radius: diameter / 2);
        final reserved = Rect.fromLTRB(
          body.left - overhang,
          body.top - overhang,
          body.right + overhang,
          body.bottom,
        );
        for (final rtl in [false, true]) {
          final g = constellationNodeRingGeometry(
            body: body,
            minTarget: minTarget,
            gap: tt.tightGap,
            minTrustRadius: constellationTrustMinRadius(tt),
            badgeDiameter: constellationTrustBadgeDiameter(tt),
            rtl: rtl,
          );
          final disc = Rect.fromCircle(
            center: g.badgeCentre,
            radius: g.badgeDiameter / 2,
          );
          expect(
            reserved.inflate(1e-9).contains(disc.topLeft) &&
                reserved.inflate(1e-9).contains(disc.bottomRight),
            isTrue,
            reason: 'diameter $diameter rtl $rtl',
          );
        }
      }
      expect(
        constellationNodeBadgeOverhang(
          base: 5,
          bodyDiameter: 40,
          hasTrustBadge: false,
          tt: tt,
        ),
        5,
      );
    });

    test("a neighbour's label is not placed over a trusted person's disc", () {
      final tt = TenturaTokens.light;
      // Overview zoom (0.4): 16 px people. The neighbour sits just above and
      // to the start of the trusted person, so its label below would land
      // on the trusted person's disc.
      const diameter = 16.0;
      const trusted = Offset(200, 200);
      const neighbour = Offset(190, 160);
      ConstellationPresentationFrame place({required bool reserve}) =>
          computeConstellationPresentationFrame(
            snapshot: const Object(),
            cameraRevision: 1,
            detail: ConstellationDetailLevel.overview,
            viewport: const Size(400, 400),
            nodesInPaintOrder: [
              ConstellationFrameNodeInput(
                id: 'trusted',
                centre: trusted,
                bodyDiameter: diameter,
                badgeOverhang: constellationNodeBadgeOverhang(
                  base: 0,
                  bodyDiameter: diameter,
                  hasTrustBadge: reserve,
                  tt: tt,
                ),
                labelSize: const Size(80, 20),
                priority: 2,
                ring: 1,
                labelCandidate: true,
              ),
              const ConstellationFrameNodeInput(
                id: 'neighbour',
                centre: neighbour,
                bodyDiameter: diameter,
                badgeOverhang: 0,
                labelSize: Size(80, 20),
                priority: 2,
                ring: 1,
                labelCandidate: true,
              ),
            ],
            chips: const [],
            gap: 2,
            minTarget: minTarget,
            rtl: false,
          );
      final g = constellationNodeRingGeometry(
        body: Rect.fromCircle(center: trusted, radius: diameter / 2),
        minTarget: minTarget,
        gap: tt.tightGap,
        minTrustRadius: constellationTrustMinRadius(tt),
        badgeDiameter: constellationTrustBadgeDiameter(tt),
        rtl: false,
      );
      final disc = Rect.fromCircle(
        center: g.badgeCentre,
        radius: g.badgeDiameter / 2,
      );
      // Without the reservation the neighbour's label would cover the disc.
      expect(place(reserve: false).labels['neighbour']!.overlaps(disc), isTrue);

      final frame = place(reserve: true);
      for (final label in frame.labels.values) {
        expect(label.overlaps(disc), isFalse);
      }
      expect(frame.labels['neighbour'], isNotNull);
      expect(frame.labels['trusted'], isNotNull);
    });
  });

  group('ring layer paints', () {
    Future<void> pumpLayer(
      WidgetTester tester, {
      required ConstellationPresentationFrame frame,
      Map<GraphNodeId, ConstellationTrustBadge> trust = const {},
      GraphNodeId? selected,
      Set<GraphNodeId> dimmed = const {},
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
                dimmedGraphIds: dimmed,
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

    for (final badge in ConstellationTrustBadge.values) {
      testWidgets('paints the ${badge.name} glyph disc and no ring', (
        tester,
      ) async {
        final frame = frameOf([
          ('p', const Offset(200, 200), 40),
        ], detail: ConstellationDetailLevel.close);
        await pumpLayer(tester, frame: frame, trust: {'p': badge});
        final context = tester.element(rings());
        final tt = context.tt;
        final scheme = Theme.of(context).colorScheme;
        final style = constellationTrustBadgeStyle(badge, scheme, rtl: false);
        final g = constellationNodeRingGeometry(
          body: frame.bodies['p']!,
          minTarget: minTarget,
          gap: tt.tightGap,
          minTrustRadius: constellationTrustMinRadius(tt),
          badgeDiameter: constellationTrustBadgeDiameter(tt),
          rtl: false,
        );
        // Only the disc: nothing is drawn round the person.
        expect(rings(), isNot(paints..path()));
        expect(rings(), isNot(paints..circle(x: 200, y: 200)));
        expect(
          rings(),
          paints
            ..circle(
              x: g.badgeCentre.dx,
              y: g.badgeCentre.dy,
              radius: g.badgeDiameter / 2,
              color: scheme.surface,
            )
            ..circle(
              x: g.badgeCentre.dx,
              y: g.badgeCentre.dy,
              radius: g.badgeDiameter / 2,
              color: style.color,
              style: PaintingStyle.stroke,
            )
            ..paragraph(),
        );
        // A person without a relation gets nothing.
        await pumpLayer(tester, frame: frame);
        expect(rings(), paintsNothing);
      });
    }

    testWidgets('off the selected trust chain the trust marks fade', (
      tester,
    ) async {
      final frame = frameOf([
        ('on', const Offset(100, 200), 40),
        ('off1', const Offset(200, 300), 40),
        ('off2', const Offset(300, 200), 40),
      ], detail: ConstellationDetailLevel.close);
      const trust = {
        'on': ConstellationTrustBadge.mutual,
        'off1': ConstellationTrustBadge.mutual,
        'off2': ConstellationTrustBadge.mutual,
      };
      await pumpLayer(tester, frame: frame, trust: trust);
      expect(
        rings(),
        isNot(paints..something((name, _) => name == #saveLayer)),
        reason: 'no chain selected: nothing fades',
      );

      // Same frame, new dimmed set: the layer repaints.
      await pumpLayer(
        tester,
        frame: frame,
        trust: trust,
        dimmed: {'off1', 'off2'},
      );
      var layers = 0;
      // The kept mark first, then both faded ones inside ONE translucent
      // layer at the chain's dim opacity.
      final g = (Offset c) => constellationNodeRingGeometry(
        body: Rect.fromCircle(center: c, radius: 20),
        minTarget: minTarget,
        gap: tester.element(rings()).tt.tightGap,
        minTrustRadius: constellationTrustMinRadius(tester.element(rings()).tt),
        badgeDiameter: constellationTrustBadgeDiameter(
          tester.element(rings()).tt,
        ),
        rtl: false,
      ).badgeCentre;
      final on = g(const Offset(100, 200));
      final off1 = g(const Offset(200, 300));
      final off2 = g(const Offset(300, 200));
      expect(
        rings(),
        paints
          ..circle(x: on.dx, y: on.dy)
          ..something((name, args) {
            if (name != #saveLayer) return false;
            layers++;
            final paint = args[1] as Paint;
            expect(
              paint.color.a,
              moreOrLessEquals(
                kConstellationTrustChainDimOpacity,
                epsilon: 0.01,
              ),
            );
            return true;
          })
          // Each mark: the glyph disc (fill, stroke, glyph).
          ..circle(x: off1.dx, y: off1.dy)
          ..circle()
          ..paragraph()
          ..circle(x: off2.dx, y: off2.dy)
          ..circle()
          ..paragraph()
          ..restore(),
      );
      expect(layers, 1);
    });

    // Zoomed out the fixed-size disc would cover the node: a muted rim on
    // the node's own edge shows the relation instead, scaling with it.
    for (final detail in const [
      ConstellationDetailLevel.district,
      ConstellationDetailLevel.overview,
    ]) {
      testWidgets('at ${detail.name} detail a muted rim, no disc', (
        tester,
      ) async {
        final frame = frameOf([
          // 25 px: a 2 px rim, exact in the canvas's float32 stroke width.
          ('p', const Offset(200, 200), 25),
        ], detail: detail);
        await pumpLayer(
          tester,
          frame: frame,
          trust: {'p': ConstellationTrustBadge.mutual},
        );
        final scheme = Theme.of(tester.element(rings())).colorScheme;
        final rim = constellationTrustRimOf(
          ConstellationTrustBadge.mutual,
          frame.bodies['p']!,
          scheme,
        )!;
        expect(
          rings(),
          paints..circle(
            x: 200,
            y: 200,
            radius: 12.5 - rim.width / 2,
            strokeWidth: rim.width,
            color: rim.color,
            style: PaintingStyle.stroke,
          ),
        );
        expect(rings(), isNot(paints..paragraph()), reason: 'no glyph disc');

        // A contact without content has no relation colour: nothing.
        await pumpLayer(
          tester,
          frame: frame,
          trust: {'p': ConstellationTrustBadge.contactOnly},
        );
        expect(rings(), paintsNothing);

        // Selected, it also gets the plain target-size ring, after the rim.
        await pumpLayer(
          tester,
          frame: frameOf([
            ('p', const Offset(200, 200), lowZoomBody),
          ], detail: detail),
          trust: {'p': ConstellationTrustBadge.mutual},
          selected: 'p',
        );
        expect(
          rings(),
          paints
            ..circle(x: 200, y: 200, radius: lowZoomBody / 2 - 0.5)
            ..circle(x: 200, y: 200, radius: minTarget / 2),
        );
      });
    }

    test('the rim stays inside the node and scales with it', () {
      final scheme = TenturaTheme.light().colorScheme;
      Rect body(double d) =>
          Rect.fromCircle(center: Offset.zero, radius: d / 2);
      final small = constellationTrustRimOf(
        ConstellationTrustBadge.mutual,
        body(8),
        scheme,
      )!;
      final large = constellationTrustRimOf(
        ConstellationTrustBadge.mutual,
        body(30),
        scheme,
      )!;
      expect(small.width, 1, reason: 'a floor so it stays visible');
      expect(large.width, greaterThan(small.width));
      expect(large.width, lessThan(15 / 2), reason: 'never fills the node');
      final oneWay = constellationTrustRimOf(
        ConstellationTrustBadge.youTrust,
        body(30),
        scheme,
      )!;
      expect(oneWay.width, lessThan(large.width), reason: 'one-way is thinner');
    });

    for (final (name, theme) in [
      ('light', TenturaTheme.light()),
      ('dark', TenturaTheme.dark()),
    ]) {
      test('rim colours are muted yet keep 3:1 on the $name field', () {
        final scheme = theme.colorScheme;
        double contrast(Color a, Color b) {
          final la = a.computeLuminance();
          final lb = b.computeLuminance();
          final (hi, lo) = la > lb ? (la, lb) : (lb, la);
          return (hi + 0.05) / (lo + 0.05);
        }

        for (final base in [scheme.primary, scheme.tertiary]) {
          final muted = constellationMutedRimColor(base, scheme.surface);
          expect(
            contrast(muted, scheme.surface),
            greaterThanOrEqualTo(kConstellationTrustRimMinContrast),
          );
          expect(
            HSLColor.fromColor(muted).saturation,
            lessThan(HSLColor.fromColor(base).saturation),
            reason: 'muted',
          );
        }
      });
    }

    testWidgets('a node larger than a target gets no action ring', (
      tester,
    ) async {
      final frame = frameOf([
        ('p', const Offset(200, 200), 60),
      ], detail: ConstellationDetailLevel.close);
      await pumpLayer(tester, frame: frame, selected: 'p');
      expect(rings(), isNot(paints..circle()));
    });
  });
}

extension on WidgetTester {
  Future<TestGesture> createGestureMouse() =>
      createGesture(kind: PointerDeviceKind.mouse);
}
