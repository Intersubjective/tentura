part of '_migrations.dart';

/// Budding B4 (Arch §3.4, I11): `beacon_hierarchy` realtime recipients for a
/// Request budded from a Post.
///
/// When the projection owner's parent is a Post (`kind = 1`), the live
/// `parent_linked` audience is replaced by the owner's `beacon_bud_observer`
/// rows, minus users blocked with the owner author or the Post author, while
/// the Post is not deleted or a draft (status 2/3) — the same rule as the
/// read wall (m0242). Request parents are unchanged; emits owned by the Post
/// itself (it has no parent) are unchanged.
///
/// Former recipients still get revocation hints through the callers'
/// `p_extra_user_ids` (block path). The parent-deletion path passes none: an
/// accepted gap, former observers refetch and the read wall answers.
///
/// Body copied from the latest definition (m0193); it stays `LANGUAGE sql
/// STABLE` with the default COST, no SECURITY DEFINER and no search_path.
final m0243 = Migration('0243', [
  r'''
CREATE OR REPLACE FUNCTION public.realtime_beacon_hierarchy_recipients(p_projection_owner_beacon_id text) RETURNS text[]
    LANGUAGE sql STABLE
    AS $$
WITH owner AS (
  SELECT b.user_id AS owner_id, b.parent_beacon_id
  FROM public.beacon b
  WHERE b.id = p_projection_owner_beacon_id
),
direct_admission AS (
  SELECT q.user_id
  FROM owner o
  CROSS JOIN LATERAL (
    SELECT o.owner_id AS user_id
    WHERE o.owner_id IS NOT NULL AND o.owner_id <> ''
    UNION ALL
    SELECT bs.user_id
    FROM public.beacon_steward bs
    WHERE bs.beacon_id = p_projection_owner_beacon_id
    UNION ALL
    SELECT bp.user_id
    FROM public.beacon_participant bp
    WHERE bp.beacon_id = p_projection_owner_beacon_id
      AND (bp.role = 1 OR bp.room_access = 3)
  ) q
  WHERE NOT public.block_hides(o.owner_id, q.user_id)
),
parent_linked AS (
  SELECT q.user_id
  FROM owner o
  JOIN public.beacon parent ON parent.id = o.parent_beacon_id
  CROSS JOIN LATERAL (
    SELECT parent.user_id AS user_id
    WHERE parent.user_id IS NOT NULL AND parent.user_id <> ''
    UNION ALL
    SELECT bs.user_id
    FROM public.beacon_steward bs
    WHERE bs.beacon_id = parent.id
    UNION ALL
    SELECT bp.user_id
    FROM public.beacon_participant bp
    WHERE bp.beacon_id = parent.id
      AND (bp.role = 1 OR bp.room_access = 3)
  ) q
  WHERE o.parent_beacon_id IS NOT NULL
    AND parent.kind = 0
    AND parent.status NOT IN (2, 3)
    AND parent.published_at IS NOT NULL
    AND NOT public.block_hides(parent.user_id, q.user_id)
    AND NOT public.block_hides(o.owner_id, q.user_id)
),
-- Post parent: the owner's bud snapshot, never live Post membership (B4).
bud_observers AS (
  SELECT obs.user_id
  FROM owner o
  JOIN public.beacon parent ON parent.id = o.parent_beacon_id
  JOIN public.beacon_bud_observer obs
    ON obs.beacon_id = p_projection_owner_beacon_id
  WHERE parent.kind = 1
    AND parent.status NOT IN (2, 3)
    AND parent.published_at IS NOT NULL
    AND NOT public.block_hides(parent.user_id, obs.user_id)
    AND NOT public.block_hides(o.owner_id, obs.user_id)
)
SELECT COALESCE(
  ARRAY(
    SELECT DISTINCT user_id
    FROM (
      SELECT user_id FROM direct_admission
      UNION ALL
      SELECT user_id FROM parent_linked
      UNION ALL
      SELECT user_id FROM bud_observers
    ) recipients
    WHERE user_id IS NOT NULL AND user_id <> ''
    ORDER BY user_id
    LIMIT 2000
  ),
  ARRAY[]::text[]
);
$$
''',
]);
