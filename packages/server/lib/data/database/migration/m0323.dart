part of '_migrations.dart';

/// A Post closed by budding must reach the realtime audience of a plain close.
///
/// The read path already shows a Post member who cannot read the bud the same
/// closed notice as a plain close (`closedByAuthor`). The realtime hint of the
/// `budded` notice used to follow the bud's read wall, so an uninvited member
/// received nothing for a budded close but a hint for a plain close, which
/// told them a continuation exists. The hint only names the notice message;
/// the snapshot lookup rewrites it for viewers who cannot read the bud.
final m0323 = Migration('0323', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_can_read_room_notice(
  p_room_id text, p_kind integer, p_payload jsonb, p_viewer_id text
) RETURNS boolean
LANGUAGE sql STABLE
AS $$
SELECT CASE
  WHEN p_kind IS NULL OR p_kind NOT IN (1, 2, 5) THEN true
  WHEN p_kind = 5 AND p_payload->>'reason' IN ('expired', 'closedByAuthor', 'budded') THEN true
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
]);
