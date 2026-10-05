part of '_migrations.dart';

/// Mutual visibility without per-row MeritRank round-trips (#232).
///
/// `mr_mutual_scores(v)` lists `p` iff `S_v(p) > 0` (v's score of p) and
/// returns `S_p(v)` alongside it (meritrank-rust `read_mutual_scores`). With
/// explicit trust `T` from `vote_user`, the D14 OR-closure
/// `mutual_v(p) OR mutual_p(v)` that `person_are_mutually_visible` and
/// `person_visible_peers_symmetric` evaluated reduces to
///
///     (S_v(p) > 0 OR T(v,p)) AND (S_p(v) > 0 OR T(p,v))
///
/// so every mutually visible peer is either listed by `v` or trusted by `v`,
/// and only a one-way trusted, unlisted peer needs its own score of `v`
/// (one `mr_node_score`) instead of a full `person_visibility_peers(p)` per
/// non-mutual candidate.
///
/// `beacon_can_read_content` asked `person_are_mutually_visible_cached` once
/// per beacon row. In read-only transactions (Hasura queries, constellation
/// snapshots) the cache was bypassed, and each call recomputed the viewer's
/// peer list through MeritRank: 13–23 s for 225 beacons on dev. The viewer's
/// symmetric set is now computed once per transaction and memoized in a
/// transaction-local setting, which also works in read-only transactions.
/// The memo is keyed by viewer and context and carries the MR publish epoch
/// and the direct-trust version, so a trust write later in the same
/// transaction is not missed. MeritRank failures still fail closed: the
/// viewer sees nobody as mutually visible for that transaction.
final m0222 = Migration('0222', [
  r'''
CREATE OR REPLACE FUNCTION public.person_visible_peers_symmetric(viewer_id text, ctx text) RETURNS TABLE(peer_id text)
    LANGUAGE sql STABLE
    AS $$
WITH n AS (
  SELECT nullif(trim(coalesce(viewer_id, '')), '') AS v_id,
         coalesce(ctx, '')                          AS v_ctx
),
mr AS (
  SELECT
    CASE WHEN ms.src = n.v_id THEN ms.dst::text ELSE ms.src::text END AS peer_id,
    max(CASE WHEN ms.src = n.v_id THEN ms.score_value_of_dst
             ELSE ms.score_value_of_src END)::double precision AS fwd,
    max(CASE WHEN ms.src = n.v_id THEN ms.score_value_of_src
             ELSE ms.score_value_of_dst END)::double precision AS rev
  FROM n
  CROSS JOIN public.mr_mutual_scores(n.v_id, n.v_ctx) ms
  WHERE n.v_id IS NOT NULL
    AND (ms.src = n.v_id OR ms.dst = n.v_id)
    AND CASE WHEN ms.src = n.v_id THEN ms.dst::text ELSE ms.src::text END <> n.v_id
  GROUP BY 1
),
trust_out AS (
  SELECT vu.object AS peer_id
  FROM n
  INNER JOIN public.vote_user vu ON vu.subject = n.v_id AND vu.amount > 0
  WHERE vu.object <> n.v_id
),
trust_in AS (
  SELECT vu.subject AS peer_id
  FROM n
  INNER JOIN public.vote_user vu ON vu.object = n.v_id AND vu.amount > 0
  WHERE vu.subject <> n.v_id
),
-- (S_v(p) > 0 OR T(v,p))
candidates AS (
  SELECT mr.peer_id FROM mr WHERE mr.fwd > 0
  UNION
  SELECT trust_out.peer_id FROM trust_out
)
SELECT c.peer_id
FROM candidates c
CROSS JOIN n
LEFT JOIN mr m ON m.peer_id = c.peer_id
-- (S_p(v) > 0 OR T(p,v))
WHERE CASE
  WHEN m.rev > 0 THEN true
  WHEN EXISTS (SELECT 1 FROM trust_in t WHERE t.peer_id = c.peer_id) THEN true
  -- Listed by the viewer: S_p(v) came with the row and is not positive.
  WHEN m.peer_id IS NOT NULL THEN false
  -- One-way trusted and unlisted: ask MeritRank for p's score of v only.
  ELSE coalesce((
    SELECT ns.score_value_of_src > 0
    FROM public.mr_node_score(n.v_id, c.peer_id, n.v_ctx) ns
    LIMIT 1
  ), false)
END;
$$
''',
  r'''
CREATE FUNCTION public.person_visible_peer_ids_tx(viewer_id text, ctx text) RETURNS text[]
    LANGUAGE plpgsql
    AS $$
DECLARE
  _v text := nullif(trim(coalesce(viewer_id, '')), '');
  _ctx text := coalesce(ctx, '');
  _key text;
  _stamp text;
  _memo text;
  _ids text[];
BEGIN
  IF _v IS NULL THEN
    RETURN '{}'::text[];
  END IF;
  _key := 'tentura_visibility.p' || md5(_v || chr(31) || _ctx);
  _stamp := coalesce((SELECT epoch FROM public.mr_publish_epoch WHERE id = true), 0)
    || ':' || public.direct_trust_current_version() || ':';
  _memo := current_setting(_key, true);
  IF _memo IS NOT NULL AND starts_with(_memo, _stamp) THEN
    RETURN substr(_memo, length(_stamp) + 1)::text[];
  END IF;
  BEGIN
    SELECT coalesce(array_agg(s.peer_id ORDER BY s.peer_id), '{}'::text[])
    INTO _ids
    FROM public.person_visible_peers_symmetric(_v, _ctx) s;
  EXCEPTION WHEN OTHERS THEN
    -- MeritRank unavailable: fail closed for the rest of this transaction
    -- instead of retrying (and timing out) once per row.
    _ids := '{}'::text[];
  END;
  PERFORM set_config(_key, _stamp || _ids::text, true);
  RETURN _ids;
END;
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.person_are_mutually_visible(a_id text, b_id text, ctx text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
SELECT CASE
  WHEN nullif(trim(coalesce(a_id, '')), '') IS NULL THEN false
  WHEN nullif(trim(coalesce(b_id, '')), '') IS NULL THEN false
  WHEN a_id = b_id THEN false
  WHEN public.person_reciprocal_explicit_trust(a_id, b_id) THEN true
  ELSE b_id = ANY(public.person_visible_peer_ids_tx(a_id, coalesce(ctx, '')))
END;
$$
''',
  // Same contract as before (callers pass the viewer first); the cross-
  // transaction cache table is no longer read or written.
  r'''
CREATE OR REPLACE FUNCTION public.person_are_mutually_visible_cached(a_id text, b_id text, ctx text) RETURNS boolean
    LANGUAGE sql
    AS $$
SELECT public.person_are_mutually_visible(a_id, b_id, ctx);
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.constellation_trust_edges(p_viewer_id text, p_ctx text, node_ids text[]) RETURNS TABLE(src text, dst text, tier smallint)
    LANGUAGE sql STABLE
    AS $$
WITH viewer AS (
  SELECT nullif(trim(coalesce(p_viewer_id, '')), '') AS id, coalesce(p_ctx, '') AS ctx
),
visible AS (
  SELECT unnest(public.person_visible_peer_ids_tx(v.id, v.ctx)) AS id   -- D14, symmetric
  FROM viewer v
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
$$
''',
]);
