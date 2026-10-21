@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PictureLayer;
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'fixtures/constellation_reference_fixture.dart';
import 'fixtures/edge_picture_layers.dart';

void main() {
  group('Constellation edge repaint discipline', () {
    testWidgets('panning the camera does not repaint edges', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await pumpConstellationBody(tester, cubit, size: const Size(1200, 900));
      await tester.pumpAndSettle();
      expect(cubit.edgeKindByPair, isNotEmpty);

      final camera = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      final edgeLayers = edgePictureLayers(tester);
      final cameraRevision = cubit.graphController.cameraRevision.value;

      final panned = camera.value.clone()
        ..setTranslationRaw(
          camera.value.storage[12] + 12,
          camera.value.storage[13] + 8,
          camera.value.storage[14],
        );
      camera.value = panned;
      await tester.pump();

      expect(
        cubit.graphController.cameraRevision.value,
        greaterThan(cameraRevision),
        reason: 'The pan must register as a camera change',
      );
      _expectSameLayers(
        edgePictureLayers(tester),
        edgeLayers,
        reason:
            'Edge geometry and stroke width are unchanged by a pure '
            'translation, so the edge layer must be reused, not repainted',
      );
    });

    testWidgets('a rebuild with unchanged scene and style does not repaint '
        'edges', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      final theme = TenturaTheme.light();
      await pumpConstellationBody(
        tester,
        cubit,
        size: const Size(1200, 900),
        theme: theme,
      );
      await tester.pumpAndSettle();
      final edgeLayers = edgePictureLayers(tester);

      // Same scene revision, same data, same theme: only the widget tree is
      // rebuilt, handing the render layer a freshly built painter object.
      await pumpConstellationBody(
        tester,
        cubit,
        size: const Size(1200, 900),
        theme: theme,
      );
      await tester.pumpAndSettle();

      _expectSameLayers(
        edgePictureLayers(tester),
        edgeLayers,
        reason:
            'Edge painting is keyed by scene revision and style, not by the '
            'identity of a freshly built painter object',
      );
    });

    testWidgets('a changed endpoint position repaints the edge layer', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit(
        field: constellationReferenceField(
          anchors: [
            ConstellationAnchor(
              target: ConstellationAnchorTarget.person('am'),
              position: const ConstellationAnchorPosition(
                xUnits: 4,
                yUnits: -2,
                coordinateSpaceVersion: 1,
              ),
              revision: ConstellationAnchorRevision(BigInt.one),
              placedAt: DateTime.utc(2026, 9, 9, 12),
            ),
          ],
        ),
      );
      addTearDown(cubit.close);
      await pumpConstellationBody(tester, cubit, size: const Size(1200, 900));
      await tester.pumpAndSettle();
      expect(cubit.edgeKindByPair, isNotEmpty);

      cubit.beginDragExisting(target: ConstellationAnchorTarget.person('am'));
      await tester.pumpAndSettle();
      final edgeLayers = edgePictureLayers(tester);
      final controller = cubit.graphController;
      final before = controller.getPositionForId('fp:am');

      cubit.updateDragPresentation(
        nodeId: 'am',
        sceneCentre: before + const Offset(40, 30),
      );
      await tester.pump();

      expect(
        controller.getPositionForId('fp:am'),
        before + const Offset(40, 30),
      );
      // Only the edges that end at the dragged node repaint (live layer); the
      // cached layer of the other edges is reused.
      expect(
        sameEdgeLayers(edgePictureLayers(tester), edgeLayers),
        isFalse,
        reason: 'A changed endpoint position is a geometry change: repaint',
      );
    });

    testWidgets('zooming out repaints edges so stroke width tracks the camera', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await pumpConstellationBody(tester, cubit, size: const Size(1200, 900));
      await tester.pumpAndSettle();
      expect(cubit.edgeKindByPair, isNotEmpty);

      final controller = cubit.graphController;
      final edgeLayers = edgePictureLayers(tester);
      final scaleBefore = controller.cameraScale;
      final revisionBefore = controller.cameraRevision.value;

      // Below 1 the stroke is widened by 1 / scale, so a zoom-out changes what
      // the edges must look like even though no node moved.
      controller.zoomBy(0.4 / scaleBefore);
      await tester.pumpAndSettle();

      expect(controller.cameraScale, lessThan(1));
      expect(controller.cameraScale, lessThan(scaleBefore));
      expect(controller.cameraRevision.value, greaterThan(revisionBefore));
      _expectNewLayers(
        edgePictureLayers(tester),
        edgeLayers,
        reason: 'A zoom that changes the stroke compensation must redraw',
      );
    });

    testWidgets('a pan after a zoom still leaves the edge layer reused', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await pumpConstellationBody(tester, cubit, size: const Size(1200, 900));
      await tester.pumpAndSettle();

      final controller = cubit.graphController..zoomBy(0.5);
      await tester.pumpAndSettle();
      final camera = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      final edgeLayers = edgePictureLayers(tester);
      final scale = controller.cameraScale;

      camera.value = camera.value.clone()
        ..setTranslationRaw(
          camera.value.storage[12] - 20,
          camera.value.storage[13] + 14,
          camera.value.storage[14],
        );
      await tester.pump();

      expect(controller.cameraScale, scale);
      _expectSameLayers(
        edgePictureLayers(tester),
        edgeLayers,
        reason: 'Translation at any zoom level must not redraw the edges',
      );
    });

    testWidgets('a style change repaints the edges', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await pumpConstellationBody(
        tester,
        cubit,
        size: const Size(1200, 900),
        theme: TenturaTheme.light(),
      );
      await tester.pumpAndSettle();
      final edgeLayers = edgePictureLayers(tester);

      await pumpConstellationBody(
        tester,
        cubit,
        size: const Size(1200, 900),
        theme: TenturaTheme.dark(),
      );
      await tester.pumpAndSettle();

      _expectNewLayers(
        edgePictureLayers(tester),
        edgeLayers,
        reason: 'Edge colours come from the theme: a new style must redraw',
      );
    });
  });
}

void _expectSameLayers(
  List<PictureLayer> actual,
  List<PictureLayer> expected, {
  required String reason,
}) {
  expect(sameEdgeLayers(actual, expected), isTrue, reason: reason);
}

void _expectNewLayers(
  List<PictureLayer> actual,
  List<PictureLayer> previous, {
  required String reason,
}) {
  expect(allEdgeLayersReplaced(actual, previous), isTrue, reason: reason);
}
