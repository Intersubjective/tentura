part of '_migrations.dart';

/// `beacon_fact_card` + FK from `beacon_room_message.linked_fact_card_id`; extends
/// `notify_entity_change` with a `fact_card` branch (`entity_id` = beacon_id).
final m0039 = Migration('0039', [
  r'''
CREATE TABLE IF NOT EXISTS public.beacon_fact_card (
  id text NOT NULL PRIMARY KEY DEFAULT (
    concat('F', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12))
  ),
  beacon_id text NOT NULL
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE,
  fact_text text NOT NULL,
  visibility smallint NOT NULL,
  pinned_by text NOT NULL
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  source_message_id text NULL
    REFERENCES public.beacon_room_message(id) ON UPDATE CASCADE ON DELETE SET NULL,
  status smallint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT beacon_fact_card_visibility_chk CHECK (visibility IN (0, 1)),
  CONSTRAINT beacon_fact_card_status_chk CHECK (status IN (0, 1, 2))
);

CREATE INDEX IF NOT EXISTS beacon_fact_card_beacon_idx
  ON public.beacon_fact_card (beacon_id, created_at DESC);
''',
  r'''
ALTER TABLE public.beacon_room_message
  DROP CONSTRAINT IF EXISTS beacon_room_message_linked_fact_card_id_fkey;
''',
  r'''
ALTER TABLE public.beacon_room_message
  ADD CONSTRAINT beacon_room_message_linked_fact_card_id_fkey
    FOREIGN KEY (linked_fact_card_id)
    REFERENCES public.beacon_fact_card(id)
    ON UPDATE CASCADE ON DELETE SET NULL;
''',
  // Full replace — keep beacon/commitment/forward/room_message/participant + fact_card.
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
  vis          smallint;
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

  ELSIF entity_type = 'fact_card' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    vis := COALESCE(NEW.visibility, OLD.visibility);
    IF vis = 1 THEN
      BEGIN
        SELECT coalesce(array_agg(DISTINCT uid), ARRAY[]::text[]) INTO user_ids
        FROM (
          SELECT bp.user_id AS uid FROM public.beacon_participant bp
            WHERE bp.beacon_id = entity_id AND bp.room_access = 3
          UNION ALL
          SELECT b.user_id FROM public.beacon b WHERE b.id = entity_id
        ) q;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE WARNING 'notify_entity_change: fact_card room fan-out failed for %: %',
            entity_id, SQLERRM;
          user_ids := ARRAY[]::text[];
      END;
    ELSE
      BEGIN
        SELECT coalesce(array_agg(DISTINCT uid), ARRAY[]::text[]) INTO user_ids
        FROM (
          SELECT bp.user_id AS uid FROM public.beacon_participant bp
            WHERE bp.beacon_id = entity_id
          UNION ALL
          SELECT b.user_id FROM public.beacon b WHERE b.id = entity_id
          UNION ALL
          SELECT DISTINCT fe.sender_id AS uid FROM public.beacon_forward_edge fe
            WHERE fe.beacon_id = entity_id
          UNION ALL
          SELECT DISTINCT fe.recipient_id AS uid FROM public.beacon_forward_edge fe
            WHERE fe.beacon_id = entity_id
          UNION ALL
          SELECT DISTINCT bc.user_id FROM public.beacon_commitment bc
            WHERE bc.beacon_id = entity_id AND bc.status = 0
        ) q;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE WARNING 'notify_entity_change: fact_card public fan-out failed for %: %',
            entity_id, SQLERRM;
          user_ids := ARRAY[]::text[];
      END;
    END IF;

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
  r'''
DROP TRIGGER IF EXISTS beacon_fact_card_notify ON public.beacon_fact_card;
''',
  r'''
CREATE TRIGGER beacon_fact_card_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.beacon_fact_card
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_entity_change('fact_card');
''',
]);
