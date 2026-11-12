import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_edge_style.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

import 'fixtures/edge_endpoint_recording.dart';

FieldPersonNode _person(String id, {int ring = 1, double size = 40}) =>
    FieldPersonNode(
      person: Profile(id: id, displayName: id),
      ring: ring,
      isKept: true,
      size: size,
    );

EndpointRecordingCanvas _paint({
  required double scale,
  NodeDetails? source,
  NodeDetails? destination,
  ConstellationEdgeKind kind = ConstellationEdgeKind.tier1Path,
  bool arrow = false,
}) {
  final edge = EdgeDetails(
    source: source ?? _person('a'),
    destination: destination ?? _person('b'),
    color: Colors.transparent,
    arrowAtDestination: arrow,
  );
  final repaint = ChangeNotifier();
  final painter = ConstellationEdgePainter(
    edgeKindByPair: {edge.semanticId: kind},
    tt: TenturaTokens.light,
    scheme: const ColorScheme.light(),
    repaint: repaint,
    cameraScale: () => scale,
  );
  final canvas = EndpointRecordingCanvas();
  painter.paint(canvas, edge, Offset.zero, const Offset(100, 0));
  repaint.dispose();
  return canvas;
}

void _expectEnds(
  EndpointRecordingCanvas canvas,
  double start,
  double end,
  double scale, {
  bool dashed = false,
}) {
  expect(
    canvas.strokes,
    isNotEmpty,
    reason: 'visible endpoint circles cannot substitute for an edge stroke',
  );
  if (!dashed) {
    expect(
      canvas.strokes,
      hasLength(1),
      reason: 'a solid edge must draw one continuous stroke',
    );
  }
  final (a, _) = canvas.strokes.first;
  final (_, b) = canvas.strokes.last;
  expect(
    (a - Offset(start, 0)).distance * scale,
    lessThanOrEqualTo(0.5),
    reason: 'source stroke endpoint must meet its marker rim',
  );
  expect(
    (b - Offset(end, 0)).distance * scale,
    lessThanOrEqualTo(0.5),
    reason: 'destination stroke endpoint must meet its marker rim',
  );
}

void main() {
  group('Field edge endpoints meet overview person dots', () {
    for (final (scale, inset) in [(0.4, 6.25), (0.2, 12.5), (0.1, 25.0)]) {
      test('solid edge meets both dot rims at camera scale $scale', () {
        final canvas = _paint(scale: scale);
        _expectEnds(canvas, inset, 100 - inset, scale);
        if (scale == 0.1) {
          // At minimum zoom a 3-scene-pixel intrusion is only 0.3 screen
          // pixels: also pin the specified rim coordinates, not just tolerance.
          expect(canvas.strokes.single.$1.dx, closeTo(25, 1e-6));
          expect(canvas.strokes.single.$2.dx, closeTo(75, 1e-6));
        }
      });
    }

    test('dot rim trim ignores different person avatar sizes', () {
      _expectEnds(
        _paint(scale: 0.4, destination: _person('b', size: 60)),
        6.25,
        93.75,
        0.4,
      );
    });

    test(
      'close and district retain avatar margins before overview uses dots',
      () {
        for (final scale in [1.0, 0.5]) {
          _expectEnds(_paint(scale: scale), 22, 78, scale);
        }
        _expectEnds(_paint(scale: 0.4), 6.25, 93.75, 0.4);
      },
    );

    for (final (label, node) in <(String, NodeDetails)>[
      ('ego avatar', _person('ego', ring: 0)),
      ('non-person marker', const FieldDraftNode(size: 40)),
    ]) {
      test('$label keeps its margin while the destination meets its dot', () {
        _expectEnds(_paint(scale: 0.4, source: node), 22, 93.75, 0.4);
      });
      test('$label keeps its margin while the source meets its dot', () {
        _expectEnds(_paint(scale: 0.4, destination: node), 6.25, 78, 0.4);
      });
    }

    test('dashed edge starts and finishes at the dot rims', () {
      const kind = ConstellationEdgeKind.tier2Path;
      expect(
        constellationEdgeStyle(
          kind,
          TenturaTokens.light,
          const ColorScheme.light(),
        ).dash,
        greaterThan(0),
      );
      final canvas = _paint(scale: 0.4, kind: kind);
      expect(canvas.strokes.length, greaterThan(1));
      _expectEnds(canvas, 6.25, 93.75, 0.4, dashed: true);
    });

    test('destination arrow tip meets the destination dot rim', () {
      final canvas = _paint(scale: 0.4, arrow: true);
      expect(canvas.filledPathBounds, hasLength(1));
      final arrow = canvas.filledPathBounds.single;
      expect(arrow.right, closeTo(93.75, 0.5 / 0.4));
      expect(arrow.center.dy, closeTo(0, 1e-6));
    });
  });
}
