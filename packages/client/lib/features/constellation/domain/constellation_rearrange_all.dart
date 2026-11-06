import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'constellation_drag_cluster.dart';
import 'constellation_layout.dart';
import 'constellation_rearrange_tag_areas.dart';

/// First pass of [computeConstellationRearrangeAll]: same graph as rearrange
/// everyone uses for the free layout (pins cleared; seated-off-path merged).
ConstellationPlacedLayoutInput constellationRearrangeLoosePlacementInput(
  ConstellationPlacedLayoutInput input,
) {
  final seatedOffPath = {
    for (final id in input.pinnedPersonIds)
      if (id != input.egoId &&
          !input.paths.keep.contains(id) &&
          !input.paths.ring.contains(id))
        id,
  };
  return (
    egoId: input.egoId,
    paths: seatedOffPath.isEmpty
        ? input.paths
        : (
            depth: input.paths.depth,
            derived: input.paths.derived,
            parent: input.paths.parent,
            parentTier: input.paths.parentTier,
            attributed: input.paths.attributed,
            keep: input.paths.keep,
            ring: {...input.paths.ring, ...seatedOffPath},
          ),
    automaticKeptPeerIds: {
      ...input.automaticKeptPeerIds,
      ...input.pinnedPersonIds,
    },
    pinnedPersonIds: const <String>{},
    pinnedRequestIds: const <String>{},
    supportPersonIds: input.supportPersonIds,
    anchorByNodeId: const <String, ConstellationAnchorPosition>{},
    priorHints: null,
    nodeSizes: input.nodeSizes,
    satelliteRequestIdsByAuthor: input.satelliteRequestIdsByAuthor,
    requestAuthorById: input.requestAuthorById,
    egoOwnRequestIds: input.egoOwnRequestIds,
    spacing: input.spacing,
    maxHops: input.maxHops,
    viewportClass: input.viewportClass,
    footprints: input.footprints,
    rearrangeOwnTagPeopleByTagId: input.rearrangeOwnTagPeopleByTagId,
    rearrangeTagMagnetsByTagId: input.rearrangeTagMagnetsByTagId,
  );
}

/// Where «Rearrange everyone» puts the Field: `pinned` holds the new centre of
/// every pinned node it can seat, `layout` the whole Field once those nodes
/// rest there and everyone else is laid out afresh around them.
typedef ConstellationRearrangement = ({
  Map<String, ConstellationPoint> pinned,
  ConstellationLayout layout,
  Map<String, ConstellationPoint> tagCentres,
});

/// A full re-layout of [input] that ignores its pins and session inertia.
///
/// The pinned people join the automatic ones for a first layout without
/// anchors; each pinned node takes the place that layout gives it, held to
/// the bounds a drag holds a node to, and stays pinned there. A second layout
/// with the pins at those places is what the Field shows once they are
/// written, so `layout` is exactly what Apply
/// produces. A pinned node the first layout cannot seat keeps its anchor.
ConstellationRearrangement computeConstellationRearrangeAll(
  ConstellationPlacedLayoutInput input,
) {
  final loose = constellationRearrangeLoosePlacementInput(input);
  final free = computeConstellationPlacedLayout(input: loose);
  final hasOwnTagIds = input.rearrangeOwnTagPeopleByTagId.keys.any(
    (k) => !k.startsWith('auto:'),
  );
  final staging = hasOwnTagIds
      ? constellationRearrangeTagStaging(
          input: input,
          freeLayout: free,
        )
      : (
          areaPositions: const <String, ConstellationPoint>{},
          tagCentres: const <String, ConstellationPoint>{},
        );
  final tagArea = staging.areaPositions;
  final tagCentres = staging.tagCentres;
  final pinned = <String, ConstellationPoint>{
    for (final id in input.anchorByNodeId.keys)
      if (free.positions[id] case final point?)
        id: constellationClampToDragBounds(point),
  };
  for (final entry in tagArea.entries) {
    pinned[entry.key] = constellationClampToDragBounds(entry.value);
  }

  final priorHints = tagArea.isEmpty
      ? null
      : (
          positions: <String, ConstellationPoint>{
            ...free.positions,
            ...tagArea,
          },
          ring: Map<String, int>.from(free.ring),
          viewportClass: input.viewportClass,
        );

  final settled = (
    egoId: input.egoId,
    paths: input.paths,
    automaticKeptPeerIds: input.automaticKeptPeerIds,
    pinnedPersonIds: input.pinnedPersonIds,
    pinnedRequestIds: input.pinnedRequestIds,
    supportPersonIds: input.supportPersonIds,
    anchorByNodeId: {
      ...input.anchorByNodeId,
      for (final entry in pinned.entries)
        entry.key: constellationPointToV1Anchor(entry.value),
    },
    priorHints: priorHints,
    nodeSizes: input.nodeSizes,
    satelliteRequestIdsByAuthor: input.satelliteRequestIdsByAuthor,
    requestAuthorById: input.requestAuthorById,
    egoOwnRequestIds: input.egoOwnRequestIds,
    spacing: input.spacing,
    maxHops: input.maxHops,
    viewportClass: input.viewportClass,
    footprints: input.footprints,
    rearrangeOwnTagPeopleByTagId: input.rearrangeOwnTagPeopleByTagId,
    rearrangeTagMagnetsByTagId: input.rearrangeTagMagnetsByTagId,
  );
  var layout = computeConstellationPlacedLayout(input: settled);

  final ownTagIds =
      input.rearrangeOwnTagPeopleByTagId.keys
          .where((k) => !k.startsWith('auto:'))
          .toList()
        ..sort();
  if (ownTagIds.length == 2 && tagCentres.length == 2 && tagArea.isNotEmpty) {
    final t0 = ownTagIds[0];
    final t1 = ownTagIds[1];
    final a = tagCentres[t0];
    final b = tagCentres[t1];
    final set0 = input.rearrangeOwnTagPeopleByTagId[t0];
    final set1 = input.rearrangeOwnTagPeopleByTagId[t1];
    if (a != null && b != null && set0 != null && set1 != null) {
      final personTags = <String, Set<String>>{};
      for (final id in set0) {
        personTags.putIfAbsent(id, () => {}).add(t0);
      }
      for (final id in set1) {
        personTags.putIfAbsent(id, () => {}).add(t1);
      }

      final nextPositions = Map<String, ConstellationPoint>.from(
        layout.positions,
      );

      final both = set0.intersection(set1);
      for (final id in both) {
        final current = nextPositions[id];
        if (current == null) continue;
        final onSeg = _nearestPointOnSegment(current, a, b);
        final snapped = constellationClampToDragBounds(
          onSeg,
          size: input.nodeSizes[id] ?? (width: 64, height: 64),
        );
        nextPositions[id] = snapped;
        if (pinned.containsKey(id)) {
          pinned[id] = snapped;
        }
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
        var p = start;
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
        }
        nextPositions[key] = p;
        if (pinned.containsKey(key)) {
          pinned[key] = p;
        }
      }

      layout = (positions: nextPositions, ring: layout.ring);
    }
  }

  return (
    pinned: pinned,
    layout: layout,
    tagCentres: tagCentres,
  );
}

ConstellationPoint _nearestPointOnSegment(
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
