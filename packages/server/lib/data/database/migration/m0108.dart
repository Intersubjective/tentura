part of '_migrations.dart';

final m0108 = Migration('0108', [
  r'''
CREATE OR REPLACE FUNCTION public.user_trust_edge_degree(
  node_id text,
  positive_only boolean
) RETURNS integer
  LANGUAGE sql
  STABLE
  AS $$
SELECT COUNT(*)::int
FROM public.user_trust_edge
WHERE (subject = node_id OR object = node_id)
  AND (positive_only = false OR prev_sent_weight > 0)
$$;
''',
  r'''
CREATE OR REPLACE VIEW public.graph_score AS
  SELECT
    ''::text AS src,
    ''::text AS dst,
    (0)::double precision AS src_score,
    (0)::double precision AS dst_score,
    (0)::integer AS src_total_neighbor_count,
    (0)::integer AS dst_total_neighbor_count
  WHERE false;
''',
  r'''
DROP FUNCTION IF EXISTS public.graph(text, text, boolean, json);
''',
  r'''
CREATE OR REPLACE FUNCTION public.graph(
  focus text,
  context text,
  positive_only boolean,
  hasura_session json
) RETURNS SETOF public.graph_score
  LANGUAGE sql
  STABLE
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
  ) AS g;
$$;
''',
]);
