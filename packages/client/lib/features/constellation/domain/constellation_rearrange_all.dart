import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'constellation_drag_cluster.dart';
import 'constellation_layout.dart';

/// Where «Rearrange everyone» puts the Field: `pinned` holds the new centre of
/// every pinned node it can seat, `layout` the whole Field once those nodes
/// rest there and everyone else is laid out afresh around them.
typedef ConstellationRearrangement = ({
  Map<String, ConstellationPoint> pinned,
  ConstellationLayout layout,
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
  final seatedOffPath = {
    for (final id in input.pinnedPersonIds)
      if (id != input.egoId &&
          !input.paths.keep.contains(id) &&
          !input.paths.ring.contains(id))
        id,
  };
  final loose = (
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
  );
  final free = computeConstellationPlacedLayout(input: loose);
  final pinned = {
    for (final id in input.anchorByNodeId.keys)
      if (free.positions[id] case final point?)
        id: constellationClampToDragBounds(point),
  };
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
    priorHints: null,
    nodeSizes: input.nodeSizes,
    satelliteRequestIdsByAuthor: input.satelliteRequestIdsByAuthor,
    requestAuthorById: input.requestAuthorById,
    egoOwnRequestIds: input.egoOwnRequestIds,
    spacing: input.spacing,
    maxHops: input.maxHops,
    viewportClass: input.viewportClass,
    footprints: input.footprints,
  );
  return (
    pinned: pinned,
    layout: computeConstellationPlacedLayout(input: settled),
  );
}
