import 'package:meta/meta.dart';

import 'constellation_cap_policy.dart';
import 'constellation_consts.dart';
import 'constellation_density.dart';
import 'constellation_filters.dart';
import 'constellation_path_resolution.dart';
import 'entity/constellation_anchor.dart';
import 'entity/constellation_anchor_projection.dart';
import 'entity/constellation_field.dart';

/// Viewport class for layout-hint eligibility (D33); not a UI token.
enum ConstellationViewportClass {
  compact,
  expanded,
}

ConstellationViewportClass constellationViewportClassForSize({
  required double width,
}) =>
    width < 840 ? ConstellationViewportClass.compact : ConstellationViewportClass.expanded;

@immutable
class ConstellationAutomaticLayer {
  const ConstellationAutomaticLayer({
    required this.peers,
    required this.requests,
    required this.edges,
    required this.peersCapped,
    required this.requestsCapped,
  });

  final List<ConstellationPerson> peers;
  final List<ConstellationRequest> requests;
  final List<ConstellationTrustEdgeEntity> edges;
  final bool peersCapped;
  final bool requestsCapped;
}

@immutable
class ConstellationAnchorOverlay {
  const ConstellationAnchorOverlay({
    required this.anchors,
    required this.pinnedPeers,
    required this.pinnedRequests,
    required this.supportPeers,
    required this.supportEdges,
    required this.serverFilteredPinnedBeaconIds,
  });

  final List<ConstellationAnchor> anchors;
  final List<ConstellationPerson> pinnedPeers;
  final List<ConstellationRequest> pinnedRequests;
  final List<ConstellationPerson> supportPeers;
  final List<ConstellationTrustEdgeEntity> supportEdges;
  final Set<String> serverFilteredPinnedBeaconIds;

  static const empty = ConstellationAnchorOverlay(
    anchors: [],
    pinnedPeers: [],
    pinnedRequests: [],
    supportPeers: [],
    supportEdges: [],
    serverFilteredPinnedBeaconIds: {},
  );
}

@immutable
class ConstellationLabelDisplayPlan {
  const ConstellationLabelDisplayPlan({
    required this.drawnRequestIds,
    required this.layoutRequestsByAuthor,
    required this.egoOwnRequestIds,
    required this.overflowHiddenCountByAuthor,
    required this.pinnedRequestIds,
    this.expandedExtraCountByAuthor = const {},
  });

  final Set<String> drawnRequestIds;
  final Map<String, List<String>> layoutRequestsByAuthor;
  final Set<String> egoOwnRequestIds;
  final Map<String, int> overflowHiddenCountByAuthor;
  final Set<String> pinnedRequestIds;
  final Map<String, int> expandedExtraCountByAuthor;
}

@immutable
class ConstellationComposedPresentation {
  const ConstellationComposedPresentation({
    required this.automatic,
    required this.anchorOverlay,
    required this.paths,
    required this.keptPeerIds,
    required this.droppedHolderIds,
    required this.renderBudgetCapped,
    required this.labelPlan,
    required this.eligiblePersonIds,
    required this.eligibleRequestIds,
    required this.locallyFilteredPinnedBeaconIds,
  });

  final ConstellationAutomaticLayer automatic;
  final ConstellationAnchorOverlay anchorOverlay;
  final ConstellationPathResolution paths;
  final Set<String> keptPeerIds;
  final Set<String> droppedHolderIds;
  final bool renderBudgetCapped;
  final ConstellationLabelDisplayPlan labelPlan;
  final Set<String> eligiblePersonIds;
  final Set<String> eligibleRequestIds;
  final Set<String> locallyFilteredPinnedBeaconIds;
}

ConstellationComposedPresentation composeConstellationPresentation({
  required String viewerId,
  required ConstellationField field,
  required ConstellationFilters localFilters,
  required DateTime asOfUtc,
  required ConstellationLabelBudget labelBudget,
  Set<String> expandedSatelliteAuthorIds = const {},
}) {
  final projection = field.resolvedAnchorProjection;
  final automatic = ConstellationAutomaticLayer(
    peers: field.peers,
    requests: field.requests,
    edges: field.edges,
    peersCapped: field.peersCapped,
    requestsCapped: field.requestsCapped,
  );

  final pinnedPeerIds = {
    for (final peer in projection.pinnedPeers) peer.id,
  };
  final pinnedRequestById = {
    for (final request in projection.pinnedRequests) request.id: request,
  };
  final pinnedRequestIds = pinnedRequestById.keys.toSet();

  final locallyFilteredPinnedBeaconIds = {
    for (final request in projection.pinnedRequests)
      if (!_requestMatchesLocalFilters(request, localFilters, asOfUtc))
        request.id,
  };

  final locallyVisiblePinnedRequestIds =
      pinnedRequestIds.difference(locallyFilteredPinnedBeaconIds);

  final anchorOverlay = _overlayForVisiblePins(
    projection: projection,
    viewerId: viewerId,
    pinnedPeerIds: pinnedPeerIds,
    locallyVisiblePinnedRequestIds: locallyVisiblePinnedRequestIds,
    automatic: automatic,
  );

  final budgetExemptPeerIds = {
    ...pinnedPeerIds,
    for (final peer in anchorOverlay.supportPeers) peer.id,
  };

  final holderIds = {
    viewerId,
    ...automatic.requests.map((request) => request.authorId),
    ...anchorOverlay.pinnedRequests.map((request) => request.authorId),
    ...pinnedPeerIds,
  };

  final mergedEdges = [
    ...automatic.edges.map(
      (edge) => (src: edge.src, dst: edge.dst, tier: edge.tier),
    ),
    ...anchorOverlay.supportEdges.map(
      (edge) => (src: edge.src, dst: edge.dst, tier: edge.tier),
    ),
  ];

  final visiblePeerIds = {
    ...automatic.peers.map((peer) => peer.id),
    ...pinnedPeerIds,
    for (final peer in anchorOverlay.supportPeers) peer.id,
  };

  final resolved = resolveAndCapConstellation(
    egoId: viewerId,
    visiblePeerIds: visiblePeerIds,
    holderIds: holderIds,
    edges: mergedEdges,
    cap: kConstellationRenderPeerCap,
    budgetExemptPeerIds: budgetExemptPeerIds,
  );

  final labelPlan = _buildLabelDisplayPlan(
    viewerId: viewerId,
    automatic: automatic,
    anchorOverlay: anchorOverlay,
    localFilters: localFilters,
    asOfUtc: asOfUtc,
    labelBudget: labelBudget,
    expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
    locallyFilteredPinnedBeaconIds: locallyFilteredPinnedBeaconIds,
  );

  final keptPeerIds = {
    ...resolved.keptPeerIds,
    ...pinnedPeerIds,
    for (final peer in anchorOverlay.supportPeers) peer.id,
  };

  final eligiblePersonIds = {
    viewerId,
    ...keptPeerIds,
  };

  final eligibleRequestIds = {
    ...labelPlan.drawnRequestIds,
    ...locallyVisiblePinnedRequestIds,
  };

  return ConstellationComposedPresentation(
    automatic: automatic,
    anchorOverlay: anchorOverlay,
    paths: resolved.paths,
    keptPeerIds: keptPeerIds,
    droppedHolderIds: resolved.droppedHolderIds,
    renderBudgetCapped: resolved.capped,
    labelPlan: labelPlan,
    eligiblePersonIds: eligiblePersonIds,
    eligibleRequestIds: eligibleRequestIds,
    locallyFilteredPinnedBeaconIds: locallyFilteredPinnedBeaconIds,
  );
}

ConstellationAnchorOverlay _overlayForVisiblePins({
  required ConstellationAnchorProjection projection,
  required String viewerId,
  required Set<String> pinnedPeerIds,
  required Set<String> locallyVisiblePinnedRequestIds,
  required ConstellationAutomaticLayer automatic,
}) {
  if (projection.anchors.isEmpty) {
    return ConstellationAnchorOverlay.empty;
  }

  final visiblePinnedRequests = [
    for (final request in projection.pinnedRequests)
      if (locallyVisiblePinnedRequestIds.contains(request.id)) request,
  ]..sort((a, b) => a.id.compareTo(b.id));

  final pathHolderIds = {
    ...pinnedPeerIds,
    for (final request in visiblePinnedRequests) request.authorId,
  };

  if (pathHolderIds.isEmpty) {
    return ConstellationAnchorOverlay(
      anchors: projection.anchors,
      pinnedPeers: projection.pinnedPeers,
      pinnedRequests: visiblePinnedRequests,
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredPinnedBeaconIds: projection.serverFilteredBeaconIds.toSet(),
    );
  }

  final mergedEdges = [
    ...automatic.edges.map(
      (edge) => (src: edge.src, dst: edge.dst, tier: edge.tier),
    ),
    ...projection.supportEdges.map(
      (edge) => (src: edge.src, dst: edge.dst, tier: edge.tier),
    ),
  ];

  final visiblePeerIds = {
    ...automatic.peers.map((peer) => peer.id),
    ...pinnedPeerIds,
    ...pathHolderIds,
    ...projection.supportPeers.map((peer) => peer.id),
    for (final edge in mergedEdges) edge.src,
    for (final edge in mergedEdges) edge.dst,
  };

  final resolution = resolveConstellationPaths(
    egoId: viewerId,
    visiblePeerIds: visiblePeerIds,
    holderIds: pathHolderIds,
    edges: mergedEdges,
  );

  final ringResidualPeerIds = resolution.ring.difference({
    viewerId,
    ...pinnedPeerIds,
  });

  final neededSupportPeerIds = {
    ...resolution.keep.difference({
      viewerId,
      ...pinnedPeerIds,
    }),
    ...ringResidualPeerIds,
  };

  final automaticPeerIds = automatic.peers.map((peer) => peer.id).toSet();
  final supportPeers = [
    for (final peer in projection.supportPeers)
      if (neededSupportPeerIds.contains(peer.id)) peer,
  ];

  final supportEdges = constellationSupportEdges(
    egoId: viewerId,
    resolution: resolution,
    trustEdges: mergedEdges,
  )
      .map(
        (edge) => ConstellationTrustEdgeEntity(
          src: edge.src,
          dst: edge.dst,
          tier: edge.tier,
        ),
      )
      .toList()
    ..sort((a, b) {
      final src = a.src.compareTo(b.src);
      if (src != 0) {
        return src;
      }
      final dst = a.dst.compareTo(b.dst);
      if (dst != 0) {
        return dst;
      }
      return a.tier.compareTo(b.tier);
    });

  // Do not prune automatic copies: support lists only overlay entities.
  for (final peer in projection.supportPeers) {
    if (neededSupportPeerIds.contains(peer.id) &&
        automaticPeerIds.contains(peer.id) &&
        !supportPeers.any((existing) => existing.id == peer.id)) {
      supportPeers.add(peer);
      supportPeers.sort((a, b) => a.id.compareTo(b.id));
    }
  }

  return ConstellationAnchorOverlay(
    anchors: projection.anchors,
    pinnedPeers: projection.pinnedPeers,
    pinnedRequests: visiblePinnedRequests,
    supportPeers: supportPeers,
    supportEdges: supportEdges,
    serverFilteredPinnedBeaconIds: projection.serverFilteredBeaconIds.toSet(),
  );
}

ConstellationLabelDisplayPlan _buildLabelDisplayPlan({
  required String viewerId,
  required ConstellationAutomaticLayer automatic,
  required ConstellationAnchorOverlay anchorOverlay,
  required ConstellationFilters localFilters,
  required DateTime asOfUtc,
  required ConstellationLabelBudget labelBudget,
  required Set<String> expandedSatelliteAuthorIds,
  required Set<String> locallyFilteredPinnedBeaconIds,
}) {
  final allByAuthor = <String, List<String>>{};
  for (final request in automatic.requests) {
    allByAuthor.putIfAbsent(request.authorId, () => <String>[]).add(request.id);
  }
  for (final request in anchorOverlay.pinnedRequests) {
    allByAuthor.putIfAbsent(request.authorId, () => <String>[]).add(request.id);
  }
  for (final entry in allByAuthor.entries) {
    entry.value.sort();
  }

  final filteredIds = filterRequestIds(
    requests: [
      ...automatic.requests,
      ...anchorOverlay.pinnedRequests,
    ].map(
      (request) => (
        id: request.id,
        needs: request.needs.toSet(),
        primaryNeedSlug: request.primaryNeedSlug,
        startAt: request.startAt,
        endAt: request.endAt,
        addressLabel: request.addressLabel,
        hasCoordinates: request.hasCoordinates,
      ),
    ),
    filters: localFilters,
    asOfUtc: asOfUtc,
  );

  final pinnedRequestIds = {
    for (final request in anchorOverlay.pinnedRequests) request.id,
  };

  final filteredByAuthor = <String, List<String>>{};
  for (final entry in allByAuthor.entries) {
    final ids = [
      for (final id in entry.value)
        if (filteredIds.contains(id) && !pinnedRequestIds.contains(id)) id,
    ];
    if (ids.isNotEmpty) {
      filteredByAuthor[entry.key] = ids;
    }
  }

  final allocated = allocateVisibleRequests(
    requestIdsByAuthor: filteredByAuthor,
    budget: labelBudget,
  );

  final drawn = <String>{...pinnedRequestIds};
  final overflow = <String, int>{};
  final expandedExtra = <String, int>{};

  for (final entry in filteredByAuthor.entries) {
    final authorId = entry.key;
    final automaticIds = entry.value;
    final visibleIds = List<String>.from(allocated[authorId] ?? const []);
    if (expandedSatelliteAuthorIds.contains(authorId)) {
      visibleIds
        ..clear()
        ..addAll(automaticIds);
      final allocatedCount = (allocated[authorId] ?? const []).length;
      final extra = automaticIds.length - allocatedCount;
      if (extra > 0) {
        expandedExtra[authorId] = extra;
      }
    }
    final hidden = automaticIds.length - visibleIds.length;
    if (hidden > 0) {
      overflow[authorId] = hidden;
    }
    drawn.addAll(visibleIds);
  }

  for (final request in anchorOverlay.pinnedRequests) {
    if (filteredIds.contains(request.id)) {
      drawn.add(request.id);
    }
  }

  return ConstellationLabelDisplayPlan(
    drawnRequestIds: drawn,
    layoutRequestsByAuthor: allByAuthor,
    egoOwnRequestIds: {
      for (final id in allByAuthor[viewerId] ?? const <String>[]) id,
    },
    overflowHiddenCountByAuthor: overflow,
    pinnedRequestIds: pinnedRequestIds,
    expandedExtraCountByAuthor: expandedExtra,
  );
}

bool _requestMatchesLocalFilters(
  ConstellationRequest request,
  ConstellationFilters filters,
  DateTime asOfUtc,
) {
  return filterRequestIds(
    requests: [
      (
        id: request.id,
        needs: request.needs.toSet(),
        primaryNeedSlug: request.primaryNeedSlug,
        startAt: request.startAt,
        endAt: request.endAt,
        addressLabel: request.addressLabel,
        hasCoordinates: request.hasCoordinates,
      ),
    ],
    filters: filters,
    asOfUtc: asOfUtc,
  ).contains(request.id);
}

Map<String, ConstellationAnchor> constellationAnchorsByNodeId(
  Iterable<ConstellationAnchor> anchors,
) {
  return {
    for (final anchor in anchors) anchor.target.graphNodeId: anchor,
  };
}
