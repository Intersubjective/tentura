part of '_migrations.dart';

/// Trust graph readers follow the committed projection. prev_sent_weight is
/// publication bookkeeping and can still be positive after a profile untrust.
/// Filter stale user edges from MR neighbourhoods too, so reopening the graph
/// cannot merge a withdrawn edge back into its structural closure.
final m0272 = Migration('0272', [
  r'''
CREATE OR REPLACE FUNCTION public.user_trust_edge_degree(node_id text, positive_only boolean) RETURNS integer
    LANGUAGE sql STABLE
    AS $$
SELECT COUNT(DISTINCT
  CASE WHEN subject = node_id THEN object ELSE subject END
)::int
FROM public.user_trust_edge
WHERE (subject = node_id OR object = node_id)
  AND target_w <> 0
  AND (positive_only = false OR target_w > 0)
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.graph_edges_between(node_ids text[], positive_only boolean, hasura_session json) RETURNS SETOF public.graph_score
    LANGUAGE sql STABLE
    AS $$
SELECT
  e.subject AS src,
  e.object AS dst,
  (0)::double precision AS src_score,
  e.target_w AS dst_score,
  public.user_trust_edge_degree(e.subject, positive_only) AS src_total_neighbor_count,
  public.user_trust_edge_degree(e.object, positive_only) AS dst_total_neighbor_count
FROM public.user_trust_edge e
WHERE e.subject = ANY(node_ids)
  AND e.object = ANY(node_ids)
  AND e.target_w <> 0
  AND (positive_only = false OR e.target_w > 0)
  AND NOT public.block_hides(hasura_session ->> 'x-hasura-user-id', e.subject)
  AND NOT public.block_hides(hasura_session ->> 'x-hasura-user-id', e.object);
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.graph(focus text, context text, positive_only boolean, hasura_session json) RETURNS SETOF public.graph_score
    LANGUAGE sql STABLE
    AS $$
SELECT
  g.src,
  g.dst,
  g.score_cluster_of_ego AS src_score,
  g.score_cluster_of_dst AS dst_score,
  public.user_trust_edge_degree(g.src, positive_only) AS src_total_neighbor_count,
  public.user_trust_edge_degree(g.dst, positive_only) AS dst_total_neighbor_count
FROM
  mr_graph(
    hasura_session ->> 'x-hasura-user-id',
    focus,
    context,
    positive_only,
    0,
    100
  ) AS g
LEFT JOIN public."user" src_user ON src_user.id = g.src
LEFT JOIN public."user" dst_user ON dst_user.id = g.dst
LEFT JOIN public.user_trust_edge e ON e.subject = g.src AND e.object = g.dst
WHERE NOT public.block_hides(hasura_session ->> 'x-hasura-user-id', g.src)
  AND NOT public.block_hides(hasura_session ->> 'x-hasura-user-id', g.dst)
  AND (src_user.id IS NULL OR dst_user.id IS NULL OR (
    e.target_w <> 0 AND (positive_only = false OR e.target_w > 0)
  ));
$$
''',
]);
