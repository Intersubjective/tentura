part of '_migrations.dart';

/// Repair 0162/0163 skipped when 0163a was registered ahead of them.
/// Keep these CREATE OR REPLACE bodies identical to the original migrations.
final m0169 = Migration('0169', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_can_read_content(
  p_beacon_id text,
  p_viewer_id text
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT COALESCE((
  SELECT CASE
    WHEN public.block_hides(b.user_id, p_viewer_id) THEN false
    WHEN b.status = 3 THEN b.user_id = p_viewer_id
    WHEN b.status = 2 THEN false
    WHEN b.user_id = p_viewer_id THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_forward_edge fe
      WHERE fe.beacon_id = p_beacon_id
        AND fe.recipient_id = p_viewer_id
        AND fe.cancelled_at IS NULL
    ) THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_participant bp
      WHERE bp.beacon_id = p_beacon_id
        AND bp.user_id = p_viewer_id
        AND (bp.role = 1 OR bp.room_access = 3)
    ) THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_help_offer ho
      WHERE ho.beacon_id = p_beacon_id
        AND ho.user_id = p_viewer_id
        AND ho.status = 0
    ) THEN true
    WHEN b.is_discoverable
      AND b.status IN (0, 7, 8)
      AND b.published_at IS NOT NULL
      AND b.user_id IS NOT NULL
      AND public.person_are_mutually_visible_cached(p_viewer_id, b.user_id, '')
      THEN true
    ELSE false
  END
  FROM public.beacon b
  WHERE b.id = p_beacon_id
), false);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.constellation_trust_edges(
  p_viewer_id text,
  p_ctx       text,
  node_ids    text[]
) RETURNS TABLE (src text, dst text, tier smallint)
  LANGUAGE sql STABLE AS $$
WITH viewer AS (
  SELECT nullif(trim(coalesce(p_viewer_id, '')), '') AS id, coalesce(p_ctx, '') AS ctx
),
visible AS (
  SELECT s.peer_id::text AS id
  FROM viewer v
  CROSS JOIN public.person_visible_peers_symmetric(v.id, v.ctx) s   -- D14, symmetric
  WHERE v.id IS NOT NULL
),
allowed AS (
  SELECT DISTINCT n AS id
  FROM viewer v
  CROSS JOIN unnest(node_ids) AS n
  WHERE v.id IS NOT NULL
    AND nullif(trim(coalesce(n, '')), '') IS NOT NULL
    AND (n = v.id OR n IN (SELECT id FROM visible))          -- D6
    AND NOT public.block_hides(v.id, n)      -- block_hides is symmetric (m0135)
),
t1 AS (
  SELECT vu.subject::text AS src, vu.object::text AS dst
  FROM public.vote_user vu
  INNER JOIN allowed a ON a.id = vu.subject
  INNER JOIN allowed b ON b.id = vu.object
  WHERE vu.amount > 0 AND vu.subject <> vu.object
    AND NOT public.block_hides(vu.subject, vu.object)   -- peer↔peer block, not just viewer
),
t2 AS (
  SELECT e.subject::text AS src, e.object::text AS dst
  FROM public.user_trust_edge e
  INNER JOIN allowed a ON a.id = e.subject
  INNER JOIN allowed b ON b.id = e.object
  WHERE e.prev_sent_weight > 0 AND e.subject <> e.object     -- positive_only, hard-coded
    AND NOT public.block_hides(e.subject, e.object)     -- peer↔peer block
)
SELECT t1.src, t1.dst, 1::smallint FROM t1
UNION ALL
SELECT t2.src, t2.dst, 2::smallint FROM t2
WHERE NOT EXISTS (SELECT 1 FROM t1 WHERE t1.src = t2.src AND t1.dst = t2.dst);
$$;
''',
]);
