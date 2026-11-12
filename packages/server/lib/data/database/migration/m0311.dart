part of '_migrations.dart';

/// One access rule for beacon facts: `beacon_fact_access(beacon, user)`
/// returns one row, also for an unknown beacon id (`beacon_exists` false,
/// no access). `can_read` is the content wall; `can_use_room` adds a live
/// (non-deleted) beacon and room membership: author, steward or a participant
/// with `room_access = 3` (admitted). Stricter than `RoomAccessPolicy`: the
/// wall's `block_hides` applies to every kind, and a draft is author-only.
final m0311 = Migration('0311', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_fact_access(
  p_beacon_id text,
  p_user_id text
) RETURNS TABLE(
  beacon_exists boolean,
  kind integer,
  status integer,
  is_draft boolean,
  is_expired_post boolean,
  can_read boolean,
  can_use_room boolean
)
    LANGUAGE sql STABLE
    AS $$
WITH access AS (
  SELECT
    b.id IS NOT NULL AS beacon_exists,
    b.kind::integer AS kind,
    b.status::integer AS status,
    COALESCE(
      b.status = 3
        OR (b.kind = 1 AND b.status = 0 AND b.post_root_message_id IS NULL),
      false
    ) AS is_draft,
    COALESCE(
      b.kind = 1 AND b.status = 0
        AND b.expires_at IS NOT NULL AND b.expires_at <= now(),
      false
    ) AS is_expired_post,
    b.id IS NOT NULL
      AND public.beacon_can_read_content(p_beacon_id, p_user_id) AS can_read,
    b.status IS DISTINCT FROM 2
      AND (
        b.user_id = p_user_id
        OR EXISTS (
          SELECT 1 FROM public.beacon_steward s
          WHERE s.beacon_id = b.id AND s.user_id = p_user_id
        )
        OR EXISTS (
          SELECT 1 FROM public.beacon_participant p
          WHERE p.beacon_id = b.id
            AND p.user_id = p_user_id
            AND p.room_access = 3
        )
      ) AS is_room_member
  FROM (SELECT 1) AS one
  LEFT JOIN public.beacon b ON b.id = p_beacon_id
)
SELECT
  a.beacon_exists,
  a.kind,
  a.status,
  a.is_draft,
  a.is_expired_post,
  a.can_read,
  COALESCE(a.can_read AND a.is_room_member, false) AS can_use_room
FROM access a
$$;
''',
]);
