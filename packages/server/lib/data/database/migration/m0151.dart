part of '_migrations.dart';

/// Drop incoming-only MeritRank discovery from `person_visibility_peers`.
///
/// Incoming-only MeritRank is not a visibility signal here.
/// `mr_mutual_scores(viewer)` is ego-outbound, so a peer with only
/// peer→viewer MR (including mixed explicit trustOut + mrIn) is omitted.
/// We dropped `mr_edgelist` / per-peer `mr_node_score` discovery: first for
/// speed, second for simplicity. Mutual visibility remains explicit
/// `vote_user` and/or a `mr_mutual_scores` row (both directions in that
/// row). Mixed `trustIn + mrOut` is unchanged.
final m0151 = Migration('0151', [
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
all_peers AS (
  SELECT peer_id FROM trust_out
  UNION
  SELECT peer_id FROM trust_in
  UNION
  SELECT peer_id FROM mr_mutual_agg
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
    coalesce(mma.forward_mr, 0::double precision) AS forward_mr,
    coalesce(mma.reverse_mr, 0::double precision) AS reverse_mr
  FROM all_peers p
  LEFT JOIN mr_mutual_agg mma ON mma.peer_id = p.peer_id
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
]);
