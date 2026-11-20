part of '_migrations.dart';

/// Undo m0323's change to `beacon_can_read_room_notice` and move the rule where
/// it belongs.
///
/// That function is the READ wall of Post closure notices too: it decides
/// whether the snapshot lookup shows an uninvited Post member the `budded`
/// notice (child id and title) or rewrites it to a plain close. Letting it
/// answer true for `budded` made the read path leak the continuation. Only the
/// realtime hint must reach every Post reader (it names nothing but the notice
/// message), so the exception lives in `realtime_room_notice_recipients`.
final m0324 = Migration('0324', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_can_read_room_notice(
  p_room_id text, p_kind integer, p_payload jsonb, p_viewer_id text
) RETURNS boolean
LANGUAGE sql STABLE
AS $$
SELECT CASE
  WHEN p_kind IS NULL OR p_kind NOT IN (1, 2, 5) THEN true
  WHEN p_kind = 5 AND p_payload->>'reason' IN ('expired', 'closedByAuthor') THEN true
  WHEN NOT EXISTS (
    SELECT 1 FROM public.beacon WHERE id = p_room_id AND kind = 1
  ) THEN true
  ELSE public.beacon_can_read_content(
    CASE WHEN p_kind = 1 THEN (
      SELECT source_beacon_id FROM public.beacon_hierarchy_events
      WHERE id = p_payload->>'eventId'
    ) ELSE p_payload->>'childBeaconId' END,
    p_viewer_id
  )
END;
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.realtime_room_notice_recipients(
  p_room_id text, p_kind smallint, p_payload jsonb, p_user_ids text[]
) RETURNS text[]
    LANGUAGE sql STABLE
    AS $$
SELECT CASE WHEN p_kind IS NULL THEN p_user_ids ELSE ARRAY(
  SELECT user_id FROM unnest(p_user_ids) AS user_id
  WHERE (p_kind = 5 AND p_payload->>'reason' = 'budded')
    OR public.beacon_can_read_room_notice(p_room_id, p_kind, p_payload, user_id)
) END
$$
''',
]);
