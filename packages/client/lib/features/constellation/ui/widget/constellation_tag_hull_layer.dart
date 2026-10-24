import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_tag_colors.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';

/// Scene-space margin the hull keeps around the nodes it encloses.
const kConstellationTagHullPadding = 56.0;

const _hullAlpha = 0.18;

/// A soft hull around the Field people of every selected own tag: the
/// padded convex hull of their nodes in the tag's colour. Sits in the scene
/// beneath the nodes; reads positions only and never moves a node.
class ConstellationTagHullLayer extends StatelessWidget {
  const ConstellationTagHullLayer({
    required this.controller,
    required this.tags,
    required this.peopleOf,
    super.key,
  });

  /// The key of the hull of tag [tagId].
  static Key hullKey(String tagId) => ValueKey('constellation-tag-hull-$tagId');

  final GraphController<NodeDetails, EdgeDetails> controller;

  /// The selected own tags, in tag order.
  final List<PersonTag> tags;

  /// Ids of the people in the own tag with the given id.
  final Set<String> Function(String tagId) peopleOf;

  @override
  Widget build(BuildContext context) {
    final swatches = Theme.of(
      context,
    ).extension<TenturaTagColors>()!.swatches;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, _) => Stack(
          fit: StackFit.expand,
          children: [
            for (final tag in tags)
              if (_centres(tag.id) case final centres when centres.isNotEmpty)
                CustomPaint(
                  key: hullKey(tag.id),
                  painter: _HullPainter(
                    centres: centres,
                    color: swatches[tag.color % swatches.length].accent
                        .withValues(alpha: _hullAlpha),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  List<Offset> _centres(String tagId) => [
    for (final id in peopleOf(tagId))
      ?controller.getPositionOrNullForId('fp:$id'),
  ];
}

class _HullPainter extends CustomPainter {
  const _HullPainter({required this.centres, required this.color});

  final List<Offset> centres;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    var hull = Path();
    for (final centre in centres) {
      hull = Path.combine(
        PathOperation.union,
        hull,
        Path()..addOval(Rect.fromCircle(center: centre, radius: _padding)),
      );
    }
    final outline = _convexHull(centres);
    if (outline.length > 2) {
      hull = Path.combine(
        PathOperation.union,
        hull,
        Path()..addPolygon(outline, true),
      );
    }
    canvas.drawPath(hull, Paint()..color = color);
  }

  static const _padding = kConstellationTagHullPadding;

  @override
  bool shouldRepaint(_HullPainter old) =>
      old.color != color || !_sameCentres(old.centres);

  bool _sameCentres(List<Offset> other) {
    if (other.length != centres.length) return false;
    for (var i = 0; i < other.length; i++) {
      if (other[i] != centres[i]) return false;
    }
    return true;
  }
}

/// Andrew's monotone chain; the points of the convex hull in order.
List<Offset> _convexHull(List<Offset> points) {
  if (points.length < 3) return points;
  final sorted = [
    ...points,
  ]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  double cross(Offset o, Offset a, Offset b) =>
      (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
  List<Offset> half(Iterable<Offset> input) {
    final chain = <Offset>[];
    for (final p in input) {
      while (chain.length >= 2 &&
          cross(chain[chain.length - 2], chain.last, p) <= 0) {
        chain.removeLast();
      }
      chain.add(p);
    }
    return chain..removeLast();
  }

  return [...half(sorted), ...half(sorted.reversed)];
}
