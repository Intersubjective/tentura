part of '_migrations.dart';

/// Structural closure for the trust graph.
///
/// `mr_graph` ranks *who* to show and only ever returns the neighbourhood of the
/// current focus, so an edge between two already-visible nodes never arrives
/// until the user happens to focus one of its endpoints. `user_trust_edge` is a
/// plain table, so the structure between a known set of nodes can be answered
/// with pure SQL. Returns `graph_score` so the existing Hasura relationships and
/// select permissions apply unchanged.
final m0134 = Migration('0134', [
  r'''
CREATE OR REPLACE FUNCTION public.graph_edges_between(
  node_ids text[],
  positive_only boolean
) RETURNS SETOF public.graph_score
  LANGUAGE sql
  STABLE
  AS $$
SELECT
  e.subject AS src,
  e.object AS dst,
  (0)::double precision AS src_score,
  e.prev_sent_weight AS dst_score,
  public.user_trust_edge_degree(e.subject, positive_only) AS src_total_neighbor_count,
  public.user_trust_edge_degree(e.object, positive_only) AS dst_total_neighbor_count
FROM public.user_trust_edge e
WHERE e.subject = ANY(node_ids)
  AND e.object = ANY(node_ids)
  AND (positive_only = false OR e.prev_sent_weight > 0);
$$;
''',
]);
