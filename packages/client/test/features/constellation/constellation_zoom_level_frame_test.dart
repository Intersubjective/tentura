import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_zoom_level_controller.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';

void main() {
  // A spread of people over priorities and rings, one frame per level.
  Set<String> labelsAt(ConstellationDetailLevel level) {
    final nodes = <ConstellationFrameNodeInput>[];
    var i = 0;
    for (var priority = 0; priority <= 3; priority++) {
      for (var ring = 0; ring <= 3; ring++) {
        nodes.add(
          ConstellationFrameNodeInput(
            id: 'n${i++}',
            centre: Offset(60.0 + 90 * ring, 60.0 + 90 * priority),
            bodyDiameter: 40,
            badgeOverhang: 0,
            labelSize: const Size(60, 16),
            priority: priority,
            ring: ring,
            labelCandidate: constellationLabelCandidateForDetail(
              detail: level,
              priority: priority,
              ring: ring,
            ),
          ),
        );
      }
    }
    return computeConstellationPresentationFrame(
      snapshot: const Object(),
      cameraRevision: 1,
      detail: level,
      viewport: const Size(400, 400),
      nodesInPaintOrder: nodes,
      chips: const [],
      gap: 2,
      minTarget: 48,
      rtl: false,
    ).labels.keys.toSet();
  }

  ConstellationDetailLevel levelAfter(
    List<double> gesture,
    double settledScale,
  ) {
    final c = ConstellationZoomLevelController();
    for (final s in gesture) {
      c.update(s, gestureActive: true);
    }
    c.update(settledScale, gestureActive: false);
    final level = c.value;
    c.dispose();
    return level;
  }

  group('labels in the presentation frame at a settled scale', () {
    test(
      'zooming in and zooming out to the same scale label the same people',
      () {
        for (final scale in [0.31, 0.45, 0.6, 0.8, 0.849, 0.85]) {
          final fromFar = levelAfter([0.2, 0.3, scale - 0.02, scale], scale);
          final fromNear = levelAfter([1.4, 1.1, scale + 0.02, scale], scale);
          expect(fromFar, fromNear, reason: 'scale $scale');
          expect(labelsAt(fromFar), labelsAt(fromNear), reason: 'scale $scale');
        }
      },
    );

    test(
      'placed labels only grow while the scale rises from cut-off to 0.85',
      () {
        Set<String>? previous;
        for (var i = 30; i <= 85; i++) {
          final scale = i / 100;
          final placed = labelsAt(settledConstellationDetailLevel(scale));
          if (previous != null) {
            expect(
              placed.containsAll(previous),
              isTrue,
              reason: 'a label vanished when zooming in to $scale',
            );
          }
          previous = placed;
        }
      },
    );

    test('placed labels are the same sweeping the scale up or down', () {
      final scales = [for (var i = 30; i <= 120; i++) i / 100];
      final up = {
        for (final s in scales) s: labelsAt(settledConstellationDetailLevel(s)),
      };
      final down = {
        for (final s in scales.reversed)
          s: labelsAt(settledConstellationDetailLevel(s)),
      };
      for (final s in scales) {
        expect(down[s], up[s], reason: 'scale $s');
      }
    });
  });
}
