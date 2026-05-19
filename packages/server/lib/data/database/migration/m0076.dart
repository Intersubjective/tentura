part of '_migrations.dart';

/// Drop legacy `beacon_blocker` table; coordination_item is the sole blocker model.
final m0076 = Migration('0076', [
  '''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id,
  created_at, updated_at, published
)
SELECT
  bb.id,
  bb.beacon_id,
  3,
  CASE bb.status WHEN 0 THEN 0 WHEN 1 THEN 1 ELSE 2 END,
  COALESCE(NULLIF(trim(bb.title), ''), 'Blocker'),
  '',
  bb.opened_by,
  bb.created_at,
  COALESCE(bb.resolved_at, bb.created_at),
  true
FROM public.beacon_blocker bb
WHERE NOT EXISTS (
  SELECT 1 FROM public.coordination_item ci WHERE ci.id = bb.id
);
''',
  '''
UPDATE public.beacon_room_message m
SET linked_item_id = COALESCE(m.linked_item_id, m.linked_blocker_id),
    linked_event_kind = COALESCE(m.linked_event_kind, 1)
WHERE m.linked_blocker_id IS NOT NULL
  AND m.linked_item_id IS NULL;
''',
  '''
UPDATE public.beacon_room_state
SET open_blocker_id = NULL
WHERE open_blocker_id IS NOT NULL;
''',
  '''
ALTER TABLE public.beacon_room_state
  DROP CONSTRAINT IF EXISTS beacon_room_state_open_blocker_fk;
''',
  '''
ALTER TABLE public.beacon_room_message
  DROP CONSTRAINT IF EXISTS beacon_room_message_linked_blocker_fkey;
''',
  '''
ALTER TABLE public.beacon_room_message
  DROP COLUMN IF EXISTS linked_blocker_id;
''',
  '''
DROP TRIGGER IF EXISTS beacon_blocker_notify ON public.beacon_blocker;
''',
  '''
DROP TABLE IF EXISTS public.beacon_blocker CASCADE;
''',
]);
