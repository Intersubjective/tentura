part of '_migrations.dart';

/// Questions standing keeps the shared content wall as its authorization
/// policy. Evaluate its bounded grants before discoverability so stewards,
/// bud observers and addressees with hierarchy/snapshot access need no peer
/// set. The wall's blocks, terminal-state checks and grants are unchanged;
/// Questions still unions discoverability with the other standings.
/// Both function bodies are frozen here for deterministic migration replay.
/// `CREATE OR REPLACE` resets COST, so the wall's COST 1000 is re-applied.
final m0309 = Migration('0309', [
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
    -- Expensive discoverability is needed only without a bounded grant.
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
END;
$$
''',
  'ALTER FUNCTION public.beacon_can_read_content(text, text) COST 1000',
  r'''
CREATE OR REPLACE FUNCTION public.questions_access_levels(p_beacon_id text, p_user_ids text[])
RETURNS TABLE(user_id text, access smallint)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
WITH b AS (
  SELECT beacon.id, beacon.user_id AS author_id, beacon.status
  FROM public.beacon
  WHERE beacon.id = p_beacon_id AND beacon.kind = 0
),
cand AS (
  SELECT DISTINCT u AS user_id
  FROM unnest(COALESCE(p_user_ids, ARRAY[]::text[])) AS u
  WHERE u IS NOT NULL AND u <> ''
),
standing AS (
  SELECT
    c.user_id,
    b.status,
    c.user_id = b.author_id AS is_author,
    (
      c.user_id = b.author_id
      OR EXISTS (
        SELECT 1 FROM public.beacon_steward bs
        WHERE bs.beacon_id = b.id AND bs.user_id = c.user_id
      )
      OR EXISTS (
        SELECT 1 FROM public.beacon_participant bp
        WHERE bp.beacon_id = b.id AND bp.user_id = c.user_id
          AND (bp.role = 1 OR bp.room_access = 3)
      )
      OR EXISTS (
        SELECT 1 FROM public.beacon_help_offer ho
        WHERE ho.beacon_id = b.id AND ho.user_id = c.user_id
          AND ho.status = 0
      )
    ) AS own_standing,
    (
      EXISTS (
        SELECT 1 FROM public.beacon_forward_edge fe
        WHERE fe.beacon_id = b.id AND fe.recipient_id = c.user_id
          AND fe.cancelled_at IS NULL AND NOT fe.recipient_rejected
      )
      OR EXISTS (
        SELECT 1 FROM public.beacon_participant bp
        WHERE bp.beacon_id = b.id AND bp.user_id = c.user_id
          AND bp.role = 6
      )
      OR EXISTS (
        SELECT 1 FROM public.beacon_bud_observer o
        WHERE o.beacon_id = b.id AND o.user_id = c.user_id
      )
    ) AS addressed,
    EXISTS (
      SELECT 1 FROM public.beacon_help_offer ho
      WHERE ho.beacon_id = b.id AND ho.user_id = c.user_id
        AND ho.status <> 0
    ) AS past_offer,
    EXISTS (
      SELECT 1 FROM public.beacon_forward_edge fe
      WHERE fe.beacon_id = b.id AND fe.recipient_id = c.user_id
        AND fe.cancelled_at IS NULL AND fe.recipient_rejected
    ) AS rejected_forward,
    EXISTS (
      SELECT 1 FROM public.beacon_lobby_ban ban
      WHERE ban.beacon_id = b.id AND ban.user_id = c.user_id
    ) AS banned
  FROM cand c
  CROSS JOIN b
)
SELECT
  s.user_id,
  (CASE
    WHEN s.banned AND NOT s.is_author THEN 0
    WHEN s.own_standing OR s.addressed OR s.past_offer OR s.rejected_forward
      THEN CASE
        WHEN NOT public.beacon_can_read_content(p_beacon_id, s.user_id) THEN 0
        WHEN (s.own_standing
              OR (s.addressed AND NOT s.past_offer AND NOT s.rejected_forward))
          AND s.status NOT IN (1, 2, 6) THEN 2
        ELSE 1
      END
    -- No other standing: the wall's discoverability reason, which holds only
    -- on an open-family Request (status 0, 7, 8).
    WHEN (public.beacon_access_reasons(p_beacon_id, s.user_id) & 32) <> 0
      THEN 2
    ELSE 0
  END)::smallint AS access
FROM standing s
$$
''',
]);
