part of '_migrations.dart';

/// Phase 5.1: `beacon_blocker`, `beacon_activity_event`; FKs for room state + messages.
final m0040 = Migration('0040', [
  '''
CREATE TABLE IF NOT EXISTS public.beacon_blocker (
  id text NOT NULL PRIMARY KEY DEFAULT (
    concat('K', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12))
  ),
  beacon_id text NOT NULL
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE,
  title text NOT NULL,
  status smallint NOT NULL DEFAULT 0,
  visibility smallint NOT NULL DEFAULT 1,
  opened_by text NOT NULL
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  opened_from_message_id text NULL
    REFERENCES public.beacon_room_message(id) ON UPDATE CASCADE ON DELETE SET NULL,
  affected_participant_id text NULL
    REFERENCES public.beacon_participant(id) ON UPDATE CASCADE ON DELETE SET NULL,
  resolver_participant_id text NULL
    REFERENCES public.beacon_participant(id) ON UPDATE CASCADE ON DELETE SET NULL,
  resolved_by text NULL
    REFERENCES public."user"(id) ON DELETE SET NULL,
  resolved_from_message_id text NULL
    REFERENCES public.beacon_room_message(id) ON UPDATE CASCADE ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz NULL,
  CONSTRAINT beacon_blocker_visibility_chk CHECK (visibility IN (0, 1)),
  CONSTRAINT beacon_blocker_status_chk CHECK (status IN (0, 1, 2))
);
''',
  '''
CREATE INDEX IF NOT EXISTS beacon_blocker_beacon_created_idx
  ON public.beacon_blocker (beacon_id, created_at DESC);
''',
  '''
CREATE TABLE IF NOT EXISTS public.beacon_activity_event (
  id text NOT NULL PRIMARY KEY DEFAULT (
    concat('V', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12))
  ),
  beacon_id text NOT NULL
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE,
  visibility smallint NOT NULL,
  type smallint NOT NULL,
  actor_id text NULL
    REFERENCES public."user"(id) ON DELETE SET NULL,
  target_user_id text NULL
    REFERENCES public."user"(id) ON DELETE SET NULL,
  source_message_id text NULL
    REFERENCES public.beacon_room_message(id) ON DELETE SET NULL,
  diff jsonb NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
''',
  '''
CREATE INDEX IF NOT EXISTS beacon_activity_event_beacon_created_idx
  ON public.beacon_activity_event (beacon_id, created_at DESC);
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
ALTER TABLE public.beacon_room_state
  ADD CONSTRAINT beacon_room_state_open_blocker_fk
  FOREIGN KEY (open_blocker_id)
  REFERENCES public.beacon_blocker(id)
  ON UPDATE CASCADE ON DELETE SET NULL;
''',
  '''
ALTER TABLE public.beacon_room_message
  DROP CONSTRAINT IF EXISTS beacon_room_message_linked_blocker_fkey;
''',
  '''
ALTER TABLE public.beacon_room_message
  ADD CONSTRAINT beacon_room_message_linked_blocker_fkey
  FOREIGN KEY (linked_blocker_id)
  REFERENCES public.beacon_blocker(id)
  ON UPDATE CASCADE ON DELETE SET NULL;
''',
]);
