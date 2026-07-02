import 'dart:collection';

import 'entity/edge_directed.dart';

/// Vertices reachable from [start] following directed pairs `$1 → $2`.
Set<String> forwardReachFromPairs(
  Iterable<(String, String)> pairs,
  String start,
) {
  final out = <String>{start};
  final adj = <String, List<String>>{};
  for (final (src, dst) in pairs) {
    adj.putIfAbsent(src, () => <String>[]).add(dst);
  }
  final q = Queue<String>()..add(start);
  while (q.isNotEmpty) {
    final u = q.removeFirst();
    for (final v in adj[u] ?? const <String>[]) {
      if (out.add(v)) {
        q.add(v);
      }
    }
  }
  return out;
}

/// Vertices `v` for which there exists a directed path `v → … → focus`
/// in the same pair direction (`$1 → $2`).
Set<String> verticesThatCanReachFocusPairs(
  Iterable<(String, String)> pairs,
  String focus,
) {
  final out = <String>{focus};
  final rev = <String, List<String>>{};
  for (final (src, dst) in pairs) {
    rev.putIfAbsent(dst, () => <String>[]).add(src);
  }
  final q = Queue<String>()..add(focus);
  while (q.isNotEmpty) {
    final v = q.removeFirst();
    for (final u in rev[v] ?? const <String>[]) {
      if (out.add(u)) {
        q.add(u);
      }
    }
  }
  return out;
}

/// Returns only endpoint pairs that lie on **at least one** directed path
/// from [root] to [focus] (inclusive of endpoints).
///
/// Uses the standard DAG trick: `v` lies on some `root → focus` path iff
/// `v` is reachable from [root] and can reach [focus]. A pair `(u, v)`
/// lies on such a path iff `u` is in the forward-reach set from [root] and
/// `v` is in the set of vertices that can reach [focus].
///
/// When there is no directed `root → focus` path (e.g. viewer is the
/// help offerer and [focus] is the author, or someone trusts ego without
/// ego trusting them back), retries with **swapped** endpoints so the spine
/// follows the real forward chain `focus → … → root`.
Set<(String, String)> edgePairsOnSomeDirectedPath({
  required Set<(String, String)> pairs,
  required String root,
  required String focus,
}) {
  if (pairs.isEmpty || root.isEmpty || focus.isEmpty) {
    return pairs;
  }

  Set<(String, String)> pruneFor(String r, String f) {
    final s = forwardReachFromPairs(pairs, r);
    if (!s.contains(f)) {
      return const <(String, String)>{};
    }
    final t = verticesThatCanReachFocusPairs(pairs, f);
    return {
      for (final p in pairs)
        if (s.contains(p.$1) && t.contains(p.$2)) p,
    };
  }

  var result = pruneFor(root, focus);
  if (result.isEmpty && root != focus) {
    result = pruneFor(focus, root);
  }
  return result;
}

/// Vertices reachable from [start] following directed edges `src → dst`.
Set<String> forwardReachFrom(Set<EdgeDirected> edges, String start) =>
    forwardReachFromPairs([for (final e in edges) (e.src, e.dst)], start);

/// Vertices `v` for which there exists a directed path `v → … → focus`
/// in the same edge direction (`src → dst`).
Set<String> verticesThatCanReachFocus(Set<EdgeDirected> edges, String focus) =>
    verticesThatCanReachFocusPairs(
      [for (final e in edges) (e.src, e.dst)],
      focus,
    );

/// [EdgeDirected] wrapper around [edgePairsOnSomeDirectedPath], including
/// its swapped-endpoints fallback.
Set<EdgeDirected> edgesOnSomeDirectedPath({
  required Set<EdgeDirected> edges,
  required String root,
  required String focus,
}) {
  if (edges.isEmpty || root.isEmpty || focus.isEmpty) {
    return edges;
  }
  final keep = edgePairsOnSomeDirectedPath(
    pairs: {for (final e in edges) (e.src, e.dst)},
    root: root,
    focus: focus,
  );
  return {
    for (final e in edges)
      if (keep.contains((e.src, e.dst))) e,
  };
}
