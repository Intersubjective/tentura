part of '_migrations.dart';

/// People who see a Request only through discoverability (#526, owner
/// decision 2026-11-08) have Questions standing like direct recipients: they
/// read and write before offering; a withdrawn or declined offer, a closed
/// Request, a ban or a block with the author narrow it as for recipients.
///
/// Discoverable standing is the content wall's discoverability clause
/// (`beacon_can_read_content`, m0242: discoverable, published, an author the
/// viewer is mutually visible with through the shared peer predicate
/// `person_are_mutually_visible_cached`) WITHOUT its open-family status
/// window: like a forward edge, it is standing that outlives closing, so a
/// closed Request leaves the viewer read-only instead of shut out. That one
/// case is also why the content gate below admits discoverable standing
/// directly (never on a deleted or draft Request, never across a block with
/// the author). Making the Request private ends it.
///
/// `questions_audience` (mentions, realtime hints via
/// `questions_hint_recipients`) does not enumerate everyone who could find
/// the Request: a discoverable viewer is a candidate once they have written
/// in Questions. Questions grants no discussion admission.
final m0299 = Migration('0299', [
  r'''
CREATE OR REPLACE FUNCTION public.questions_access_levels(p_beacon_id text, p_user_ids text[])
RETURNS TABLE(user_id text, access smallint)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
WITH b AS (
  SELECT beacon.id, beacon.user_id AS author_id, beacon.status,
    beacon.is_discoverable, beacon.published_at
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
    (
      b.is_discoverable
      AND b.published_at IS NOT NULL
      AND b.author_id IS NOT NULL
      AND b.status NOT IN (2, 3)
      AND NOT public.block_hides(b.author_id, c.user_id)
      AND public.person_are_mutually_visible_cached(c.user_id, b.author_id, '')
    ) AS discoverable,
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
    WHEN NOT (s.own_standing OR s.addressed OR s.discoverable OR s.past_offer
              OR s.rejected_forward) THEN 0
    WHEN s.banned AND NOT s.is_author THEN 0
    WHEN NOT (s.discoverable
              OR public.beacon_can_read_content(p_beacon_id, s.user_id)) THEN 0
    WHEN (s.own_standing
          OR ((s.addressed OR s.discoverable)
              AND NOT s.past_offer AND NOT s.rejected_forward))
      AND s.status NOT IN (1, 2, 6) THEN 2
    ELSE 1
  END)::smallint AS access
FROM standing s
$$
''',
  // Everyone with access > 0. The candidate set is the union of every
  // standing source above (kept next to the policy on purpose), except
  // discoverability: a discoverable viewer joins once they have written in
  // Questions, so nobody who merely can find the Request gets the fan-out.
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
    UNION
    SELECT m.author_id FROM public.coordination_item ci
    JOIN public.beacon_room_message m ON m.thread_item_id = ci.id
    WHERE ci.beacon_id = p_beacon_id AND ci.kind = 7
      AND m.author_id IS NOT NULL
  )
) l
WHERE l.access > 0
$$
''',
]);
