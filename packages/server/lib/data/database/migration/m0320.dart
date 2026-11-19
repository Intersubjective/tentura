part of '_migrations.dart';

/// Retire the Post observer snapshot cleared by m0319. Questions use the
/// same standing as on other Requests. A bud's hierarchy hints reach its
/// active forward recipients along with its author, stewards and participants.
final m0320 = Migration('0320', [
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
  r'''
CREATE OR REPLACE FUNCTION public.realtime_beacon_hierarchy_recipients(p_projection_owner_beacon_id text) RETURNS text[]
    LANGUAGE sql STABLE
    AS $$
WITH owner AS (
  SELECT b.user_id AS owner_id, b.parent_beacon_id, b.kind
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
    UNION ALL
    SELECT fe.recipient_id
    FROM public.beacon_forward_edge fe
    WHERE fe.beacon_id = p_projection_owner_beacon_id
      AND fe.cancelled_at IS NULL AND NOT fe.recipient_rejected
      AND o.kind = 0
      AND EXISTS (
        SELECT 1 FROM public.beacon parent
        WHERE parent.id = o.parent_beacon_id AND parent.kind = 1
      )
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
)
SELECT COALESCE(
  ARRAY(
    SELECT DISTINCT user_id
    FROM (
      SELECT user_id FROM direct_admission
      UNION ALL
      SELECT user_id FROM parent_linked
    ) recipients
    WHERE user_id IS NOT NULL AND user_id <> ''
    ORDER BY user_id
    LIMIT 2000
  ),
  ARRAY[]::text[]
);
$$
''',
  'DROP TABLE IF EXISTS public.beacon_bud_observer',
]);
