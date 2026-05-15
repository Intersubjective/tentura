part of '_migrations.dart';

/// Backfill coordination_item rows from legacy room semantics and link messages.
final m0065 = Migration('0065', [
  r'''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id,
  linked_message_id, created_at, updated_at
)
SELECT
  'CI' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 22),
  m.beacon_id,
  3,
  0,
  COALESCE(NULLIF(trim(bb.title), ''), 'Blocker'),
  '',
  m.author_id,
  m.id,
  m.created_at,
  m.created_at
FROM public.beacon_room_message m
JOIN public.beacon_blocker bb ON bb.id = m.linked_blocker_id
WHERE m.semantic_marker = 5
  AND m.linked_item_id IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.coordination_item ci
    WHERE ci.linked_message_id = m.id
  );
''',
  r'''
UPDATE public.beacon_room_message m
SET linked_item_id = ci.id,
    linked_event_kind = 1
FROM public.coordination_item ci
WHERE ci.linked_message_id = m.id
  AND m.linked_item_id IS NULL;
''',
  r'''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id, created_at, updated_at
)
SELECT
  'CI' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 22),
  rs.beacon_id,
  1,
  0,
  left(trim(rs.current_plan), 500),
  '',
  COALESCE(rs.updated_by, (SELECT author_id FROM public.beacon b WHERE b.id = rs.beacon_id LIMIT 1)),
  COALESCE(rs.updated_at, now()),
  COALESCE(rs.updated_at, now())
FROM public.beacon_room_state rs
WHERE trim(rs.current_plan) <> ''
  AND NOT EXISTS (
    SELECT 1 FROM public.coordination_item ci
    WHERE ci.beacon_id = rs.beacon_id
      AND ci.kind = 1
      AND ci.linked_parent_item_id IS NULL
      AND ci.status = 0
  );
''',
]);
