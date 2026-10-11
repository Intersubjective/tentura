part of '_migrations.dart';

/// Budding B3 (Arch §3.2, I3, I4): the read wall around a Request budded from
/// a Post.
///
/// - contextChild (bit 64): when the immediate parent is a Post (`kind = 1`),
///   membership is the bud snapshot row `beacon_bud_observer(child, viewer)`,
///   not live Post membership. The Post must not be deleted or a draft
///   (status 2/3) and the Post author's block still hides it. Request parents
///   keep live membership (#146).
/// - contextAncestor (bit 128): the target must be a Request, so members of a
///   Post child never read the Post through it.
///
/// Bodies are copied from the latest definitions (`beacon_access_reasons` and
/// `beacon_can_read_content` from m0193, `beacon_readable_ids` from m0226)
/// with only these branches changed. `CREATE OR REPLACE` resets attributes it
/// does not restate, so m0227's COST 1000 on `beacon_can_read_content` is
/// re-applied; all three stay STABLE, none is SECURITY DEFINER or sets
/// search_path.
final m0242 = Migration('0242', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_access_reasons(p_beacon_id text, p_viewer_id text) RETURNS integer
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
RETURN COALESCE((
  SELECT CASE
    WHEN nullif(btrim(coalesce(p_viewer_id, '')), '') IS NULL THEN 0
    WHEN public.block_hides(b.user_id, p_viewer_id) THEN 0
    WHEN b.status = 3 THEN CASE WHEN b.user_id = p_viewer_id THEN 1 ELSE 0 END
    WHEN b.status = 2 THEN 0
    ELSE
        (CASE WHEN b.user_id = p_viewer_id THEN 1 ELSE 0 END)
      | (CASE WHEN EXISTS (
            SELECT 1 FROM public.beacon_steward bs
            WHERE bs.beacon_id = b.id AND bs.user_id = p_viewer_id
          ) OR EXISTS (
            SELECT 1 FROM public.beacon_participant bp
            WHERE bp.beacon_id = b.id AND bp.user_id = p_viewer_id AND bp.role = 1
          ) THEN 2 ELSE 0 END)
      | (CASE WHEN EXISTS (
            SELECT 1 FROM public.beacon_participant bp
            WHERE bp.beacon_id = b.id AND bp.user_id = p_viewer_id AND bp.room_access = 3
          ) THEN 4 ELSE 0 END)
      | (CASE WHEN EXISTS (
            SELECT 1 FROM public.beacon_forward_edge fe
            WHERE fe.beacon_id = b.id AND fe.recipient_id = p_viewer_id
              AND fe.cancelled_at IS NULL
          ) THEN 8 ELSE 0 END)
      | (CASE WHEN EXISTS (
            SELECT 1 FROM public.beacon_help_offer ho
            WHERE ho.beacon_id = b.id AND ho.user_id = p_viewer_id AND ho.status = 0
          ) THEN 16 ELSE 0 END)
      | (CASE WHEN b.is_discoverable
            AND b.status IN (0, 7, 8)
            AND b.published_at IS NOT NULL
            AND b.user_id IS NOT NULL
            AND public.person_are_mutually_visible_cached(p_viewer_id, b.user_id, '')
          THEN 32 ELSE 0 END)
      -- Same bounded beacon_member probes as beacon_can_read_content above.
      | (CASE WHEN b.parent_beacon_id IS NOT NULL AND b.published_at IS NOT NULL
            AND EXISTS (
                SELECT 1 FROM public.beacon member_beacon
                WHERE member_beacon.id = b.parent_beacon_id
                  AND member_beacon.kind = 0
                  AND member_beacon.status NOT IN (2, 3)
                  AND member_beacon.published_at IS NOT NULL
                  AND (
                    (member_beacon.user_id IS NOT NULL
                      AND member_beacon.user_id = p_viewer_id)
                    OR CASE WHEN
                      EXISTS (
                        SELECT 1 FROM public.beacon_steward bs
                        WHERE bs.beacon_id = member_beacon.id
                          AND bs.user_id = p_viewer_id
                      )
                      OR EXISTS (
                        SELECT 1 FROM public.beacon_participant bp
                        WHERE bp.beacon_id = member_beacon.id
                          AND bp.user_id = p_viewer_id
                          AND (bp.role = 1 OR bp.room_access = 3)
                      )
                      THEN NOT public.block_hides(member_beacon.user_id, p_viewer_id)
                      ELSE false
                    END
                  )
            )
          THEN 64
          -- contextChild under a Post: the bud snapshot, not live membership.
          WHEN b.parent_beacon_id IS NOT NULL AND b.published_at IS NOT NULL
            AND EXISTS (
                SELECT 1 FROM public.beacon parent
                WHERE parent.id = b.parent_beacon_id
                  AND parent.kind = 1
                  AND parent.status NOT IN (2, 3)
                  AND parent.published_at IS NOT NULL
                  AND EXISTS (
                    SELECT 1 FROM public.beacon_bud_observer o
                    WHERE o.beacon_id = b.id AND o.user_id = p_viewer_id
                  )
                  AND NOT public.block_hides(parent.user_id, p_viewer_id)
            )
          THEN 64 ELSE 0 END)
      -- contextAncestor never grants a Post.
      | (CASE WHEN b.published_at IS NOT NULL
            AND b.kind = 0
            AND EXISTS (
                SELECT 1 FROM public.beacon_ancestor a
                JOIN public.beacon member_beacon ON member_beacon.id = a.beacon_id
                WHERE a.ancestor_id = b.id
                  AND member_beacon.status NOT IN (2, 3)
                  AND member_beacon.published_at IS NOT NULL
                  AND (
                    (member_beacon.user_id IS NOT NULL
                      AND member_beacon.user_id = p_viewer_id)
                    OR CASE WHEN
                      EXISTS (
                        SELECT 1 FROM public.beacon_steward bs
                        WHERE bs.beacon_id = member_beacon.id
                          AND bs.user_id = p_viewer_id
                      )
                      OR EXISTS (
                        SELECT 1 FROM public.beacon_participant bp
                        WHERE bp.beacon_id = member_beacon.id
                          AND bp.user_id = p_viewer_id
                          AND (bp.role = 1 OR bp.room_access = 3)
                      )
                      THEN NOT public.block_hides(member_beacon.user_id, p_viewer_id)
                      ELSE false
                    END
                  )
            )
          THEN 128 ELSE 0 END)
  END
  FROM public.beacon b
  WHERE b.id = p_beacon_id
), 0);
END;
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_can_read_content(p_beacon_id text, p_viewer_id text) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
RETURN COALESCE((
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
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_steward bs
      WHERE bs.beacon_id = p_beacon_id AND bs.user_id = p_viewer_id
    ) THEN true
    -- These bounded probes mirror beacon_member in m0170 exactly. Keep both
    -- functions in sync with that canonical view: published, non-draft/deleted;
    -- author OR unblocked steward/participant (role = 1 OR room_access = 3).
    -- The view's author branch intentionally has no block_hides predicate.
    -- CASE checks blocks only for actual non-author members, not every descendant.
    -- contextChild: member of the immediate Request parent (D1)
    WHEN b.parent_beacon_id IS NOT NULL
      AND b.published_at IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.beacon member_beacon
        WHERE member_beacon.id = b.parent_beacon_id
          AND member_beacon.kind = 0
          AND member_beacon.status NOT IN (2, 3)
          AND member_beacon.published_at IS NOT NULL
          AND (
            (member_beacon.user_id IS NOT NULL
              AND member_beacon.user_id = p_viewer_id)
            OR CASE WHEN
              EXISTS (
                SELECT 1 FROM public.beacon_steward bs
                WHERE bs.beacon_id = member_beacon.id
                  AND bs.user_id = p_viewer_id
              )
              OR EXISTS (
                SELECT 1 FROM public.beacon_participant bp
                WHERE bp.beacon_id = member_beacon.id
                  AND bp.user_id = p_viewer_id
                  AND (bp.role = 1 OR bp.room_access = 3)
              )
              THEN NOT public.block_hides(member_beacon.user_id, p_viewer_id)
              ELSE false
            END
          )
      ) THEN true
    -- contextChild under a Post: the bud snapshot, not live membership (B3)
    WHEN b.parent_beacon_id IS NOT NULL
      AND b.published_at IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.beacon parent
        WHERE parent.id = b.parent_beacon_id
          AND parent.kind = 1
          AND parent.status NOT IN (2, 3)
          AND parent.published_at IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM public.beacon_bud_observer o
            WHERE o.beacon_id = b.id AND o.user_id = p_viewer_id
          )
          AND NOT public.block_hides(parent.user_id, p_viewer_id)
      ) THEN true
    -- contextAncestor: member of some descendant (D1); never a Post (B3)
    WHEN b.published_at IS NOT NULL
      AND b.kind = 0
      AND EXISTS (
        SELECT 1 FROM public.beacon_ancestor a
        JOIN public.beacon member_beacon ON member_beacon.id = a.beacon_id
        WHERE a.ancestor_id = b.id
          AND member_beacon.status NOT IN (2, 3)
          AND member_beacon.published_at IS NOT NULL
          AND (
            (member_beacon.user_id IS NOT NULL
              AND member_beacon.user_id = p_viewer_id)
            OR CASE WHEN
              EXISTS (
                SELECT 1 FROM public.beacon_steward bs
                WHERE bs.beacon_id = member_beacon.id
                  AND bs.user_id = p_viewer_id
              )
              OR EXISTS (
                SELECT 1 FROM public.beacon_participant bp
                WHERE bp.beacon_id = member_beacon.id
                  AND bp.user_id = p_viewer_id
                  AND (bp.role = 1 OR bp.room_access = 3)
              )
              THEN NOT public.block_hides(member_beacon.user_id, p_viewer_id)
              ELSE false
            END
          )
      ) THEN true
    ELSE false
  END
  FROM public.beacon b
  WHERE b.id = p_beacon_id
), false);
END;
$$
''',
  'ALTER FUNCTION public.beacon_can_read_content(text, text) COST 1000',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_readable_ids(p_viewer_id text, p_ids text[]) RETURNS SETOF text
    LANGUAGE sql STABLE
    AS $$
WITH cand AS (
  SELECT b.id, b.user_id, b.status, b.is_discoverable, b.published_at,
         b.parent_beacon_id, b.kind,
         parent.kind AS parent_kind, parent.user_id AS parent_user_id,
         parent.status AS parent_status,
         parent.published_at AS parent_published_at
  FROM public.beacon b
  LEFT JOIN public.beacon parent ON parent.id = b.parent_beacon_id
  WHERE b.id = ANY(p_ids)
),
-- Bud snapshot rows of the viewer on Post children (B3).
bud_obs AS (
  SELECT o.beacon_id FROM public.beacon_bud_observer o
  WHERE o.user_id = p_viewer_id AND o.beacon_id = ANY(p_ids)
),
blocked_author AS (
  SELECT a.user_id, public.block_hides(a.user_id, p_viewer_id) AS hidden
  FROM (SELECT DISTINCT user_id FROM cand) a
),
fwd AS (
  SELECT fe.beacon_id FROM public.beacon_forward_edge fe
  WHERE fe.recipient_id = p_viewer_id AND fe.cancelled_at IS NULL
    AND fe.beacon_id = ANY(p_ids)
),
part AS (
  SELECT bp.beacon_id FROM public.beacon_participant bp
  WHERE bp.user_id = p_viewer_id AND (bp.role = 1 OR bp.room_access = 3)
),
offer AS (
  SELECT ho.beacon_id FROM public.beacon_help_offer ho
  WHERE ho.user_id = p_viewer_id AND ho.status = 0
    AND ho.beacon_id = ANY(p_ids)
),
stew AS (
  SELECT bs.beacon_id FROM public.beacon_steward bs
  WHERE bs.user_id = p_viewer_id
),
-- Beacons the viewer is a member of (mirrors beacon_member, see m0193).
member AS (
  SELECT mb.id
  FROM public.beacon mb
  WHERE mb.user_id = p_viewer_id
    AND mb.status NOT IN (2, 3) AND mb.published_at IS NOT NULL
  UNION
  SELECT mb.id
  FROM public.beacon mb
  WHERE mb.id IN (SELECT beacon_id FROM stew UNION SELECT beacon_id FROM part)
    AND mb.status NOT IN (2, 3) AND mb.published_at IS NOT NULL
    AND NOT public.block_hides(mb.user_id, p_viewer_id)
),
member_ancestors AS (
  SELECT DISTINCT a.ancestor_id
  FROM public.beacon_ancestor a
  WHERE a.beacon_id IN (SELECT id FROM member)
),
peers AS MATERIALIZED (
  SELECT public.person_visible_peer_ids_tx(p_viewer_id, '') AS ids
  WHERE EXISTS (SELECT 1 FROM cand WHERE is_discoverable)
),
-- Mutual visibility once per distinct discoverable author, not per beacon.
mutual AS (
  SELECT a.user_id,
         public.person_reciprocal_explicit_trust(p_viewer_id, a.user_id)
           OR a.user_id = ANY(coalesce((SELECT ids FROM peers), '{}'::text[])) AS ok
  FROM (
    SELECT DISTINCT user_id FROM cand
    WHERE is_discoverable AND status IN (0, 7, 8)
      AND published_at IS NOT NULL AND user_id IS NOT NULL
      AND user_id <> p_viewer_id
  ) a
)
SELECT c.id
FROM cand c
JOIN blocked_author ba ON ba.user_id IS NOT DISTINCT FROM c.user_id
WHERE CASE
  WHEN ba.hidden THEN false
  WHEN c.status = 3 THEN c.user_id = p_viewer_id
  WHEN c.status = 2 THEN false
  WHEN c.user_id = p_viewer_id THEN true
  WHEN c.id IN (SELECT beacon_id FROM fwd) THEN true
  WHEN c.id IN (SELECT beacon_id FROM part) THEN true
  WHEN c.id IN (SELECT beacon_id FROM offer) THEN true
  WHEN c.is_discoverable
    AND c.status IN (0, 7, 8)
    AND c.published_at IS NOT NULL
    AND c.user_id IS NOT NULL
    AND c.user_id IN (SELECT user_id FROM mutual WHERE ok)
    THEN true
  WHEN c.id IN (SELECT beacon_id FROM stew) THEN true
  WHEN c.parent_beacon_id IS NOT NULL
    AND c.published_at IS NOT NULL
    AND c.parent_kind = 0
    AND c.parent_beacon_id IN (SELECT id FROM member) THEN true
  WHEN c.parent_beacon_id IS NOT NULL
    AND c.published_at IS NOT NULL
    AND c.parent_kind = 1
    AND c.parent_status NOT IN (2, 3)
    AND c.parent_published_at IS NOT NULL
    AND c.id IN (SELECT beacon_id FROM bud_obs)
    AND NOT public.block_hides(c.parent_user_id, p_viewer_id) THEN true
  WHEN c.published_at IS NOT NULL
    AND c.kind = 0
    AND c.id IN (SELECT ancestor_id FROM member_ancestors) THEN true
  ELSE false
END;
$$
''',
]);
