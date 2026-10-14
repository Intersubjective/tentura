@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';

import 'fixtures/constellation_reference_fixture.dart';

void main() {
  group('Constellation label placement cache', () {
    testWidgets('pan translates labels with zero placement calls', (
      tester,
    ) async {
      // No overflow chips: every _firstFittingCandidate call places a label.
      final cubit = await loadReferenceCubit(
        field: ConstellationField(
          loadedAt: DateTime.utc(2026, 10, 14),
          context: '',
        ),
      );
      addTearDown(cubit.close);
      final holder = ConstellationPresentationFrameHolder();
      await pumpConstellationBody(
        tester,
        cubit,
        size: const Size(1200, 900),
        presentationFrameHolder: holder,
      );
      await tester.pumpAndSettle();
      expect(holder.frame!.chips, isEmpty);
      expect(holder.frame!.labels, isNotEmpty);

      expect(constellationPlacementCount, greaterThan(0));

      int takePlacementCount() {
        final count = constellationPlacementCount;
        constellationPlacementCount = 0;
        return count;
      }

      takePlacementCount();

      // Positive control: changing zoom must exercise real label placement.
      cubit.graphController.zoomBy(1.25);
      await tester.pumpAndSettle();
      expect(takePlacementCount(), greaterThan(0));
      final controller = cubit.graphController;
      final snapshot = controller.renderSnapshot;
      final scale = controller.cameraScale;
      final layoutCount = controller.relayoutInvocationCount;
      final labelsBefore = Map<String, Rect>.of(holder.frame!.labels);
      expect(labelsBefore, isNotEmpty);
      final cameraRevision = controller.cameraRevision.value;
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final camera = viewer.transformationController!;
      const delta = Offset(12, 8);
      final transform = camera.value.clone();
      transform.setTranslationRaw(
        transform.storage[12] + delta.dx,
        transform.storage[13] + delta.dy,
        transform.storage[14],
      );
      camera.value = transform;
      await tester.pump();

      final panPlacements = takePlacementCount();
      expect(controller.cameraRevision.value, greaterThan(cameraRevision));
      expect(controller.cameraScale, scale);
      expect(controller.renderSnapshot, equals(snapshot));
      expect(controller.relayoutInvocationCount, layoutCount);
      expect(holder.frame!.cameraRevision, controller.cameraRevision.value);
      for (final entry in labelsBefore.entries) {
        final translated = holder.frame!.labels[entry.key];
        expect(translated, isNotNull);
        expect(
          (translated!.center - entry.value.center - delta).distance,
          lessThan(0.001),
          reason: 'Panning must translate the cached label for ${entry.key}',
        );
        expect(translated.width, closeTo(entry.value.width, 0.001));
        expect(translated.height, closeTo(entry.value.height, 0.001));
      }
      expect(
        panPlacements,
        0,
        reason:
            'A camera pan must reuse label placement at unchanged zoom '
            'and layout revision',
      );
    });
  });
}
