import 'constellation_anchor_composition.dart';
import 'constellation_trust_chain.dart';
import 'constellation_visibility.dart';
import 'entity/constellation_field.dart';

export 'constellation_trust_chain.dart';
export 'constellation_visibility.dart';

/// The selected person's chain of trust on the field (#641).
///
/// The chain uses only what the field shows: the people the composition puts
/// on the map and the trust edges the viewer may see between them (field
/// edges and anchor support paths), so every step can be drawn and named.
/// The viewer's own edge to a contact node without content counts (they are
/// a direct contact); no chain passes through such a node.
ConstellationTrustChain constellationTrustChainFor({
  required String viewerId,
  required String personId,
  required ConstellationField field,
  required ConstellationComposedPresentation composition,
}) {
  if (personId == viewerId) {
    return const ConstellationTrustChainDirect();
  }
  final edges = [
    ...constellationVisibleTrustEdges(field),
    for (final edge in composition.anchorOverlay.supportEdges)
      (src: edge.src, dst: edge.dst, tier: edge.tier),
  ];
  final isDirect =
      field.directContactIds.contains(personId) ||
      edges.any(
        (edge) =>
            edge.src == viewerId && edge.dst == personId && edge.tier == 1,
      );
  if (isDirect) {
    return const ConstellationTrustChainDirect();
  }
  final path = constellationShortestTrustChain(
    from: viewerId,
    to: personId,
    edges: edges,
    allowedNodeIds: composition.eligiblePersonIds,
    contactOnlyIds: constellationContactOnlyIds(field),
  );
  if (path == null) {
    return const ConstellationTrustChainNone();
  }
  final explicitHops = {
    for (final edge in edges)
      if (edge.tier == 1) (edge.src, edge.dst),
  };
  return ConstellationTrustChainFound(
    path,
    derivedHops: {
      for (var i = 0; i + 1 < path.length; i++)
        if (!explicitHops.contains((path[i], path[i + 1])))
          (path[i], path[i + 1]),
    },
  );
}

/// Memoises the field as [ConstellationVisibility] shows it and the selected
/// person's trust chain, so a rebuild does not recompute either.
final class ConstellationShownFieldMemo {
  ConstellationField? _source;
  String? _viewerId;
  ConstellationVisibility? _visibility;
  DateTime? _asOfUtc;
  late ConstellationField _shown;
  Set<String> _hiddenItemHolderIds = const {};

  /// Holders the last [shown] field keeps although their items are hidden
  /// by type (see [constellationHiddenItemHolderIds]).
  Set<String> get hiddenItemHolderIds => _hiddenItemHolderIds;

  ConstellationField shown(
    ConstellationField field, {
    required String viewerId,
    required ConstellationVisibility visibility,
    DateTime? asOfUtc,
  }) {
    if (!identical(field, _source) ||
        viewerId != _viewerId ||
        visibility != _visibility ||
        asOfUtc != _asOfUtc) {
      _source = field;
      _viewerId = viewerId;
      _visibility = visibility;
      _asOfUtc = asOfUtc;
      final degrees = visibility.hidesPeople
          ? constellationTrustDegrees(field: field, viewerId: viewerId)
          : null;
      _shown = constellationVisibleField(
        field: field,
        viewerId: viewerId,
        visibility: visibility,
        degrees: degrees,
      );
      _hiddenItemHolderIds = constellationHiddenItemHolderIds(
        field: field,
        viewerId: viewerId,
        visibility: visibility,
        asOfUtc: asOfUtc,
        degrees: degrees,
      );
    }
    return _shown;
  }

  ConstellationComposedPresentation? _chainComposition;
  ConstellationField? _chainField;
  String? _chainPersonId;
  late ConstellationTrustChain _chain;

  ConstellationTrustChain chain({
    required String viewerId,
    required String personId,
    required ConstellationField field,
    required ConstellationComposedPresentation composition,
  }) {
    if (!identical(composition, _chainComposition) ||
        !identical(field, _chainField) ||
        personId != _chainPersonId) {
      _chainComposition = composition;
      _chainField = field;
      _chainPersonId = personId;
      _chain = constellationTrustChainFor(
        viewerId: viewerId,
        personId: personId,
        field: field,
        composition: composition,
      );
    }
    return _chain;
  }
}
