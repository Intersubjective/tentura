part of '_migrations.dart';

/// Fixes [m0108]'s `user_trust_edge_degree`: it counted rows in
/// `user_trust_edge`, but mutual relationships store TWO directed rows
/// (subject/object swapped) for the same underlying neighbor, so a fully
/// mutual pair inflated the degree to 2 for what is really one hidden
/// neighbor. `mr_graph` can also surface those two directed rows for the
/// same pair from two different focus queries (one per direction), so the
/// client's hidden-neighbor badge for a node could change when a completely
/// different node was tapped, as soon as the "other" direction of an
/// already-mutual edge happened to be returned. Counting distinct neighbor
/// ids instead of rows fixes both: the total now matches the number of
/// distinct people, and it no longer moves once every direction of a known
/// neighbor has been loaded.
final m0109 = Migration('0109', [
  r'''
CREATE OR REPLACE FUNCTION public.user_trust_edge_degree(
  node_id text,
  positive_only boolean
) RETURNS integer
  LANGUAGE sql
  STABLE
  AS $$
SELECT COUNT(DISTINCT
  CASE WHEN subject = node_id THEN object ELSE subject END
)::int
FROM public.user_trust_edge
WHERE (subject = node_id OR object = node_id)
  AND (positive_only = false OR prev_sent_weight > 0)
$$;
''',
]);
