part of '_migrations.dart';

/// Request Questions for people who see a Request only through
/// discoverability (#526), corrected after m0299 (which stays as shipped):
///
/// * Their standing is the content wall's own discoverability reason
///   (`beacon_access_reasons` bit 32, the wall's decomposition kept in parity
///   with `beacon_can_read_content`), not a copy of it: they have Questions
///   only while the wall lets them read the Request (status 0, 7, 8), never
///   after Final check or closing. Recipients, forward edges and the other
///   standing sources keep read-only Questions after close as before.
/// * Cheap standing is decided first, so the mutual-visibility lookup (a
///   MeritRank peer set per person) runs only for someone with no other
///   standing; a forward recipient never pays for it.
/// * The audience list (`questions_audience`) and Questions unread share one
///   candidate list (`questionsAudienceCandidateIdsSql`): a discoverable
///   viewer joins it, and gets Questions unread, once they write there.
///   `request_unread_message_count` (m0289) is re-created to pick that up.
final m0300 = Migration('0300', [
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
  r'''
CREATE OR REPLACE FUNCTION public.questions_audience(p_beacon_id text)
RETURNS TABLE(user_id text, access smallint)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT l.user_id, l.access
FROM public.questions_access_levels(
  p_beacon_id,
  ARRAY(SELECT qa_b.user_id FROM public.beacon qa_b
WHERE qa_b.id = p_beacon_id AND qa_b.user_id IS NOT NULL
UNION
SELECT qa_bs.user_id FROM public.beacon_steward qa_bs
WHERE qa_bs.beacon_id = p_beacon_id
UNION
SELECT qa_bp.user_id FROM public.beacon_participant qa_bp
WHERE qa_bp.beacon_id = p_beacon_id
  AND (qa_bp.role IN (1, 6) OR qa_bp.room_access = 3)
UNION
SELECT qa_fe.recipient_id FROM public.beacon_forward_edge qa_fe
WHERE qa_fe.beacon_id = p_beacon_id AND qa_fe.cancelled_at IS NULL
UNION
SELECT qa_ho.user_id FROM public.beacon_help_offer qa_ho
WHERE qa_ho.beacon_id = p_beacon_id
UNION
SELECT qa_o.user_id FROM public.beacon_bud_observer qa_o
WHERE qa_o.beacon_id = p_beacon_id
UNION
SELECT qa_m.author_id FROM public.coordination_item qa_ci
JOIN public.beacon_room_message qa_m ON qa_m.thread_item_id = qa_ci.id
WHERE qa_ci.beacon_id = p_beacon_id AND qa_ci.kind = 7
  AND qa_m.author_id IS NOT NULL
)
) l
WHERE l.access > 0
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.request_unread_message_count(p_viewer text, p_beacon text)
RETURNS integer
LANGUAGE sql STABLE
SET search_path TO public, pg_temp
AS $$
SELECT (
  CASE WHEN public.beacon_effective_admission(p_beacon, p_viewer) THEN (
    SELECT count(*)::integer FROM public.beacon_room_message m
    LEFT JOIN public.beacon_room_seen seen
      ON seen.beacon_id = m.beacon_id AND seen.user_id = p_viewer
      AND seen.thread_item_id IS NULL
    WHERE m.beacon_id = p_beacon AND m.thread_item_id IS NULL
      AND m.author_id <> p_viewer
AND m.system_message_kind IS NULL
AND (m.semantic_marker IS NULL OR m.semantic_marker NOT IN
  (9, 18, 19))
AND (seen.last_seen_at IS NULL OR m.created_at > seen.last_seen_at)

  ) ELSE 0 END
  + COALESCE((
    SELECT q.unread_count
    FROM public.coordination_item ci
    CROSS JOIN LATERAL (
      SELECT count(*)::integer AS message_count,
  (CASE WHEN EXISTS (
  SELECT 1 FROM public.coordination_item qa_lobby
  WHERE qa_lobby.id = ci.id
    AND p_viewer IN (SELECT qa_b.user_id FROM public.beacon qa_b
WHERE qa_b.id = qa_lobby.beacon_id AND qa_b.user_id IS NOT NULL
UNION
SELECT qa_bs.user_id FROM public.beacon_steward qa_bs
WHERE qa_bs.beacon_id = qa_lobby.beacon_id
UNION
SELECT qa_bp.user_id FROM public.beacon_participant qa_bp
WHERE qa_bp.beacon_id = qa_lobby.beacon_id
  AND (qa_bp.role IN (1, 6) OR qa_bp.room_access = 3)
UNION
SELECT qa_fe.recipient_id FROM public.beacon_forward_edge qa_fe
WHERE qa_fe.beacon_id = qa_lobby.beacon_id AND qa_fe.cancelled_at IS NULL
UNION
SELECT qa_ho.user_id FROM public.beacon_help_offer qa_ho
WHERE qa_ho.beacon_id = qa_lobby.beacon_id
UNION
SELECT qa_o.user_id FROM public.beacon_bud_observer qa_o
WHERE qa_o.beacon_id = qa_lobby.beacon_id
UNION
SELECT qa_m.author_id FROM public.coordination_item qa_ci
JOIN public.beacon_room_message qa_m ON qa_m.thread_item_id = qa_ci.id
WHERE qa_ci.beacon_id = qa_lobby.beacon_id AND qa_ci.kind = 7
  AND qa_m.author_id IS NOT NULL
)
)
    THEN count(*) FILTER (WHERE m.author_id <> p_viewer
      AND m.system_message_kind IS NULL
      AND (s.last_seen_at IS NULL OR m.created_at > s.last_seen_at))
    ELSE 0
  END)::integer AS unread_count
FROM public.beacon_room_message m
LEFT JOIN public.beacon_room_seen s
  ON s.thread_item_id = m.thread_item_id AND s.user_id = p_viewer
  AND s.beacon_id = m.beacon_id
WHERE m.thread_item_id = ci.id
  AND (m.author_id IS NULL OR NOT public.block_hides(m.author_id, p_viewer))

    ) q
    WHERE ci.beacon_id = p_beacon AND ci.kind = 7
      AND EXISTS (
        SELECT 1 FROM public.questions_access_levels(
          ci.beacon_id, ARRAY[p_viewer]::text[]
        ) access WHERE access.access > 0
      )
  ), 0)
)

$$
''',
]);
