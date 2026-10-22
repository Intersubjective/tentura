import 'entity/constellation_field.dart';

/// The viewer's trust relation to a person on the field (#643).
///
/// Only explicit trust marks count (tier-1 edges, as the friends list reads
/// them); the derived tier-2 links are drawn as edges but are not a mark
/// either person set.
enum ConstellationTrustBadge {
  /// Each has marked the other as someone they trust.
  mutual,

  /// The viewer trusts them; they have not marked the viewer.
  youTrust,

  /// They trust the viewer; the viewer has not marked them.
  theyTrust,

  /// A contact node without content (#246, Q5): the viewer trusts them, but
  /// they are outside the viewer's visible set, so the field holds only
  /// their identity and the viewer's own edge — never theirs.
  contactOnly,
}

/// The trust badge of every person on [field] who has one, by person id.
///
/// A contact node is always [ConstellationTrustBadge.contactOnly]: the
/// visibility wall withholds their edge to the viewer, so the field cannot
/// tell whether it is mutual. The viewer never has a badge.
///
/// The result is cached per field instance and viewer, so callers on the
/// build path pay for it once per field.
Map<String, ConstellationTrustBadge> constellationTrustBadges({
  required ConstellationField field,
  required String viewerId,
}) {
  final cached = _cache[field];
  if (cached != null && cached.$1 == viewerId) {
    return cached.$2;
  }
  final badges = _computeTrustBadges(field: field, viewerId: viewerId);
  _cache[field] = (viewerId, badges);
  return badges;
}

final _cache = Expando<(String, Map<String, ConstellationTrustBadge>)>(
  'constellationTrustBadges',
);

Map<String, ConstellationTrustBadge> _computeTrustBadges({
  required ConstellationField field,
  required String viewerId,
}) {
  if (viewerId.isEmpty) {
    return const {};
  }
  final projection = field.resolvedAnchorProjection;
  final outgoing = <String>{};
  final incoming = <String>{};
  for (final edge in [...field.edges, ...projection.supportEdges]) {
    if (edge.tier != 1 || edge.src == edge.dst) {
      continue;
    }
    if (edge.src == viewerId) {
      outgoing.add(edge.dst);
    } else if (edge.dst == viewerId) {
      incoming.add(edge.src);
    }
  }
  final contactOnly = <String>{
    for (final peer in [
      ...field.peers,
      ...projection.pinnedPeers,
      ...projection.supportPeers,
    ])
      if (peer.contactOnly && peer.id != viewerId) peer.id,
  };
  final badges = <String, ConstellationTrustBadge>{
    for (final id in {...outgoing, ...incoming})
      id: switch ((outgoing.contains(id), incoming.contains(id))) {
        (true, true) => ConstellationTrustBadge.mutual,
        (true, false) => ConstellationTrustBadge.youTrust,
        _ => ConstellationTrustBadge.theyTrust,
      },
    for (final id in contactOnly) id: ConstellationTrustBadge.contactOnly,
  };
  return Map.unmodifiable(badges);
}
