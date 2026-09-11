typedef ConstellationEdgeRef = ({String src, String dst, int tier});

typedef ConstellationPathResolution = ({
  Map<String, int> depth,
  Map<String, int> derived,
  Map<String, String> parent,
  Map<String, int> parentTier,
  Set<String> attributed,
  Set<String> keep,
  Set<String> ring,
});

const _infinity = 1 << 30;

ConstellationPathResolution resolveConstellationPaths({
  required String egoId,
  required Set<String> visiblePeerIds,
  required Set<String> holderIds,
  required Iterable<ConstellationEdgeRef> edges,
  int maxHops = 3,
}) {
  final allowed = {egoId, ...visiblePeerIds};

  // [ALG-DEDUP] — tier 1 wins when both tiers share the same ordered pair.
  final deduped = <String, ConstellationEdgeRef>{};
  for (final edge in edges) {
    if (!allowed.contains(edge.src) || !allowed.contains(edge.dst)) {
      continue;
    }
    final key = '${edge.src}\0${edge.dst}';
    final existing = deduped[key];
    if (existing == null || edge.tier < existing.tier) {
      deduped[key] = edge;
    }
  }
  final filteredEdges = deduped.values.toList();

  final tier1Edges = <ConstellationEdgeRef>[];
  final allEdges = <ConstellationEdgeRef>[];
  for (final edge in filteredEdges) {
    allEdges.add(edge);
    if (edge.tier == 1) {
      tier1Edges.add(edge);
    }
  }

  // [ALG-STAGE1] — tier-1 BFS within the hop cap.
  final depth1 = <String, int>{egoId: 0};
  final tier1Adj = _buildAdjacency(tier1Edges);
  final queue = <String>[egoId];
  var head = 0;
  while (head < queue.length) {
    final node = queue[head++];
    final currentDepth = depth1[node]!;
    if (currentDepth >= maxHops) {
      continue;
    }
    for (final next in tier1Adj[node] ?? const <String>[]) {
      if (depth1.containsKey(next)) {
        continue;
      }
      depth1[next] = currentDepth + 1;
      queue.add(next);
    }
  }

  final t = depth1.keys.where((id) => id != egoId).toSet();

  final depth = <String, int>{};
  final derived = <String, int>{};
  final parent = <String, String>{};
  final parentTier = <String, int>{};

  for (final peer in t) {
    depth[peer] = depth1[peer]!;
    derived[peer] = 0;
  }

  for (final peer in t) {
    final targetDepth = depth1[peer]!;
    final predecessors = <String>[];
    for (final edge in tier1Edges) {
      if (edge.dst != peer) {
        continue;
      }
      final q = edge.src;
      final qDepth = q == egoId ? 0 : depth1[q];
      if (qDepth != null && qDepth == targetDepth - 1) {
        predecessors.add(q);
      }
    }
    predecessors.sort();
    final chosen = predecessors.first;
    parent[peer] = chosen;
    parentTier[peer] = 1;
  }

  // [ALG-STAGE2] — layered d2[p][h] table over both tiers.
  final nodes = {...allowed};
  final d2 = <String, List<int>>{};
  for (final node in nodes) {
    d2[node] = List<int>.filled(maxHops + 1, _infinity);
  }
  d2[egoId]![0] = 0;

  final allAdj = _buildAdjacency(allEdges);
  final edgeTier = <String, int>{};
  for (final edge in allEdges) {
    edgeTier['${edge.src}\0${edge.dst}'] = edge.tier;
  }

  for (var h = 1; h <= maxHops; h++) {
    for (final edge in allEdges) {
      final q = edge.src;
      final p = edge.dst;
      if (!nodes.contains(q) || !nodes.contains(p)) {
        continue;
      }

      final qInT = t.contains(q);
      if (qInT && depth1[q] != h - 1) {
        continue;
      }

      final previous = d2[q]![h - 1];
      if (previous >= _infinity) {
        continue;
      }

      final cost = edge.tier == 1 ? 0 : 1;
      final candidate = previous + cost;
      if (candidate < d2[p]![h]) {
        d2[p]![h] = candidate;
      }
    }
  }

  for (final peer in nodes) {
    if (peer == egoId || t.contains(peer)) {
      continue;
    }

    var bestH = -1;
    for (var h = 1; h <= maxHops; h++) {
      if (d2[peer]![h] < _infinity) {
        bestH = h;
        break;
      }
    }
    if (bestH < 0) {
      continue;
    }

    depth[peer] = bestH;
    derived[peer] = d2[peer]![bestH];

    // [ALG-PARENT] — guarded (tier, id) predecessor at depth(p) - 1.
    final targetDepth = bestH;
    final targetDerived = derived[peer]!;
    String? bestParent;
    var bestParentTier = 1 << 30;
    var bestParentId = '';

    for (final edge in allEdges) {
      if (edge.dst != peer) {
        continue;
      }
      final q = edge.src;
      if (!nodes.contains(q)) {
        continue;
      }

      final qDepthLayer = targetDepth - 1;
      if (d2[q]![qDepthLayer] >= _infinity) {
        continue;
      }

      if (t.contains(q) && depth1[q] != qDepthLayer) {
        continue;
      }

      final cost = edge.tier == 1 ? 0 : 1;
      if (d2[q]![qDepthLayer] + cost != targetDerived) {
        continue;
      }

      final tier = edge.tier;
      if (tier < bestParentTier || (tier == bestParentTier && q.compareTo(bestParentId) < 0)) {
        bestParentTier = tier;
        bestParentId = q;
        bestParent = q;
      }
    }

    if (bestParent != null) {
      parent[peer] = bestParent;
      parentTier[peer] = bestParentTier;
    }
  }

  final reached = depth.keys.toSet();

  // [ALG-PRUNE] — reached holders vs Steiner keep set.
  final attributed = holderIds.intersection(reached).difference({egoId});
  final keep = <String>{...attributed};
  for (final holder in attributed) {
    var current = holder;
    while (parent.containsKey(current)) {
      final ancestor = parent[current]!;
      if (ancestor == egoId) {
        break;
      }
      keep.add(ancestor);
      current = ancestor;
    }
  }

  // [ALG-EGO] — residual ring excludes ego.
  final ring = holderIds.difference(reached).difference({egoId});

  return (
    depth: depth,
    derived: derived,
    parent: parent,
    parentTier: parentTier,
    attributed: attributed,
    keep: keep,
    ring: ring,
  );
}

Map<String, List<String>> _buildAdjacency(Iterable<ConstellationEdgeRef> edges) {
  final adj = <String, List<String>>{};
  for (final edge in edges) {
    adj.putIfAbsent(edge.src, () => <String>[]).add(edge.dst);
  }
  return adj;
}

Set<ConstellationEdgeRef> constellationSupportEdges({
  required String egoId,
  required ConstellationPathResolution resolution,
  required Iterable<ConstellationEdgeRef> trustEdges,
}) {
  final nodes = {...resolution.keep, egoId};
  final deduped = <String, ConstellationEdgeRef>{};
  for (final edge in trustEdges) {
    if (!nodes.contains(edge.src) || !nodes.contains(edge.dst)) {
      continue;
    }
    if (edge.src != egoId &&
        edge.dst != egoId &&
        !resolution.keep.contains(edge.src) &&
        !resolution.keep.contains(edge.dst)) {
      continue;
    }
    final key = '${edge.src}\0${edge.dst}\0${edge.tier}';
    deduped[key] = edge;
  }
  final sorted = deduped.values.toList()
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
  return sorted.toSet();
}
