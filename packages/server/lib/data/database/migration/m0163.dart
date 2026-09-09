part of '_migrations.dart';

/// Two-tier constellation edge source (Constellation D1/D6/§9.1).
final m0163 = Migration('0163', [
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
