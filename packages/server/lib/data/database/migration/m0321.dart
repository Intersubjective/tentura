part of '_migrations.dart';

/// Post room notices and Hasura lineage respect the referenced Request's read boundary.
final m0321 = Migration('0321', [
  r'''
CREATE FUNCTION public.beacon_can_read_room_notice(
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
  // Hasura checks computed names against physical columns. Keep the public
  // field names for the viewer-aware projection.
  for (final edge in ['parent', 'root'])
    '''
ALTER TABLE public.beacon RENAME COLUMN lineage_${edge}_beacon_id
  TO stored_lineage_${edge}_beacon_id
''',
  for (final edge in ['parent', 'root'])
    '''
CREATE FUNCTION public.beacon_get_lineage_${edge}_beacon_id(
  beacon_row public.beacon, hasura_session json
) RETURNS text
LANGUAGE sql STABLE
AS \$\$
SELECT CASE WHEN public.beacon_can_read_content(
  beacon_row.stored_lineage_${edge}_beacon_id, hasura_session->>'x-hasura-user-id'
) THEN beacon_row.stored_lineage_${edge}_beacon_id END;
\$\$
''',
]);
