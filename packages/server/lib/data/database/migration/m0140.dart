part of '_migrations.dart';

/// Canonical person visibility projection (issue #100 WU1).
///
/// Direction mapping for `mr_mutual_scores(viewer_id, coalesce(ctx, ''))` matches
/// `m0031.dart` / `merit_score_lookup.dart`:
///   src = viewer → score_value_of_dst = viewer→peer, score_value_of_src = peer→viewer
///   dst = viewer → score_value_of_src = viewer→peer, score_value_of_dst = peer→viewer
///
/// One-way MeritRank edges discovered via `mr_edgelist` use `mr_node_score` for
/// directional scores when `mr_mutual_scores` omits the peer row.
final m0140 = Migration('0140', [
  r'''
CREATE OR REPLACE FUNCTION public.person_visibility_peers(
  viewer_id text,
  ctx text
) RETURNS TABLE (
  peer_id text,
  viewer_explicitly_trusts_subject boolean,
  subject_explicitly_trusts_viewer boolean,
  forward_mr double precision,
  reverse_mr double precision,
  viewer_can_see_subject boolean,
  subject_can_see_viewer boolean,
  is_mutually_visible boolean
)
  LANGUAGE sql
  STABLE
  AS $$
WITH normalized AS (
  SELECT
    coalesce(nullif(trim(viewer_id), ''), '') AS v_id,
    coalesce(ctx, '') AS v_ctx
),
mr_rows AS (
  SELECT
    CASE WHEN ms.src = n.v_id THEN ms.dst::text ELSE ms.src::text END AS peer_id,
    CASE WHEN ms.src = n.v_id THEN ms.score_value_of_dst
         ELSE ms.score_value_of_src END::double precision AS fwd,
    CASE WHEN ms.src = n.v_id THEN ms.score_value_of_src
         ELSE ms.score_value_of_dst END::double precision AS rev
  FROM normalized n
  CROSS JOIN mr_mutual_scores(n.v_id, n.v_ctx) ms
  WHERE n.v_id <> ''
    AND (ms.src = n.v_id OR ms.dst = n.v_id)
    AND CASE WHEN ms.src = n.v_id THEN ms.dst::text ELSE ms.src::text END <> n.v_id
),
mr_mutual_agg AS (
  SELECT
    peer_id,
    coalesce(max(fwd), 0::double precision) AS forward_mr,
    coalesce(max(rev), 0::double precision) AS reverse_mr
  FROM mr_rows
  GROUP BY peer_id
),
trust_out AS (
  SELECT vu.object AS peer_id
  FROM normalized n
  INNER JOIN vote_user vu
    ON vu.subject = n.v_id
   AND vu.amount > 0
  WHERE n.v_id <> ''
    AND vu.object <> n.v_id
),
trust_in AS (
  SELECT vu.subject AS peer_id
  FROM normalized n
  INNER JOIN vote_user vu
    ON vu.object = n.v_id
   AND vu.amount > 0
  WHERE n.v_id <> ''
    AND vu.subject <> n.v_id
),
mr_edge_out AS (
  SELECT e.dst::text AS peer_id
  FROM normalized n
  INNER JOIN mr_edgelist(n.v_ctx) e
    ON e.src = n.v_id
   AND e.dst::text <> n.v_id
   AND e.weight > 0::double precision
  WHERE n.v_id <> ''
),
mr_edge_in AS (
  SELECT e.src::text AS peer_id
  FROM normalized n
  INNER JOIN mr_edgelist(n.v_ctx) e
    ON e.dst = n.v_id
   AND e.src::text <> n.v_id
   AND e.weight > 0::double precision
  WHERE n.v_id <> ''
),
all_peers AS (
  SELECT peer_id FROM trust_out
  UNION
  SELECT peer_id FROM trust_in
  UNION
  SELECT peer_id FROM mr_mutual_agg
  UNION
  SELECT peer_id FROM mr_edge_out
  UNION
  SELECT peer_id FROM mr_edge_in
),
node_mr AS (
  SELECT
    p.peer_id,
    coalesce(max(f.score_value_of_dst), 0::double precision) AS node_forward_mr,
    coalesce(max(r.score_value_of_dst), 0::double precision) AS node_reverse_mr
  FROM all_peers p
  CROSS JOIN normalized n
  LEFT JOIN LATERAL mr_node_score(n.v_id, p.peer_id, n.v_ctx) f ON n.v_id <> ''
  LEFT JOIN LATERAL mr_node_score(p.peer_id, n.v_id, n.v_ctx) r ON n.v_id <> ''
  WHERE n.v_id <> ''
  GROUP BY p.peer_id
),
peer_signals AS (
  SELECT
    p.peer_id,
    EXISTS (
      SELECT 1
      FROM normalized n
      INNER JOIN vote_user vu
        ON vu.subject = n.v_id
       AND vu.object = p.peer_id
       AND vu.amount > 0
      WHERE n.v_id <> ''
    ) AS viewer_explicitly_trusts_subject,
    EXISTS (
      SELECT 1
      FROM normalized n
      INNER JOIN vote_user vu
        ON vu.subject = p.peer_id
       AND vu.object = n.v_id
       AND vu.amount > 0
      WHERE n.v_id <> ''
    ) AS subject_explicitly_trusts_viewer,
    greatest(
      coalesce(mma.forward_mr, 0::double precision),
      coalesce(nm.node_forward_mr, 0::double precision)
    ) AS forward_mr,
    greatest(
      coalesce(mma.reverse_mr, 0::double precision),
      coalesce(nm.node_reverse_mr, 0::double precision)
    ) AS reverse_mr
  FROM all_peers p
  LEFT JOIN mr_mutual_agg mma ON mma.peer_id = p.peer_id
  LEFT JOIN node_mr nm ON nm.peer_id = p.peer_id
  WHERE EXISTS (SELECT 1 FROM normalized n WHERE n.v_id <> '')
)
SELECT
  s.peer_id,
  s.viewer_explicitly_trusts_subject,
  s.subject_explicitly_trusts_viewer,
  s.forward_mr,
  s.reverse_mr,
  (s.viewer_explicitly_trusts_subject OR s.forward_mr > 0::double precision)
    AS viewer_can_see_subject,
  (s.subject_explicitly_trusts_viewer OR s.reverse_mr > 0::double precision)
    AS subject_can_see_viewer,
  (
    (s.viewer_explicitly_trusts_subject OR s.forward_mr > 0::double precision)
    AND (s.subject_explicitly_trusts_viewer OR s.reverse_mr > 0::double precision)
  ) AS is_mutually_visible
FROM peer_signals s;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.person_is_mutually_visible(
  viewer_id text,
  peer_id text,
  ctx text
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT coalesce(
  (
    SELECT p.is_mutually_visible
    FROM public.person_visibility_peers(viewer_id, ctx) p
    WHERE p.peer_id = person_is_mutually_visible.peer_id
  ),
  false
);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.user_get_trusts_viewer(
  user_row public."user",
  hasura_session json
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT EXISTS (
  SELECT 1
  FROM vote_user vu
  WHERE vu.subject = user_row.id
    AND vu.object = (hasura_session ->> 'x-hasura-user-id')::text
    AND vu.amount > 0
    AND nullif(trim(hasura_session ->> 'x-hasura-user-id'), '') IS NOT NULL
);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.mutually_visible_users(
  context text,
  hasura_session json
) RETURNS SETOF public."user"
  LANGUAGE sql
  STABLE
  AS $$
SELECT u.*
FROM public."user" u
INNER JOIN public.person_visibility_peers(
  hasura_session ->> 'x-hasura-user-id',
  context
) p ON u.id = p.peer_id
WHERE nullif(trim(hasura_session ->> 'x-hasura-user-id'), '') IS NOT NULL
  AND u.id <> (hasura_session ->> 'x-hasura-user-id')
  AND p.is_mutually_visible
  AND NOT public.block_hides(
    hasura_session ->> 'x-hasura-user-id',
    u.id
  );
$$;
''',
]);
