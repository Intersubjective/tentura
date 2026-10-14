import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every [PictureLayer] that holds the constellation's edge strokes.
///
/// Edges render inside their own repaint boundary; Flutter replaces that
/// boundary's picture layers each time the edges are repainted, so layer
/// identity across frames tells whether the edges were redrawn. The edge
/// widget is found by name and its boundary is whichever repaint boundary is
/// at or below it, else the nearest one above, so the render structure inside
/// the boundary is free to change.
List<PictureLayer> edgePictureLayers(WidgetTester tester) {
  final edges = tester.renderObject(
    find.byWidgetPredicate((w) => w.runtimeType.toString() == 'EdgesView'),
  );
  final boundary = _boundaryFor(edges);
  expect(boundary, isNotNull, reason: 'Edges must sit in a repaint boundary');
  final root = boundary!.debugLayer;
  expect(root, isNotNull, reason: 'Edges must have painted');

  final pictures = <PictureLayer>[];
  void collect(Layer node) {
    if (node is PictureLayer) pictures.add(node);
    if (node is ContainerLayer) {
      var child = node.firstChild;
      while (child != null) {
        collect(child);
        child = child.nextSibling;
      }
    }
  }

  collect(root!);
  expect(pictures, isNotEmpty, reason: 'Edges must have painted a picture');
  return pictures;
}

RenderRepaintBoundary? _boundaryFor(RenderObject start) {
  RenderRepaintBoundary? below;
  void descend(RenderObject node) {
    if (below != null) return;
    if (node is RenderRepaintBoundary) {
      below = node;
      return;
    }
    node.visitChildren(descend);
  }

  descend(start);
  if (below != null) return below;
  var up = start.parent;
  while (up != null) {
    if (up is RenderRepaintBoundary) return up;
    up = up.parent;
  }
  return null;
}

/// True when [actual] is exactly the layers in [expected]: nothing repainted.
bool sameEdgeLayers(List<PictureLayer> actual, List<PictureLayer> expected) {
  if (actual.length != expected.length) return false;
  for (var i = 0; i < actual.length; i++) {
    if (!identical(actual[i], expected[i])) return false;
  }
  return true;
}

/// True when no layer of [actual] survives from [previous]: all repainted.
bool allEdgeLayersReplaced(
  List<PictureLayer> actual,
  List<PictureLayer> previous,
) => actual.every((layer) => !previous.any((p) => identical(p, layer)));
