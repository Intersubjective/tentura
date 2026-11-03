import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/graph/domain/layout/radial_hop_positions.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import '../../support/phone_surface.dart';

import 'fixtures/constellation_reference_fixture.dart';

void main() {
  group('Field canvas extent (#968)', () {
    test('extent is 16384 with centre derived from it', () {
      expect(kConstellationCanvasExtent, 16384.0);
      expect(kConstellationCanvasCentre, kConstellationCanvasExtent / 2);
      final centre = constellationCanvasCentrePoint();
      expect(centre.x, kConstellationCanvasCentre);
      expect(centre.y, kConstellationCanvasCentre);
    });

    test('clampLayoutPosition keeps nodes inside the full square extent', () {
      const nodeSize = 48.0;
      const half = nodeSize / 2;
      const canvas = (
        w: kConstellationCanvasExtent,
        h: kConstellationCanvasExtent,
      );
      for (final corner in [
        (x: kLayoutClampMargin + half, y: kLayoutClampMargin + half),
        (
          x: kConstellationCanvasExtent - kLayoutClampMargin - half,
          y: kLayoutClampMargin + half,
        ),
        (
          x: kLayoutClampMargin + half,
          y: kConstellationCanvasExtent - kLayoutClampMargin - half,
        ),
        (
          x: kConstellationCanvasExtent - kLayoutClampMargin - half,
          y: kConstellationCanvasExtent - kLayoutClampMargin - half,
        ),
      ]) {
        final clamped = clampLayoutPosition(corner, canvas);
        expect(clamped.x, closeTo(corner.x, 1e-9));
        expect(clamped.y, closeTo(corner.y, 1e-9));
        final bounds = constellationRenderedBounds(
          centre: clamped,
          size: (width: nodeSize, height: nodeSize),
        );
        expect(constellationBoundsWithinCanvas(bounds), isTrue);
      }
    });

    testWidgets('fit-to-content respects canvas size and min-scale floor', (
      tester,
    ) async {
      const viewport = Size(1200, 800);
      final cubit = await loadReferenceCubit();
      await pumpConstellationBody(tester, cubit, size: viewport);
      final graph = cubit.graphController;
      expect(graph.canvasSize.width, kConstellationCanvasExtent);
      expect(graph.canvasSize.height, kConstellationCanvasExtent);
      graph.fitToRect(
        const Rect.fromLTWH(
          0,
          0,
          kConstellationCanvasExtent,
          kConstellationCanvasExtent,
        ),
        padding: 0,
      );
      await tester.pump();
      // Field minScale is 0.1; the canvas is larger than the viewport at that zoom.
      expect(graph.cameraScale, closeTo(0.1, 0.02));
      await cubit.close();
    });

    testWidgets('375×667 RU: reference field mounts without overflow', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final cubit = await loadReferenceCubit();
      await pumpConstellationBody(
        tester,
        cubit,
        size: kPhoneSurface,
      );
      expect(find.byType(ConstellationBody), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cubit.close();
    });
  });
}
