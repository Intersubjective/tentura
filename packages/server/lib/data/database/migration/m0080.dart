part of '_migrations.dart';

/// Backfill activity-event item link + content snippet for rows created before m0079.
final m0080 = Migration('0080', [
  '''
UPDATE public.beacon_activity_event e
SET
  coordination_item_id = ci.id,
  diff = jsonb_strip_nulls(
    jsonb_build_object(
      'title', NULLIF(btrim(ci.title), ''),
      'body', NULLIF(btrim(ci.body), '')
    )
  )
FROM public.beacon_room_message m
JOIN public.coordination_item ci ON ci.id = m.linked_item_id
WHERE e.source_message_id = m.id
  AND m.linked_item_id IS NOT NULL
  AND (
    e.coordination_item_id IS NULL
    OR e.diff IS NULL
  );
''',
]);
