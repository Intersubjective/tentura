part of '_migrations.dart';

/// Beacon Room: participants, steward, room state, messages, reactions,
/// attachments; seed author participants; migrate active commitments;
/// extend `notify_entity_change` for `room_message` and `participant`.
final m0036 = Migration('0036', [
  '''
CREATE TABLE IF NOT EXISTS public.beacon_steward (
  beacon_id text NOT NULL
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE,
  user_id text NOT NULL
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  PRIMARY KEY (beacon_id)
);
''',
  '''
CREATE TABLE IF NOT EXISTS public.beacon_participant (
  id text DEFAULT concat('P', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)) NOT NULL,
  beacon_id text NOT NULL
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE,
  user_id text NOT NULL
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  role smallint NOT NULL DEFAULT 2,
  status smallint NOT NULL DEFAULT 0,
  room_access smallint NOT NULL DEFAULT 0,
  next_move_text text NULL,
  next_move_status smallint NULL,
  next_move_source smallint NULL,
  linked_message_id text NULL,
  offer_note text NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT beacon_participant_unique_pair UNIQUE (beacon_id, user_id)
);
''',
  '''
CREATE INDEX IF NOT EXISTS beacon_participant_beacon_room_idx
  ON public.beacon_participant (beacon_id, room_access);
''',
  '''
CREATE TABLE IF NOT EXISTS public.beacon_room_state (
  beacon_id text NOT NULL
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE,
  current_plan text NOT NULL DEFAULT '',
  open_blocker_id text NULL,
  last_room_meaningful_change text NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_by text NULL
    REFERENCES public."user"(id) ON UPDATE SET NULL ON DELETE SET NULL,
  PRIMARY KEY (beacon_id)
);
''',
  '''
CREATE TABLE IF NOT EXISTS public.beacon_room_message (
  id text DEFAULT concat('R', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)) NOT NULL,
  beacon_id text NOT NULL
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE,
  author_id text NOT NULL
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  body text NOT NULL DEFAULT '',
  reply_to_message_id text NULL,
  linked_blocker_id text NULL,
  linked_next_move_id text NULL,
  linked_fact_card_id text NULL,
  semantic_marker smallint NULL,
  system_payload jsonb NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT beacon_room_msg_reply_self_fk FOREIGN KEY (reply_to_message_id)
    REFERENCES public.beacon_room_message(id) ON DELETE SET NULL
);
''',
  '''
CREATE INDEX IF NOT EXISTS beacon_room_message_beacon_created_idx
  ON public.beacon_room_message (beacon_id, created_at DESC);
''',
  '''
CREATE TABLE IF NOT EXISTS public.beacon_room_message_reaction (
  id text DEFAULT concat('E', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)) NOT NULL,
  message_id text NOT NULL
    REFERENCES public.beacon_room_message(id) ON UPDATE CASCADE ON DELETE CASCADE,
  user_id text NOT NULL
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  emoji text NOT NULL CHECK (length(emoji) <= 32),
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT beacon_room_reaction_unique UNIQUE (message_id, user_id, emoji)
);
''',
  '''
CREATE TABLE IF NOT EXISTS public.beacon_room_message_attachment (
  id text DEFAULT concat('A', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)) NOT NULL,
  message_id text NOT NULL
    REFERENCES public.beacon_room_message(id) ON UPDATE CASCADE ON DELETE CASCADE,
  kind smallint NOT NULL,
  image_id uuid NULL
    REFERENCES public.image(id) ON DELETE SET NULL,
  file_url text NULL,
  mime text NOT NULL DEFAULT 'application/octet-stream',
  size_bytes bigint NOT NULL DEFAULT 0,
  width int NULL,
  height int NULL,
  position smallint NOT NULL DEFAULT 0,
  PRIMARY KEY (id)
);
''',
  // Fix defaults when this migration is retried after a failed run: IF NOT EXISTS
  // skipped CREATE with the old broken `substring(uuid::text, '\\w{12}')` form.
  '''
ALTER TABLE public.beacon_participant
  ALTER COLUMN id SET DEFAULT concat(
    'P', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)
  );
''',
  '''
ALTER TABLE public.beacon_room_message
  ALTER COLUMN id SET DEFAULT concat(
    'R', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)
  );
''',
  '''
ALTER TABLE public.beacon_room_message_reaction
  ALTER COLUMN id SET DEFAULT concat(
    'E', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)
  );
''',
  '''
ALTER TABLE public.beacon_room_message_attachment
  ALTER COLUMN id SET DEFAULT concat(
    'A', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)
  );
''',
  '''
INSERT INTO public.beacon_participant (
  beacon_id, user_id, role, status, room_access, created_at, updated_at
)
SELECT
  b.id,
  b.user_id,
  0,
  0,
  3,
  b.created_at,
  b.updated_at
FROM public.beacon b
ON CONFLICT (beacon_id, user_id) DO NOTHING;
''',
  '''
INSERT INTO public.beacon_participant (
  beacon_id, user_id, role, status, room_access,
  offer_note, created_at, updated_at
)
SELECT
  bc.beacon_id,
  bc.user_id,
  2,
  5,
  3,
  LEFT(COALESCE(bc.message, ''), 2048),
  COALESCE(bc.created_at::timestamptz, now()),
  COALESCE(bc.updated_at::timestamptz, now())
FROM public.beacon_commitment bc
WHERE bc.status = 0
ON CONFLICT (beacon_id, user_id) DO NOTHING;
''',
  // Replace notify_entity_change — keep beacon/commitment/forward branches from m0034, add room.
  r'''
CREATE OR REPLACE FUNCTION public.notify_entity_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  entity_type  text := TG_ARGV[0];
  entity_id    text;
  user_ids     text[];
  suppress_uid text;
BEGIN
  IF entity_type = 'beacon' THEN
    entity_id := COALESCE(NEW.id, OLD.id);
    user_ids  := ARRAY[COALESCE(NEW.user_id, OLD.user_id)];
    BEGIN
      user_ids := user_ids || coalesce((
        SELECT array_agg(DISTINCT bc.user_id)
        FROM public.beacon_commitment bc
        WHERE bc.beacon_id = entity_id AND bc.status = 0
      ), ARRAY[]::text[]);
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'notify_entity_change: beacon committer lookup failed for %: %',
          entity_id, SQLERRM;
    END;
    BEGIN
      user_ids := user_ids || coalesce((
        SELECT array_agg(DISTINCT fe.recipient_id)
        FROM public.beacon_forward_edge fe
        WHERE fe.beacon_id = entity_id
      ), ARRAY[]::text[]);
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'notify_entity_change: beacon forward recipient lookup failed for %: %',
          entity_id, SQLERRM;
    END;

  ELSIF entity_type = 'commitment' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    user_ids  := ARRAY[COALESCE(NEW.user_id, OLD.user_id)];
    BEGIN
      user_ids := user_ids || (
        SELECT ARRAY[b.user_id]
        FROM public.beacon b
        WHERE b.id = entity_id
      );
    EXCEPTION
      WHEN no_data_found THEN
        NULL;
      WHEN OTHERS THEN
        RAISE WARNING 'notify_entity_change: beacon author lookup failed for %: %',
          entity_id, SQLERRM;
    END;

  ELSIF entity_type = 'forward' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    user_ids  := ARRAY[
      COALESCE(NEW.sender_id, OLD.sender_id),
      COALESCE(NEW.recipient_id, OLD.recipient_id)
    ];

  ELSIF entity_type = 'room_message' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    BEGIN
      SELECT coalesce(array_agg(DISTINCT uid), ARRAY[]::text[]) INTO user_ids
      FROM (
        SELECT bp.user_id AS uid FROM public.beacon_participant bp
          WHERE bp.beacon_id = entity_id AND bp.room_access = 3
        UNION ALL
        SELECT b.user_id FROM public.beacon b WHERE b.id = entity_id
        UNION ALL
        SELECT COALESCE(NEW.author_id, OLD.author_id) AS uid
      ) q;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'notify_entity_change: room_message fan-out failed for %: %',
          entity_id, SQLERRM;
        user_ids := ARRAY[]::text[];
    END;

  ELSIF entity_type = 'participant' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    BEGIN
      SELECT coalesce(array_agg(DISTINCT uid), ARRAY[]::text[]) INTO user_ids
      FROM (
        SELECT bp.user_id AS uid FROM public.beacon_participant bp
          WHERE bp.beacon_id = entity_id AND bp.room_access = 3
        UNION ALL
        SELECT b.user_id FROM public.beacon b WHERE b.id = entity_id
        UNION ALL
        SELECT COALESCE(NEW.user_id, OLD.user_id) AS uid
      ) q;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'notify_entity_change: participant fan-out failed for %: %',
          entity_id, SQLERRM;
        user_ids := ARRAY[]::text[];
    END;
  ELSE
    RETURN NULL;
  END IF;

  suppress_uid := current_setting('tentura.mutating_user_id', true);
  IF suppress_uid IS NOT NULL AND suppress_uid <> '' THEN
    user_ids := array_remove(user_ids, suppress_uid);
  END IF;

  IF array_length(user_ids, 1) IS NULL THEN
    RETURN NULL;
  END IF;

  PERFORM pg_notify(
    'entity_changes',
    jsonb_build_object(
      'event',    lower(TG_OP),
      'entity',   entity_type,
      'id',       entity_id,
      'user_ids', to_jsonb(user_ids)
    )::text
  );
  RETURN NULL;
END;
$$;
''',
  '''
DROP TRIGGER IF EXISTS beacon_room_message_notify ON public.beacon_room_message;
''',
  '''
CREATE TRIGGER beacon_room_message_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.beacon_room_message
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_entity_change('room_message');
''',
  '''
DROP TRIGGER IF EXISTS beacon_participant_notify ON public.beacon_participant;
''',
  '''
CREATE TRIGGER beacon_participant_notify
  AFTER INSERT OR UPDATE OF role, status, room_access, next_move_text
    ON public.beacon_participant
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_entity_change('participant');
''',
]);
