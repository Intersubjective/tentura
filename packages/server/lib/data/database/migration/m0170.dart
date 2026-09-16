part of '_migrations.dart';

/// Issue #146 T06: eligible membership view, access reasons/level, and Hasura
/// wrappers (phase 1: existing reasons only). The planned
/// `beacon(user_id)` index is omitted: m0160 already has one.
final m0170 = Migration('0170', [
  r'''
-- 1. Eligible membership: the ONLY definition of "member" used by context and bond.
CREATE OR REPLACE VIEW public.beacon_member AS
SELECT b.id AS beacon_id, b.user_id AS user_id
FROM public.beacon b
WHERE b.user_id IS NOT NULL
  AND b.status NOT IN (2, 3)
  AND b.published_at IS NOT NULL
UNION ALL
SELECT bs.beacon_id, bs.user_id
FROM public.beacon_steward bs
JOIN public.beacon b ON b.id = bs.beacon_id
WHERE b.status NOT IN (2, 3)
  AND b.published_at IS NOT NULL
  AND NOT public.block_hides(b.user_id, bs.user_id)
UNION ALL
SELECT bp.beacon_id, bp.user_id
FROM public.beacon_participant bp
JOIN public.beacon b ON b.id = bp.beacon_id
WHERE (bp.role = 1 OR bp.room_access = 3)
  AND b.status NOT IN (2, 3)
  AND b.published_at IS NOT NULL
  AND NOT public.block_hides(b.user_id, bp.user_id);
''',
  r'''
-- 2. Reason bitmask (phase 1: bits 0..5 only).
CREATE OR REPLACE FUNCTION public.beacon_access_reasons(
  p_beacon_id text,
  p_viewer_id text
) RETURNS integer
  LANGUAGE sql
  STABLE
  AS $$
SELECT COALESCE((
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
  END
  FROM public.beacon b
  WHERE b.id = p_beacon_id
), 0);
$$;
''',
  r'''
-- 3. Level derived from reasons.
CREATE OR REPLACE FUNCTION public.beacon_access_level(
  p_beacon_id text,
  p_viewer_id text
) RETURNS integer
  LANGUAGE sql
  STABLE
  AS $$
SELECT CASE
  WHEN r & 1 <> 0 THEN 0
  WHEN r & 6 <> 0 THEN 1
  WHEN r & 248 <> 0 THEN 2
  ELSE 3
END
FROM (SELECT public.beacon_access_reasons(p_beacon_id, p_viewer_id) AS r) s;
$$;
''',
  r'''
-- 4. Hasura wrappers (table + session arguments, same shape as beacon_get_can_read_linked_detail).
CREATE OR REPLACE FUNCTION public.beacon_get_access_level(
  beacon_row public.beacon, hasura_session json
) RETURNS integer LANGUAGE sql STABLE AS $$
SELECT public.beacon_access_level(beacon_row.id, (hasura_session ->> 'x-hasura-user-id')::text);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_get_access_reasons(
  beacon_row public.beacon, hasura_session json
) RETURNS integer LANGUAGE sql STABLE AS $$
SELECT public.beacon_access_reasons(beacon_row.id, (hasura_session ->> 'x-hasura-user-id')::text);
$$;
''',
]);
