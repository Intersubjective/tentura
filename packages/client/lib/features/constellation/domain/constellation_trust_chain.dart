import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart'
    show ConstellationEdgeRef;

/// Opacity of the people, items and labels off the selected person's trust
/// chain (#641).
const kConstellationTrustChainDimOpacity = 0.3;

/// Opacity factor of the edges off the selected person's trust chain (#641).
const kConstellationTrustChainEdgeFade = 0.25;

/// How a person on the field is reached from the viewer (#641).
sealed class ConstellationTrustChain {
  const ConstellationTrustChain();
}

/// The viewer trusts the person directly (or it is the viewer): no chain to
/// show.
final class ConstellationTrustChainDirect extends ConstellationTrustChain {
  const ConstellationTrustChainDirect();
}

/// The shortest chain of visible trust edges: [path] runs from the viewer to
/// the person, both included; [intermediaryIds] is the part in between.
final class ConstellationTrustChainFound extends ConstellationTrustChain {
  const ConstellationTrustChainFound(this.path, {this.derivedHops = const {}});

  final List<String> path;

  /// Hops of [path] that only a derived (tier 2) edge makes.
  final Set<(String, String)> derivedHops;

  List<String> get intermediaryIds =>
      path.length <= 2 ? const [] : path.sublist(1, path.length - 1);

  /// Consecutive `(src, dst)` hops along [path].
  Iterable<(String, String)> get hops sync* {
    for (var i = 0; i + 1 < path.length; i++) {
      yield (path[i], path[i + 1]);
    }
  }
}

/// No chain of visible trust edges reaches the person; nothing partial is
/// drawn.
final class ConstellationTrustChainNone extends ConstellationTrustChain {
  const ConstellationTrustChainNone();
}

/// Directed adjacency over the edges [from] may use: each ordered pair once,
/// with its lowest tier (an explicit edge wins over a derived one).
///
/// Only trust the viewer can see is ever passed in (field edges and anchor
/// support edges). A contact node without content ([contactOnlyIds], #246)
/// shows no trust of its own, so the only edge that touches one is the
/// viewer's own edge to it (`from → contact`): a chain may end at a contact
/// node, never pass through one.
Map<String, Map<String, int>> _adjacency({
  required String from,
  required Iterable<ConstellationEdgeRef> edges,
  required Set<String>? allowedNodeIds,
  required Set<String> contactOnlyIds,
}) {
  bool allowed(String id) =>
      id == from || allowedNodeIds == null || allowedNodeIds.contains(id);
  final adjacency = <String, Map<String, int>>{};
  for (final edge in edges) {
    if (edge.src == edge.dst || !allowed(edge.src) || !allowed(edge.dst)) {
      continue;
    }
    if (contactOnlyIds.contains(edge.src) ||
        (contactOnlyIds.contains(edge.dst) && edge.src != from)) {
      continue;
    }
    final out = adjacency.putIfAbsent(edge.src, () => <String, int>{});
    final existing = out[edge.dst];
    if (existing == null || edge.tier < existing) {
      out[edge.dst] = edge.tier;
    }
  }
  return adjacency;
}

/// Hop counts from [from] along directed trust edges (src trusts dst), over
/// the same edge rules as [constellationShortestTrustChain]. [from] is 0;
/// unreachable ids are absent.
Map<String, int> constellationTrustHops({
  required String from,
  required Iterable<ConstellationEdgeRef> edges,
  Set<String> contactOnlyIds = const {},
}) {
  final adjacency = _adjacency(
    from: from,
    edges: edges,
    allowedNodeIds: null,
    contactOnlyIds: contactOnlyIds,
  );
  final hops = <String, int>{from: 0};
  final queue = <String>[from];
  for (var head = 0; head < queue.length; head++) {
    final node = queue[head];
    final next = hops[node]! + 1;
    for (final neighbour in (adjacency[node] ?? const {}).keys) {
      if (hops.containsKey(neighbour)) continue;
      hops[neighbour] = next;
      queue.add(neighbour);
    }
  }
  return hops;
}

/// The shortest chain of trust edges from [from] (the viewer) to [to], both
/// included, or null when no chain exists (#641).
///
/// Edges are directed the way trust goes (`src` trusts `dst`), so the chain
/// reads "you trust A, A trusts B, B trusts them". Only [edges] whose ends are
/// both in [allowedNodeIds] (when given) are used, and contact nodes follow
/// the rule documented on [_adjacency].
///
/// Ties are settled deterministically: fewest hops first, then fewest derived
/// (tier 2) edges, then the chain whose ids are smallest position by
/// position. This is the trust graph's breadth-first search
/// (`GraphCubit._shortestPathInAllEdges`) made directed and stable.
List<String>? constellationShortestTrustChain({
  required String from,
  required String to,
  required Iterable<ConstellationEdgeRef> edges,
  Set<String>? allowedNodeIds,
  Set<String> contactOnlyIds = const {},
}) {
  if (from == to) {
    return [from];
  }
  if (allowedNodeIds != null && !allowedNodeIds.contains(to)) {
    return null;
  }
  final adjacency = _adjacency(
    from: from,
    edges: edges,
    allowedNodeIds: allowedNodeIds,
    contactOnlyIds: contactOnlyIds,
  );

  // Layer by layer, each node keeps its best chain so far: fewest derived
  // edges, then smallest ids. Every chain in one layer has the same length,
  // so they compare position by position.
  var layer = <String, ({int derived, List<String> path})>{
    from: (derived: 0, path: [from]),
  };
  final seen = <String>{from};
  while (layer.isNotEmpty) {
    final next = <String, ({int derived, List<String> path})>{};
    for (final entry in layer.entries) {
      final out = adjacency[entry.key];
      if (out == null) continue;
      for (final hop in out.entries) {
        if (seen.contains(hop.key)) continue;
        final candidate = (
          derived: entry.value.derived + (hop.value == 1 ? 0 : 1),
          path: [...entry.value.path, hop.key],
        );
        final best = next[hop.key];
        if (best == null || _better(candidate, best)) {
          next[hop.key] = candidate;
        }
      }
    }
    final found = next[to];
    if (found != null) {
      return found.path;
    }
    seen.addAll(next.keys);
    layer = next;
  }
  return null;
}

bool _better(
  ({int derived, List<String> path}) a,
  ({int derived, List<String> path}) b,
) {
  if (a.derived != b.derived) {
    return a.derived < b.derived;
  }
  for (var i = 0; i < a.path.length; i++) {
    final byId = a.path[i].compareTo(b.path[i]);
    if (byId != 0) {
      return byId < 0;
    }
  }
  return false;
}
