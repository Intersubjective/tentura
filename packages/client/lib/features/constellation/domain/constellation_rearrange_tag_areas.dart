import 'dart:math' as math;

import 'constellation_consts.dart';
import 'constellation_drag_cluster.dart';
import 'constellation_layout.dart';
import 'layout/layout_geometry.dart';

/// Result of staging tag areas before the settled layout pass.
typedef ConstellationRearrangeTagStaging = ({
  Map<String, ConstellationPoint> areaPositions,
  Map<String, ConstellationPoint> tagCentres,
});

/// Stages positions for own-tag «Rearrange everyone» areas on top of
/// [freeLayout] from the first pass.
///
/// Returns map entries only for people placed into a tag area (a person with
/// several tags sits in one of them). Empty when [input] carries no tag
/// membership.
Map<String, ConstellationPoint> constellationRearrangeTagAreaPositions({
  required ConstellationPlacedLayoutInput input,
  required ConstellationLayout freeLayout,
}) => constellationRearrangeTagStaging(
  input: input,
  freeLayout: freeLayout,
).areaPositions;

/// Same staging as [constellationRearrangeTagAreaPositions], plus tag centre
/// points from the first pass (mean direction + mean radius, or magnet).
ConstellationRearrangeTagStaging constellationRearrangeTagStaging({
  required ConstellationPlacedLayoutInput input,
  required ConstellationLayout freeLayout,
}) {
  ConstellationRearrangeTagStaging? out;
  for (final _ in constellationRearrangeTagStagingSteps(
    input: input,
    freeLayout: freeLayout,
    onComplete: (r) => out = r,
  )) {}
  return out ?? (areaPositions: const {}, tagCentres: const {});
}

/// Checkpoints for bounded layout jobs ([ConstellationTagStagingLayoutJob]).
/// Same granularity as [constellationPlacedLayoutSteps]: one yield per pass
/// through a small amount of deterministic work.
Iterable<void> constellationRearrangeTagStagingSteps({
  required ConstellationPlacedLayoutInput input,
  required ConstellationLayout freeLayout,
  required void Function(ConstellationRearrangeTagStaging) onComplete,
}) sync* {
  void finish(ConstellationRearrangeTagStaging r) {
    onComplete(r);
  }

  final tagPeople = input.rearrangeOwnTagPeopleByTagId;
  if (tagPeople.isEmpty) {
    finish((areaPositions: const {}, tagCentres: const {}));
    return;
  }
  if (!tagPeople.keys.any((id) => !id.startsWith('auto:'))) {
    finish((areaPositions: const {}, tagCentres: const {}));
    return;
  }
  final canvasCentre = constellationCanvasCentrePoint();
  final onFieldPeople = <String>{
    ...input.automaticKeptPeerIds,
    ...input.pinnedPersonIds,
    ...input.supportPersonIds,
  };
  final tagIds = tagPeople.keys.where((id) => !id.startsWith('auto:')).toList()
    ..sort();
  final personOwnTags = <String, Set<String>>{};
  for (final MapEntry(:key, :value) in tagPeople.entries) {
    if (key.startsWith('auto:')) {
      continue;
    }
    final tagId = key;
    for (final personId in value) {
      if (personId == input.egoId) continue;
      if (!onFieldPeople.contains(personId)) continue;
      if (freeLayout.positions[personId] == null) continue;
      personOwnTags.putIfAbsent(personId, () => {}).add(tagId);
      yield null;
    }
    yield null;
  }
  if (personOwnTags.isEmpty) {
    finish((areaPositions: const {}, tagCentres: const {}));
    return;
  }

  final depthsList = <int>{};
  for (final id in personOwnTags.keys) {
    depthsList.add(
      input.paths.depth[id] ??
          (input.paths.ring.contains(id) ? input.maxHops + 1 : input.maxHops),
    );
    yield null;
  }
  final depthsSorted = depthsList.toList()..sort();
  double ringRadius(int depth) =>
      (depthsSorted.indexOf(depth) + 1) * kConstellationRingUnitPixels;

  LPoint polar(LPoint ego, double angle, double radius) => (
    x: ego.x + radius * math.cos(angle),
    y: ego.y + radius * math.sin(angle),
  );

  final tagCentres = <String, ConstellationPoint>{};
  for (final tagId in tagIds) {
    final memberIds =
        tagPeople[tagId]!
            .where(
              (id) =>
                  id != input.egoId &&
                  onFieldPeople.contains(id) &&
                  freeLayout.positions[id] != null,
            )
            .toList()
          ..sort();
    if (memberIds.isEmpty) continue;
    final magnet = input.rearrangeTagMagnetsByTagId[tagId];
    if (magnet != null) {
      tagCentres[tagId] = constellationClampToDragBounds(magnet);
      yield null;
      continue;
    }
    var sx = 0.0;
    var sy = 0.0;
    var radSum = 0.0;
    for (final id in memberIds) {
      final p = freeLayout.positions[id]!;
      final ang = math.atan2(p.y - canvasCentre.y, p.x - canvasCentre.x);
      sx += math.cos(ang);
      sy += math.sin(ang);
      final depth =
          input.paths.depth[id] ??
          (input.paths.ring.contains(id) ? input.maxHops + 1 : input.maxHops);
      radSum += ringRadius(depth);
      yield null;
    }
    final angle = (sx.abs() < 1e-9 && sy.abs() < 1e-9)
        ? 0.0
        : math.atan2(sy, sx);
    final meanR = radSum / memberIds.length;
    tagCentres[tagId] = constellationClampToDragBounds(
      polar(canvasCentre, angle, meanR),
    );
    yield null;
  }

  final tagMemberCount = <String, int>{
    for (final tagId in tagIds)
      if (tagPeople[tagId] != null)
        tagId: tagPeople[tagId]!
            .where(
              (id) =>
                  id != input.egoId &&
                  onFieldPeople.contains(id) &&
                  freeLayout.positions[id] != null,
            )
            .length,
  };

  double cellFor(String id) {
    final size = input.nodeSizes[id] ?? (width: 64, height: 64);
    return math.max(size.width, size.height) + input.spacing;
  }

  double tagDiskRadius(String tagId) {
    final n = math.max(1, tagMemberCount[tagId] ?? 1);
    final members = tagPeople[tagId]!
        .where(
          (id) =>
              id != input.egoId &&
              onFieldPeople.contains(id) &&
              freeLayout.positions[id] != null,
        )
        .toList();
    var maxCell = 0.0;
    for (final id in members) {
      maxCell = math.max(maxCell, cellFor(id));
    }
    if (maxCell < 1e-6) {
      maxCell = 80;
    }
    return 2.5 * math.sqrt(n) * maxCell;
  }

  // Tags with no member in common never overlap: two such centres closer
  // than both disk radii plus the layout spacing are pushed apart along the
  // line joining them. Tags that share people stay close, so those people
  // sit between them. A magnet centre is where the viewer put it, so only
  // the other one moves.
  bool shareMembers(String a, String b) => personOwnTags.values.any(
    (tags) => tags.contains(a) && tags.contains(b),
  );
  final centreIds = tagCentres.keys.toList()..sort();
  for (var iter = 0; iter < 64; iter++) {
    var moved = false;
    for (var i = 0; i < centreIds.length; i++) {
      for (var j = i + 1; j < centreIds.length; j++) {
        final idA = centreIds[i];
        final idB = centreIds[j];
        final fixedA = input.rearrangeTagMagnetsByTagId.containsKey(idA);
        final fixedB = input.rearrangeTagMagnetsByTagId.containsKey(idB);
        if ((fixedA && fixedB) || shareMembers(idA, idB)) continue;
        final a = tagCentres[idA]!;
        final b = tagCentres[idB]!;
        final minGap =
            tagDiskRadius(idA) + tagDiskRadius(idB) + input.spacing + 1;
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d >= minGap) continue;
        final (ux, uy) = d < 1e-9 ? (1.0, 0.0) : (dx / d, dy / d);
        final push = minGap - d;
        final shareA = fixedA ? 0.0 : (fixedB ? 1.0 : 0.5);
        final shareB = 1 - shareA;
        tagCentres[idA] = constellationClampToDragBounds((
          x: a.x - ux * push * shareA,
          y: a.y - uy * push * shareA,
        ));
        tagCentres[idB] = constellationClampToDragBounds((
          x: b.x + ux * push * shareB,
          y: b.y + uy * push * shareB,
        ));
        moved = true;
        yield null;
      }
    }
    if (!moved) break;
  }

  final out = <String, ConstellationPoint>{};

  // Everyone sits in one tag's area: a person with several tags sits with
  // the tag that has the most people on the Field (ties: tag order), not
  // between the areas.
  String? homeTag(Set<String> tags) {
    String? best;
    for (final t in [...tags]..sort()) {
      if (!tagCentres.containsKey(t)) continue;
      if (best == null ||
          (tagMemberCount[t] ?? 0) > (tagMemberCount[best] ?? 0)) {
        best = t;
      }
    }
    return best;
  }

  final homeTagOf = <String, String>{
    for (final MapEntry(key: id, value: tags) in personOwnTags.entries)
      id: ?homeTag(tags),
  };

  final untaggedFieldPeople = <String>{
    for (final id in onFieldPeople)
      if (id != input.egoId &&
          freeLayout.positions[id] != null &&
          !personOwnTags.containsKey(id))
        id,
  };

  ConstellationPoint pushOutOfDisks(
    ConstellationPoint p,
    Set<String> diskCentres,
    String movingId,
  ) {
    var q = p;
    for (var iter = 0; iter < 48; iter++) {
      var adjusted = false;
      for (final tagId in diskCentres) {
        final c = tagCentres[tagId];
        if (c == null) continue;
        final radius = tagDiskRadius(tagId);
        final dx = q.x - c.x;
        final dy = q.y - c.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 1e-9 || dist >= radius - 1e-6) {
          continue;
        }
        final ux = dx / dist;
        final uy = dy / dist;
        q = (
          x: c.x + ux * (radius + 1),
          y: c.y + uy * (radius + 1),
        );
        q = constellationClampToDragBounds(
          q,
          size: input.nodeSizes[movingId] ?? (width: 64, height: 64),
        );
        adjusted = true;
      }
      if (!adjusted) break;
    }
    return q;
  }

  final diskCentreIds = tagCentres.keys.toSet();

  ConstellationPoint clampInsideDisk(
    ConstellationPoint p,
    ConstellationPoint centre,
    double radius,
  ) {
    final dx = p.x - centre.x;
    final dy = p.y - centre.y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d <= radius + 1e-9 || d < 1e-9) {
      return p;
    }
    final s = radius / d;
    return (x: centre.x + dx * s, y: centre.y + dy * s);
  }

  for (final tagId in tagIds) {
    final centreTag = tagCentres[tagId];
    if (centreTag == null) continue;
    final members =
        tagPeople[tagId]!
            .where(
              (id) =>
                  id != input.egoId &&
                  onFieldPeople.contains(id) &&
                  freeLayout.positions[id] != null &&
                  homeTagOf[id] == tagId,
            )
            .toList()
          ..sort();
    if (members.isEmpty) continue;

    final sortedMembers = [...members]
      ..sort((a, b) {
        final da =
            input.paths.depth[a] ??
            (input.paths.ring.contains(a) ? input.maxHops + 1 : input.maxHops);
        final db =
            input.paths.depth[b] ??
            (input.paths.ring.contains(b) ? input.maxHops + 1 : input.maxHops);
        final byDepth = da.compareTo(db);
        return byDepth != 0 ? byDepth : a.compareTo(b);
      });

    final diskR = tagDiskRadius(tagId);
    // A compact group: members take the cells of a square grid one node
    // cell wide nearest the tag centre, the cells on the viewer's side first
    // and the shallowest members first. Neighbours stand one cell apart on
    // an axis, so the layout's spacing test keeps every staged place and
    // the Field's tag area joins them into one shape, not a disc per person.
    var cell = 0.0;
    for (final id in sortedMembers) {
      cell = math.max(cell, cellFor(id));
    }
    final towardEgoX = canvasCentre.x - centreTag.x;
    final towardEgoY = canvasCentre.y - centreTag.y;
    final tow = math.sqrt(towardEgoX * towardEgoX + towardEgoY * towardEgoY);
    final bias = tow < 1e-6
        ? (x: 0.0, y: 0.0)
        : (x: 0.25 * towardEgoX / tow, y: 0.25 * towardEgoY / tow);
    final reach = math.sqrt(sortedMembers.length).ceil() + 1;
    final slots = [
      for (var gx = -reach; gx <= reach; gx++)
        for (var gy = -reach; gy <= reach; gy++) (x: gx, y: gy),
    ];
    double slotRank(({int x, int y}) g) =>
        math.pow(g.x - bias.x, 2) + math.pow(g.y - bias.y, 2).toDouble();
    slots.sort((a, b) {
      final byRank = slotRank(a).compareTo(slotRank(b));
      if (byRank != 0) return byRank;
      final byY = a.y.compareTo(b.y);
      return byY != 0 ? byY : a.x.compareTo(b.x);
    });

    for (var i = 0; i < sortedMembers.length; i++) {
      final id = sortedMembers[i];
      var raw = (
        x: centreTag.x + slots[i].x * cell,
        y: centreTag.y + slots[i].y * cell,
      );
      // Disks of tags that share people with this one may overlap it (see
      // the separation pass), so only the other tags' disks push out.
      raw = pushOutOfDisks(
        raw,
        {
          for (final t in diskCentreIds)
            if (!personOwnTags[id]!.contains(t) && !shareMembers(tagId, t)) t,
        },
        id,
      );
      raw = clampInsideDisk(raw, centreTag, diskR);
      out[id] = constellationClampToDragBounds(
        raw,
        size: input.nodeSizes[id] ?? (width: 64, height: 64),
      );
      yield null;
    }
  }

  for (final ut in untaggedFieldPeople) {
    final hint = freeLayout.positions[ut];
    if (hint == null) continue;
    var wasInside = false;
    for (final tid in diskCentreIds) {
      final c = tagCentres[tid];
      if (c == null) continue;
      final dx = hint.x - c.x;
      final dy = hint.y - c.y;
      if (math.sqrt(dx * dx + dy * dy) < tagDiskRadius(tid) - 1e-6) {
        wasInside = true;
        break;
      }
      yield null;
    }
    if (!wasInside) {
      continue;
    }
    var pushed = hint;
    for (var iter = 0; iter < 48; iter++) {
      var adjusted = false;
      for (final tagId in diskCentreIds) {
        final c = tagCentres[tagId];
        if (c == null) continue;
        final radius = tagDiskRadius(tagId);
        final dx = pushed.x - c.x;
        final dy = pushed.y - c.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 1e-9 || dist >= radius - 1e-6) {
          yield null;
          continue;
        }
        final ux = dx / dist;
        final uy = dy / dist;
        pushed = (
          x: c.x + ux * (radius + 1),
          y: c.y + uy * (radius + 1),
        );
        pushed = constellationClampToDragBounds(
          pushed,
          size: input.nodeSizes[ut] ?? (width: 64, height: 64),
        );
        adjusted = true;
        yield null;
      }
      if (!adjusted) break;
      yield null;
    }
    out[ut] = pushed;
    yield null;
  }

  finish((areaPositions: out, tagCentres: tagCentres));
}
