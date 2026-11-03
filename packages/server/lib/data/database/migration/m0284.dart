part of '_migrations.dart';

/// Members of the parent Post of a budded Request have Questions standing
/// (#526). They read the Request through the bud snapshot
/// (`beacon_bud_observer`, m0239/m0242) even when nobody invited them by
/// hand, but `questions_access_levels` / `questions_audience` (m0254) never
/// consulted it, so the entry probe said canRead=false.
///
/// The snapshot row now counts as addressed standing (writes on an open
/// Request; a withdrawn offer, a closed Request, a ban or a block with the
/// author still narrow it) and its users are audience candidates.
/// `questions_hint_recipients` (m0255) follows through the audience.
/// Parent-Request participants and discovery readers gain nothing.
final m0284 = Migration('0284', [
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
    WHEN NOT (s.own_standing OR s.addressed OR s.past_offer
              OR s.rejected_forward) THEN 0
    WHEN s.banned AND NOT s.is_author THEN 0
    WHEN NOT public.beacon_can_read_content(p_beacon_id, s.user_id) THEN 0
    WHEN (s.own_standing
          OR (s.addressed AND NOT s.past_offer AND NOT s.rejected_forward))
      AND s.status NOT IN (1, 2, 6) THEN 2
    ELSE 1
  END)::smallint AS access
FROM standing s
$$
''',
  // Everyone with access > 0. The candidate set is the union of every
  // standing source above (kept next to the policy on purpose).
  r'''
CREATE OR REPLACE FUNCTION public.questions_audience(p_beacon_id text)
RETURNS TABLE(user_id text, access smallint)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT l.user_id, l.access
FROM public.questions_access_levels(
  p_beacon_id,
  ARRAY(
    SELECT b.user_id FROM public.beacon b
    WHERE b.id = p_beacon_id AND b.user_id IS NOT NULL
    UNION
    SELECT bs.user_id FROM public.beacon_steward bs
    WHERE bs.beacon_id = p_beacon_id
    UNION
    SELECT bp.user_id FROM public.beacon_participant bp
    WHERE bp.beacon_id = p_beacon_id
      AND (bp.role IN (1, 6) OR bp.room_access = 3)
    UNION
    SELECT fe.recipient_id FROM public.beacon_forward_edge fe
    WHERE fe.beacon_id = p_beacon_id AND fe.cancelled_at IS NULL
    UNION
    SELECT ho.user_id FROM public.beacon_help_offer ho
    WHERE ho.beacon_id = p_beacon_id
    UNION
    SELECT o.user_id FROM public.beacon_bud_observer o
    WHERE o.beacon_id = p_beacon_id
  )
) l
WHERE l.access > 0
$$
''',
]);
