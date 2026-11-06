import 'constellation_drag_cluster.dart';
import 'constellation_layout.dart';

import 'constellation_rearrange_tag_areas.dart';

/// Segment snap + membership pull for exactly two own tags (see #1040).
/// Checkpoints match other rearrange jobs for bounded work.
Iterable<void> constellationRearrangeTwoTagRefinementSteps({
  required ConstellationPlacedLayoutInput input,
  required Map<String, ConstellationPoint> tagCentres,
  required ConstellationRearrangeTagStaging staging,
  required Map<String, ConstellationPoint> pinned,
  required ConstellationLayout layout,
  required void Function(ConstellationLayout) onComplete,
}) sync* {
  final tagArea = staging.areaPositions;
  final ownTagIds =
      input.rearrangeOwnTagPeopleByTagId.keys
          .where((k) => !k.startsWith('auto:'))
          .toList()
        ..sort();
  if (ownTagIds.length != 2 || tagCentres.length != 2 || tagArea.isEmpty) {
    onComplete(layout);
    return;
  }
  final t0 = ownTagIds[0];
  final t1 = ownTagIds[1];
  final a = tagCentres[t0];
  final b = tagCentres[t1];
  final set0 = input.rearrangeOwnTagPeopleByTagId[t0];
  final set1 = input.rearrangeOwnTagPeopleByTagId[t1];
  if (a == null || b == null || set0 == null || set1 == null) {
    onComplete(layout);
    return;
  }
  final personTags = <String, Set<String>>{};
  for (final id in set0) {
    personTags.putIfAbsent(id, () => {}).add(t0);
    yield null;
  }
  for (final id in set1) {
    personTags.putIfAbsent(id, () => {}).add(t1);
    yield null;
  }

  final nextPositions = Map<String, ConstellationPoint>.from(layout.positions);

  final both = set0.intersection(set1);
  for (final id in both) {
    final current = nextPositions[id];
    if (current == null) continue;
    final onSeg = _nearestPointOnSegmentRefinement(current, a, b);
    final snapped = constellationClampToDragBounds(
      onSeg,
      size: input.nodeSizes[id] ?? (width: 64, height: 64),
    );
    nextPositions[id] = snapped;
    if (pinned.containsKey(id)) {
      pinned[id] = snapped;
    }
    yield null;
  }

  for (final MapEntry(:key, :value) in personTags.entries) {
    if (value.length != 1) continue;
    final tagId = value.first;
    final otherId = tagId == t0 ? t1 : t0;
    final cOwn = tagCentres[tagId];
    final cOth = tagCentres[otherId];
    if (cOwn == null || cOth == null) continue;
    final start = nextPositions[key];
    if (start == null) continue;
    ConstellationPoint p = start;
    double dist2(ConstellationPoint u, ConstellationPoint v) {
      final dx = u.x - v.x;
      final dy = u.y - v.y;
      return dx * dx + dy * dy;
    }

    for (var i = 0; i < 24 && dist2(p, cOwn) >= dist2(p, cOth); i++) {
      p = (
        x: p.x + 0.22 * (cOwn.x - p.x),
        y: p.y + 0.22 * (cOwn.y - p.y),
      );
      p = constellationClampToDragBounds(
        p,
        size: input.nodeSizes[key] ?? (width: 64, height: 64),
      );
      yield null;
    }
    nextPositions[key] = p;
    if (pinned.containsKey(key)) {
      pinned[key] = p;
    }
    yield null;
  }

  onComplete((positions: nextPositions, ring: layout.ring));
}

ConstellationLayout applyConstellationRearrangeTwoTagRefinement({
  required ConstellationPlacedLayoutInput input,
  required Map<String, ConstellationPoint> tagCentres,
  required ConstellationRearrangeTagStaging staging,
  required Map<String, ConstellationPoint> pinned,
  required ConstellationLayout layout,
}) {
  ConstellationLayout? out;
  for (final _ in constellationRearrangeTwoTagRefinementSteps(
    input: input,
    tagCentres: tagCentres,
    staging: staging,
    pinned: pinned,
    layout: layout,
    onComplete: (l) => out = l,
  )) {}
  return out ?? layout;
}

ConstellationPoint _nearestPointOnSegmentRefinement(
  ConstellationPoint p,
  ConstellationPoint a,
  ConstellationPoint b,
) {
  final abx = b.x - a.x;
  final aby = b.y - a.y;
  final apx = p.x - a.x;
  final apy = p.y - a.y;
  final ab2 = abx * abx + aby * aby;
  final t = ab2 < 1e-12 ? 0.0 : ((apx * abx + apy * aby) / ab2).clamp(0.0, 1.0);
  return (
    x: a.x + t * abx,
    y: a.y + t * aby,
  );
}
