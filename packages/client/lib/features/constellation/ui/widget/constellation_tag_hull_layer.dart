import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_tag_colors.dart';
import 'package:tentura/design_system/tentura_tokens.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';

/// Scene-space margin the hull keeps around the nodes it encloses.
const kConstellationTagHullPadding = 56.0;

const _hullAlphaUnselected = 0.18;
const _hullAlphaSelected = 0.32;
const _hullOutlineWidth = 1.0;

/// Own-tag hull paint order: unselected tags first, then selected (on top).
List<PersonTag> constellationTagHullPaintOrder(
  List<PersonTag> tags,
  Set<String> selectedTagIds,
) => [
  for (final tag in tags)
    if (!selectedTagIds.contains(tag.id)) tag,
  for (final tag in tags)
    if (selectedTagIds.contains(tag.id)) tag,
];

/// Scene-space hull path around member node centres (same geometry as the layer).
Path buildConstellationTagHullPath(List<Offset> centres) {
  var hull = Path();
  for (final centre in centres) {
    hull = Path.combine(
      PathOperation.union,
      hull,
      Path()..addOval(
        Rect.fromCircle(center: centre, radius: kConstellationTagHullPadding),
      ),
    );
  }
  final ring = _convexHull(centres);
  if (ring.length > 2) {
    hull = Path.combine(
      PathOperation.union,
      hull,
      Path()..addPolygon(ring, true),
    );
  }
  return hull;
}

/// Scene-space hit test for own-tag hulls. Call `update` when tags, selection,
/// or member positions change; `tagHullAt` is cheap on repeated pointer moves.
///
/// Returns null when the point hits a map node (people, Requests, Posts) or
/// lies outside every hull. Topmost hull matches `constellationTagHullPaintOrder`.
class ConstellationTagHullHitTester {
  ConstellationTagHullHitTester({required this.hitsMapNode});

  /// Whether the point hits any Field node body (not hull empty space).
  final bool Function(Offset scenePoint) hitsMapNode;

  late GraphController<NodeDetails, EdgeDetails> _controller;
  late List<PersonTag> _tags;
  late Set<String> _selectedTagIds;
  late Set<String> Function(String tagId) _peopleOf;

  final Map<String, _CachedTagHullPath> _pathsByTagId = {};

  /// How many times [buildConstellationTagHullPath] ran since construction or
  /// [clearPathBuildCountForTesting].
  @visibleForTesting
  int pathBuildCount = 0;

  @visibleForTesting
  void clearPathBuildCountForTesting() => pathBuildCount = 0;

  void update({
    required GraphController<NodeDetails, EdgeDetails> controller,
    required List<PersonTag> tags,
    required Set<String> selectedTagIds,
    required Set<String> Function(String tagId) peopleOf,
  }) {
    _controller = controller;
    _tags = tags;
    _selectedTagIds = selectedTagIds;
    _peopleOf = peopleOf;

    final liveIds = <String>{};
    for (final tag in tags) {
      liveIds.add(tag.id);
      final centres = _memberCentres(tag.id);
      if (centres.isEmpty) {
        _pathsByTagId.remove(tag.id);
        continue;
      }
      final cached = _pathsByTagId[tag.id];
      if (cached != null && _sameCentres(cached.centres, centres)) {
        continue;
      }
      pathBuildCount++;
      _pathsByTagId[tag.id] = _CachedTagHullPath(
        centres: centres,
        path: buildConstellationTagHullPath(centres),
      );
    }
    _pathsByTagId.removeWhere((id, _) => !liveIds.contains(id));
  }

  /// Own-tag id whose hull contains [scenePoint], or null.
  String? tagHullAt(Offset scenePoint) {
    if (hitsMapNode(scenePoint)) {
      return null;
    }
    final paintOrder = constellationTagHullPaintOrder(_tags, _selectedTagIds);
    for (var i = paintOrder.length - 1; i >= 0; i--) {
      final tag = paintOrder[i];
      final cached = _pathsByTagId[tag.id];
      if (cached != null && cached.path.contains(scenePoint)) {
        return tag.id;
      }
    }
    return null;
  }

  List<Offset> _memberCentres(String tagId) => [
    for (final id in _peopleOf(tagId))
      ?_controller.getPositionOrNullForId('fp:$id'),
  ];
}

final class _CachedTagHullPath {
  const _CachedTagHullPath({required this.centres, required this.path});

  final List<Offset> centres;
  final Path path;
}

bool _sameCentres(List<Offset> a, List<Offset> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// A soft hull around the Field people of every own tag that has someone on
/// the map: the padded convex hull of their nodes in the tag's colour.
/// Selected tags are drawn brighter with a thin outline and on top. Sits in
/// the scene beneath the nodes; reads positions only and never moves a node.
/// Automatic tags never get a hull (callers pass own tags only).
class ConstellationTagHullLayer extends StatelessWidget {
  const ConstellationTagHullLayer({
    required this.controller,
    required this.tags,
    required this.selectedTagIds,
    required this.peopleOf,
    this.dragHighlightTagId,
    super.key,
  });

  /// The key of the hull of tag [tagId].
  static Key hullKey(String tagId) => ValueKey('constellation-tag-hull-$tagId');

  final GraphController<NodeDetails, EdgeDetails> controller;

  /// Own tags that have at least one person on the Field, in tag order.
  final List<PersonTag> tags;

  /// Own tags currently selected in the lens; hulls for these ids highlight.
  final Set<String> selectedTagIds;

  /// Ids of the people in the own tag with the given id.
  final Set<String> Function(String tagId) peopleOf;

  /// While dragging a tag area (#1021), this hull is outlined more strongly.
  final String? dragHighlightTagId;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final swatches = Theme.of(
      context,
    ).extension<TenturaTagColors>()!.swatches;
    final paintOrder = constellationTagHullPaintOrder(tags, selectedTagIds);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, _) => Stack(
          fit: StackFit.expand,
          children: [
            for (final tag in paintOrder)
              if (_centres(tag.id) case final centres when centres.isNotEmpty)
                CustomPaint(
                  key: hullKey(tag.id),
                  painter: _HullPainter(
                    centres: centres,
                    fillColor: swatches[tag.color % swatches.length].accent
                        .withValues(
                          alpha: dragHighlightTagId == tag.id
                              ? (_hullAlphaSelected + 0.12).clamp(0, 1).toDouble()
                              : selectedTagIds.contains(tag.id)
                              ? _hullAlphaSelected
                              : _hullAlphaUnselected,
                        ),
                    outlineWidth: dragHighlightTagId == tag.id
                        ? tt.tightGap / 2
                        : _hullOutlineWidth,
                    outlineColor: selectedTagIds.contains(tag.id) ||
                            dragHighlightTagId == tag.id
                        ? swatches[tag.color % swatches.length].accent
                        : null,
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
  const _HullPainter({
    required this.centres,
    required this.fillColor,
    required this.outlineWidth,
    this.outlineColor,
  });

  final List<Offset> centres;
  final Color fillColor;
  final Color? outlineColor;
  final double outlineWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final hull = buildConstellationTagHullPath(centres);
    canvas.drawPath(hull, Paint()..color = fillColor);
    final stroke = outlineColor;
    if (stroke != null) {
      canvas.drawPath(
        hull,
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = outlineWidth,
      );
    }
  }

  @override
  bool shouldRepaint(_HullPainter old) =>
      old.fillColor != fillColor ||
      old.outlineColor != outlineColor ||
      old.outlineWidth != outlineWidth ||
      !_sameCentres(old.centres, centres);
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
