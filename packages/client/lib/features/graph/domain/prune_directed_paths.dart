import 'dart:collection';

import 'entity/edge_directed.dart';

/// Vertices reachable from [start] following directed edges `src → dst`.
Set<String> forwardReachFrom(Set<EdgeDirected> edges, String start) {
  final out = <String>{start};
  final adj = <String, List<String>>{};
  for (final e in edges) {
    adj.putIfAbsent(e.src, () => <String>[]).add(e.dst);
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
/// in the same edge direction (`src → dst`).
Set<String> verticesThatCanReachFocus(Set<EdgeDirected> edges, String focus) {
  final out = <String>{focus};
  final rev = <String, List<String>>{};
  for (final e in edges) {
    rev.putIfAbsent(e.dst, () => <String>[]).add(e.src);
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

/// Returns only edges that lie on **at least one** directed path from
/// [root] to [focus] (inclusive of endpoints).
///
/// Uses the standard DAG trick: `v` lies on some `root → focus` path iff
/// `v` is reachable from [root] and can reach [focus]. An edge `(u, v)`
/// lies on such a path iff `u` is in the forward-reach set from [root] and
/// `v` is in the set of vertices that can reach [focus].
///
/// When there is no directed `root → focus` path (e.g. viewer is the
/// help offerer and [focus] is the author), retries with **swapped**
/// endpoints so the spine follows the real forward chain
/// `focus → … → root` in the underlying `sender → recipient` graph.
Set<EdgeDirected> edgesOnSomeDirectedPath({
  required Set<EdgeDirected> edges,
  required String root,
  required String focus,
}) {
  if (edges.isEmpty || root.isEmpty || focus.isEmpty) {
    return edges;
  }

  Set<EdgeDirected> pruneFor(String r, String f) {
    final s = forwardReachFrom(edges, r);
    final t = verticesThatCanReachFocus(edges, f);
    if (!s.contains(f)) {
      return <EdgeDirected>{};
    }
    return {
      for (final e in edges)
        if (s.contains(e.src) && t.contains(e.dst)) e,
    };
  }

  var result = pruneFor(root, focus);
  if (result.isEmpty && root != focus) {
    result = pruneFor(focus, root);
  }
  return result;
}
