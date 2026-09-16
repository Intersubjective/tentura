part of '_migrations.dart';

/// Named right to list admitted helpers (author + room-admitted helpers)
/// for any content-capable viewer (level ≤ 2). Does not widen involvement.
final m0174 = Migration('0174', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_can_read_admitted_helpers(
  p_beacon_id text,
  p_viewer_id text
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT public.beacon_can_read_content(p_beacon_id, p_viewer_id);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_get_can_read_admitted_helpers(
  beacon_row public.beacon,
  hasura_session json
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT public.beacon_can_read_admitted_helpers(
  beacon_row.id,
  (hasura_session ->> 'x-hasura-user-id')::text
);
$$;
''',
  r'''
CREATE OR REPLACE VIEW public.beacon_admitted_helper AS
SELECT
  bp.beacon_id,
  bp.user_id
FROM public.beacon_participant bp
JOIN public.beacon b ON b.id = bp.beacon_id
WHERE bp.room_access = 3
  AND bp.user_id <> b.user_id
  AND NOT public.block_hides(b.user_id, bp.user_id);
''',
]);
