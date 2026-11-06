import 'package:meta/meta.dart' show visibleForTesting;

import 'constellation_anchor_composition.dart';
import 'constellation_layout.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

int _pinLayoutRunCount = 0;

/// Placed-layout runs performed on behalf of pin positions.
@visibleForTesting
int get constellationPinLayoutRunCount => _pinLayoutRunCount;

/// Inverts each automatic peer's own tag ids into tag id → member ids for the
/// rearrange-everyone pass.
Map<String, Set<String>> rearrangeOwnTagPeopleFromComposition({
  required String viewerId,
  required ConstellationComposedPresentation composition,
}) {
  final eligible = <String>{
    ...composition.keptPeerIds,
    for (final p in composition.anchorOverlay.pinnedPeers) p.id,
    for (final p in composition.anchorOverlay.supportPeers) p.id,
  };
  final byTag = <String, Set<String>>{};
  for (final peer in composition.automatic.peers) {
    if (peer.id == viewerId || !eligible.contains(peer.id)) {
      continue;
    }
    for (final tagId in peer.ownTagIds) {
      byTag.putIfAbsent(tagId, () => {}).add(peer.id);
    }
  }
  return byTag;
}

ConstellationLayout _runPinLayout(ConstellationPlacedLayoutInput input) {
  _pinLayoutRunCount++;
  return computeConstellationPlacedLayout(input: input);
}

/// The placed layout of [layoutInput] for pin positions, to be shared by
/// every [computeConstellationPinPosition] call over the same input.
ConstellationLayout computeConstellationPinBaseLayout(
  ConstellationPlacedLayoutInput layoutInput,
) => _runPinLayout(layoutInput);

/// [placedLayout], when given, must be [computeConstellationPinBaseLayout] of
/// the same [layoutInput]; it saves rerunning the layout per target.
ConstellationAnchorPosition? computeConstellationPinPosition({
  required ConstellationAnchorTarget target,
  required ConstellationPlacedLayoutInput layoutInput,
  ConstellationLayout? placedLayout,
}) {
  final nodeId = target.graphNodeId;

  placedLayout ??= _runPinLayout(layoutInput);
  final composed = placedLayout.positions[nodeId];
  if (composed != null) {
    return constellationPointToV1Anchor(composed);
  }

  final scratchInput = _scratchInputAddingTarget(
    target: target,
    layoutInput: layoutInput,
  );
  if (scratchInput == null) {
    return null;
  }

  final candidateLayout = _runPinLayout(scratchInput);
  final candidate = candidateLayout.positions[nodeId];
  if (candidate == null) {
    return null;
  }
  return constellationPointToV1Anchor(candidate);
}

ConstellationPlacedLayoutInput? _scratchInputAddingTarget({
  required ConstellationAnchorTarget target,
  required ConstellationPlacedLayoutInput layoutInput,
}) {
  return switch (target) {
    ConstellationAnchorPersonTarget(:final id) =>
      layoutInput.pinnedPersonIds.contains(id)
          ? layoutInput
          : (
              egoId: layoutInput.egoId,
              paths: layoutInput.paths,
              automaticKeptPeerIds: {
                ...layoutInput.automaticKeptPeerIds,
                id,
              },
              pinnedPersonIds: layoutInput.pinnedPersonIds,
              pinnedRequestIds: layoutInput.pinnedRequestIds,
              supportPersonIds: layoutInput.supportPersonIds,
              anchorByNodeId: layoutInput.anchorByNodeId,
              priorHints: layoutInput.priorHints,
              nodeSizes: layoutInput.nodeSizes,
              satelliteRequestIdsByAuthor:
                  layoutInput.satelliteRequestIdsByAuthor,
              requestAuthorById: layoutInput.requestAuthorById,
              egoOwnRequestIds: layoutInput.egoOwnRequestIds,
              spacing: layoutInput.spacing,
              maxHops: layoutInput.maxHops,
              viewportClass: layoutInput.viewportClass,
              footprints: layoutInput.footprints,
              rearrangeOwnTagPeopleByTagId:
                  layoutInput.rearrangeOwnTagPeopleByTagId,
              rearrangeTagMagnetsByTagId:
                  layoutInput.rearrangeTagMagnetsByTagId,
            ),
    ConstellationAnchorBeaconTarget(:final id) => () {
      final authorId = layoutInput.requestAuthorById[id];
      if (authorId == null) {
        return null;
      }
      final byAuthor = {
        for (final entry in layoutInput.satelliteRequestIdsByAuthor.entries)
          entry.key: List<String>.from(entry.value),
      };
      final list = byAuthor.putIfAbsent(authorId, () => <String>[]);
      if (!list.contains(id)) {
        list
          ..add(id)
          ..sort();
      }
      return (
        egoId: layoutInput.egoId,
        paths: layoutInput.paths,
        automaticKeptPeerIds: layoutInput.automaticKeptPeerIds,
        pinnedPersonIds: layoutInput.pinnedPersonIds,
        pinnedRequestIds: layoutInput.pinnedRequestIds,
        supportPersonIds: layoutInput.supportPersonIds,
        anchorByNodeId: layoutInput.anchorByNodeId,
        priorHints: layoutInput.priorHints,
        nodeSizes: layoutInput.nodeSizes,
        satelliteRequestIdsByAuthor: byAuthor,
        requestAuthorById: layoutInput.requestAuthorById,
        egoOwnRequestIds: layoutInput.egoOwnRequestIds,
        spacing: layoutInput.spacing,
        maxHops: layoutInput.maxHops,
        viewportClass: layoutInput.viewportClass,
        footprints: layoutInput.footprints,
        rearrangeOwnTagPeopleByTagId: layoutInput.rearrangeOwnTagPeopleByTagId,
        rearrangeTagMagnetsByTagId: layoutInput.rearrangeTagMagnetsByTagId,
      );
    }(),
  };
}

ConstellationPlacedLayoutInput layoutInputFromComposition({
  required String viewerId,
  required ConstellationComposedPresentation composition,
  required ConstellationLabelDisplayPlan labelPlan,
  required Map<String, ConstellationSize> nodeSizes,
  required double spacing,
  ConstellationLayoutPriorHints? priorHints,
  ConstellationViewportClass viewportClass =
      ConstellationViewportClass.expanded,
  Map<String, ConstellationFootprint> footprints = const {},
  Map<String, Set<String>> rearrangeOwnTagPeopleByTagId = const {},
  Map<String, ConstellationPoint> rearrangeTagMagnetsByTagId = const {},
}) {
  final anchorByNodeId = constellationAnchorsByNodeId(
    composition.anchorOverlay.anchors,
  );
  final pinnedPersonIds = {
    for (final peer in composition.anchorOverlay.pinnedPeers) peer.id,
  };
  final pinnedRequestIds = {
    for (final request in composition.anchorOverlay.pinnedRequests) request.id,
    ...composition.pinnedPostIds,
  };
  final supportPersonIds = {
    for (final peer in composition.anchorOverlay.supportPeers) peer.id,
  };

  final drawnSatellites = constellationDrawnSatellites(labelPlan);

  final requestAuthorById = {
    for (final request in composition.automatic.requests)
      request.id: request.authorId,
    for (final request in composition.anchorOverlay.pinnedRequests)
      request.id: request.authorId,
    for (final node in composition.beaconNodes)
      if (node.post case final post?) post.id: post.authorId,
  };

  final pinLayoutPeerIds = {
    ...composition.keptPeerIds,
    for (final peer in composition.automatic.peers) peer.id,
  };
  final automaticKeptPeerIds = pinLayoutPeerIds.difference({
    ...pinnedPersonIds,
    ...supportPersonIds,
  });
  final holderIds = {
    viewerId,
    ...pinLayoutPeerIds,
    for (final request in composition.anchorOverlay.pinnedRequests)
      request.authorId,
  };
  final paths = resolveConstellationPaths(
    egoId: viewerId,
    visiblePeerIds: pinLayoutPeerIds,
    holderIds: holderIds,
    edges: [
      for (final edge in composition.automatic.edges)
        (src: edge.src, dst: edge.dst, tier: edge.tier),
      for (final edge in composition.anchorOverlay.supportEdges)
        (src: edge.src, dst: edge.dst, tier: edge.tier),
    ],
  );

  return (
    egoId: viewerId,
    paths: paths,
    automaticKeptPeerIds: automaticKeptPeerIds,
    pinnedPersonIds: pinnedPersonIds,
    pinnedRequestIds: pinnedRequestIds,
    supportPersonIds: supportPersonIds,
    anchorByNodeId: {
      for (final entry in anchorByNodeId.entries)
        entry.key: entry.value.position,
    },
    priorHints: priorHints,
    nodeSizes: nodeSizes,
    satelliteRequestIdsByAuthor: drawnSatellites.byAuthor,
    requestAuthorById: requestAuthorById,
    egoOwnRequestIds: drawnSatellites.egoOwn,
    spacing: spacing,
    maxHops: 3,
    viewportClass: viewportClass,
    footprints: footprints,
    rearrangeOwnTagPeopleByTagId: rearrangeOwnTagPeopleByTagId,
    rearrangeTagMagnetsByTagId: rearrangeTagMagnetsByTagId,
  );
}
