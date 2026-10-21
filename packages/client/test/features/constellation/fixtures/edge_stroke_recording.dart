import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

/// One `drawPath` call, with the geometry captured at the moment of the call
/// so a Path the painter keeps and mutates later is still judged as drawn.
typedef PathDraw = ({
  ui.Path path,
  Rect bounds,
  int contours,
  double totalLength,
  Color color,
  double strokeWidth,
});

/// Geometry fingerprint of a drawn path, independent of object identity.
String pathSignature(PathDraw d) =>
    '${d.bounds.left.toStringAsFixed(2)},${d.bounds.top.toStringAsFixed(2)},'
    '${d.bounds.right.toStringAsFixed(2)},${d.bounds.bottom.toStringAsFixed(2)}'
    '|${d.contours}|${d.totalLength.toStringAsFixed(2)}';

/// Canvas that records every `draw*` call (and the geometry of `drawPath`), so
/// tests count work instead of timing it.
class RecordingEdgeCanvas implements Canvas {
  final pathDraws = <PathDraw>[];
  var lineDraws = 0;
  var drawOps = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString().replaceAll(
      RegExp(r'Symbol\("|"\)'),
      '',
    );
    if (!name.startsWith('draw')) {
      return null;
    }
    drawOps++;
    final args = invocation.positionalArguments;
    if (name == 'drawPath') {
      final path = args[0] as ui.Path;
      final paint = args[1] as Paint;
      final metrics = path.computeMetrics().toList();
      pathDraws.add((
        path: path,
        bounds: path.getBounds(),
        contours: metrics.length,
        totalLength: metrics.fold<double>(0, (sum, m) => sum + m.length),
        color: paint.color,
        strokeWidth: paint.strokeWidth,
      ));
    } else if (name == 'drawLine') {
      lineDraws++;
    }
    return null;
  }
}

class _NeverListenable implements Listenable {
  const _NeverListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

typedef EdgeLink = (String, String, ConstellationEdgeKind);

typedef EdgeScene = ({
  ConstellationEdgePainter painter,
  List<EdgeDetails> edges,
});

/// A painter plus one edge per link, nodes keyed by id. Parallel links of
/// different kinds are distinct edges (the kind is part of the semantic id).
EdgeScene edgeScene({
  required List<EdgeLink> links,
  double Function()? cameraScale,
}) {
  final nodes = <String, FieldPersonNode>{};
  FieldPersonNode node(String id) => nodes.putIfAbsent(
    id,
    () => FieldPersonNode(
      person: Profile(id: id, displayName: id),
      ring: 1,
      isKept: true,
      size: 40,
    ),
  );
  return (
    painter: ConstellationEdgePainter(
      edgeKindByPair: {
        for (final (a, b, kind) in links) '$a->$b:${kind.name}': kind,
      },
      tt: TenturaTokens.light,
      scheme: const ColorScheme.light(),
      repaint: const _NeverListenable(),
      cameraScale: cameraScale ?? () => 1,
    ),
    edges: [
      for (final (a, b, kind) in links)
        EdgeDetails(
          source: node(a),
          destination: node(b),
          color: Colors.transparent,
          semanticId: '$a->$b:${kind.name}',
        ),
    ],
  );
}

String personId(NodeDetails node) => (node as FieldPersonNode).person.id;

typedef EdgeFrame = ({
  RecordingEdgeCanvas canvas,

  /// Draw operations each `paint` call issued, in edge order.
  List<int> opsPerEdge,
});

/// One frame: every edge painted at the positions [positionOf] gives.
EdgeFrame paintFrame(
  EdgeScene scene,
  Offset Function(NodeDetails node) positionOf,
) {
  final canvas = RecordingEdgeCanvas();
  final opsPerEdge = <int>[];
  for (final edge in scene.edges) {
    final before = canvas.drawOps;
    scene.painter.paint(
      canvas,
      edge,
      positionOf(edge.source),
      positionOf(edge.destination),
    );
    opsPerEdge.add(canvas.drawOps - before);
  }
  return (canvas: canvas, opsPerEdge: opsPerEdge);
}
