import 'entity/constellation_field.dart';

/// Whom [personId] trusts both ways according to [field] alone: an explicit
/// (tier 1) edge each way. Derived (tier 2) links never count.
///
/// The field holds the explicit edges among its graph peers and the viewer
/// (and the anchors' support paths), so this answers at once for most
/// people; the edges of pinned and support peers are not all in it, which is
/// why the selection also asks the server (`ConstellationMutualTrustCase`).
///
/// The result is cached per field instance and person, so the build path
/// pays for it once per field.
Set<String> constellationFieldMutualTrustIds({
  required ConstellationField field,
  required String personId,
}) {
  final cached = _cache[field];
  if (cached != null && cached.$1 == personId) {
    return cached.$2;
  }
  final trusted = <String>{};
  final trustedBy = <String>{};
  for (final edge in [
    ...field.edges,
    ...field.resolvedAnchorProjection.supportEdges,
  ]) {
    if (edge.tier != 1 || edge.src == edge.dst) {
      continue;
    }
    if (edge.src == personId) {
      trusted.add(edge.dst);
    } else if (edge.dst == personId) {
      trustedBy.add(edge.src);
    }
  }
  final ids = Set<String>.unmodifiable(trusted.intersection(trustedBy));
  _cache[field] = (personId, ids);
  return ids;
}

final _cache = Expando<(String, Set<String>)>(
  'constellationFieldMutualTrustIds',
);
