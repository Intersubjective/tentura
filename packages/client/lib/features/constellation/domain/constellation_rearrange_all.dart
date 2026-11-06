import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'constellation_drag_cluster.dart';
import 'constellation_layout.dart';
import 'constellation_rearrange_tag_areas.dart';
import 'constellation_rearrange_two_tag_refinement.dart';

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

  layout = applyConstellationRearrangeTwoTagRefinement(
    input: input,
    tagCentres: tagCentres,
    staging: staging,
    pinned: pinned,
    layout: layout,
  );

  return (
    pinned: pinned,
    layout: layout,
    tagCentres: tagCentres,
  );
}
