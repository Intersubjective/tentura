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
/// Returns map entries only for people placed into a tag area (including
/// multi-tag midpoints). Empty when [input] carries no tag membership.
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

  final out = <String, ConstellationPoint>{};

  {
    final multiIds =
        personOwnTags.entries
            .where((e) => e.value.length > 1)
            .map((e) => e.key)
            .toList()
          ..sort();
    for (final id in multiIds) {
      final tags = personOwnTags[id]!.toList()..sort();
      final memberCentres = [
        for (final t in tags)
          if (tagCentres[t] != null) tagCentres[t]!,
      ];
      if (memberCentres.length < 2) continue;
      final cx =
          memberCentres.map((c) => c.x).reduce((a, b) => a + b) /
          memberCentres.length;
      final cy =
          memberCentres.map((c) => c.y).reduce((a, b) => a + b) /
          memberCentres.length;
      out[id] = constellationClampToDragBounds((x: cx, y: cy));
      yield null;
    }
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
                  personOwnTags[id]!.length == 1,
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
    final tagPhase = tagIds.indexOf(tagId) * 0.2;
    final nMem = sortedMembers.length;

    for (var i = 0; i < sortedMembers.length; i++) {
      final id = sortedMembers[i];

      final cell = cellFor(id);
      final t = (i + 0.5) / nMem;
      final radial = diskR * math.sqrt(t) * 0.92;
      final angle = 2 * math.pi * i / nMem + tagPhase;
      var raw = (
        x: centreTag.x + radial * math.cos(angle),
        y: centreTag.y + radial * math.sin(angle),
      );
      raw = pushOutOfDisks(raw, {tagId}, id);
      final rdx = raw.x - centreTag.x;
      final rdy = raw.y - centreTag.y;
      final rd = math.sqrt(rdx * rdx + rdy * rdy);
      if (rd > diskR) {
        final scale = diskR / rd;
        raw = (
          x: centreTag.x + rdx * scale,
          y: centreTag.y + rdy * scale,
        );
      }
      final depth =
          input.paths.depth[id] ??
          (input.paths.ring.contains(id) ? input.maxHops + 1 : input.maxHops);
      final shallow = sortedMembers
          .map(
            (m) =>
                input.paths.depth[m] ??
                (input.paths.ring.contains(m)
                    ? input.maxHops + 1
                    : input.maxHops),
          )
          .reduce(math.min);
      final towardEgoDx = canvasCentre.x - centreTag.x;
      final towardEgoDy = canvasCentre.y - centreTag.y;
      final tow = math.sqrt(
        towardEgoDx * towardEgoDx + towardEgoDy * towardEgoDy,
      );
      if (tow > 1e-6 && depth == shallow) {
        final tuck = 0.06 * cell;
        raw = (
          x: raw.x + towardEgoDx / tow * tuck,
          y: raw.y + towardEgoDy / tow * tuck,
        );
      }
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
