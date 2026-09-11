import 'constellation_anchor_composition.dart';
import 'constellation_layout.dart';
import 'entity/constellation_anchor.dart';

ConstellationAnchorPosition? computeConstellationPinPosition({
  required ConstellationAnchorTarget target,
  required ConstellationPlacedLayoutInput layoutInput,
}) {
  final nodeId = target.graphNodeId;

  final placedLayout = computeConstellationPlacedLayout(input: layoutInput);
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

  final candidateLayout = computeConstellationPlacedLayout(input: scratchInput);
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
        byAuthor.putIfAbsent(authorId, () => <String>[]);
        if (!byAuthor[authorId]!.contains(id)) {
          byAuthor[authorId]!.add(id);
          byAuthor[authorId]!.sort();
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
  ConstellationViewportClass viewportClass = ConstellationViewportClass.expanded,
}) {
  final anchorByNodeId = constellationAnchorsByNodeId(
    composition.anchorOverlay.anchors,
  );
  final pinnedPersonIds = {
    for (final peer in composition.anchorOverlay.pinnedPeers) peer.id,
  };
  final pinnedRequestIds = {
    for (final request in composition.anchorOverlay.pinnedRequests) request.id,
  };
  final supportPersonIds = {
    for (final peer in composition.anchorOverlay.supportPeers) peer.id,
  };

  final visibleByAuthor = <String, List<String>>{};
  for (final entry in labelPlan.layoutRequestsByAuthor.entries) {
    visibleByAuthor[entry.key] = [
      for (final id in entry.value)
        if (labelPlan.drawnRequestIds.contains(id)) id,
    ];
  }

  final requestAuthorById = {
    for (final request in composition.automatic.requests)
      request.id: request.authorId,
    for (final request in composition.anchorOverlay.pinnedRequests)
      request.id: request.authorId,
  };

  return (
    egoId: viewerId,
    paths: composition.paths,
    automaticKeptPeerIds: composition.keptPeerIds.difference({
      ...pinnedPersonIds,
      ...supportPersonIds,
    }),
    pinnedPersonIds: pinnedPersonIds,
    pinnedRequestIds: pinnedRequestIds,
    supportPersonIds: supportPersonIds,
    anchorByNodeId: {
      for (final entry in anchorByNodeId.entries)
        entry.key: entry.value.position,
    },
    priorHints: priorHints,
    nodeSizes: nodeSizes,
    satelliteRequestIdsByAuthor: visibleByAuthor,
    requestAuthorById: requestAuthorById,
    egoOwnRequestIds: labelPlan.egoOwnRequestIds,
    spacing: spacing,
    maxHops: 3,
    viewportClass: viewportClass,
  );
}
