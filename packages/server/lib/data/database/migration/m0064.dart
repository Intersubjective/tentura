part of '_migrations.dart';

/// Coordination items + item messages, room message links, indexes, and
/// `notify_entity_change` fan-out for `coordination_item` /
/// `coordination_item_message`.
final m0064 = Migration('0064', [
  // --- 1. coordination_item ---
  '''
CREATE TABLE public.coordination_item (
  id text PRIMARY KEY,
  beacon_id text NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
  kind smallint NOT NULL,
  status smallint NOT NULL DEFAULT 0,
  title text NOT NULL DEFAULT '',
  body text NOT NULL DEFAULT '',
  creator_id text NOT NULL REFERENCES public."user"(id),
  target_person_id text REFERENCES public."user"(id),
  accepted_by_id text REFERENCES public."user"(id),
  target_item_id text REFERENCES public.coordination_item(id) ON DELETE SET NULL,
  target_message_id text REFERENCES public.beacon_room_message(id) ON DELETE SET NULL,
  linked_message_id text REFERENCES public.beacon_room_message(id) ON DELETE SET NULL,
  linked_parent_item_id text REFERENCES public.coordination_item(id) ON DELETE SET NULL,
  ordering smallint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  cancelled_at timestamptz
);
''',

  // --- 2. coordination_item_message ---
  '''
CREATE TABLE public.coordination_item_message (
  id text PRIMARY KEY,
  item_id text NOT NULL REFERENCES public.coordination_item(id) ON DELETE CASCADE,
  beacon_id text NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
  sender_id text NOT NULL REFERENCES public."user"(id),
  body text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  edited_at timestamptz
);
''',

  // --- 3. beacon_room_message columns ---
  '''
ALTER TABLE public.beacon_room_message ADD COLUMN linked_item_id text REFERENCES public.coordination_item(id) ON DELETE SET NULL;
''',
  '''
ALTER TABLE public.beacon_room_message ADD COLUMN linked_event_kind smallint;
''',

  // --- 4. Indexes ---
  '''
CREATE INDEX idx_coordination_item_beacon_status_kind ON public.coordination_item(beacon_id, status, kind);
''',
  '''
CREATE INDEX idx_coordination_item_target_item ON public.coordination_item(target_item_id) WHERE target_item_id IS NOT NULL;
''',
  '''
CREATE INDEX idx_coordination_item_message_item_created ON public.coordination_item_message(item_id, created_at);
''',

  // --- 5. Triggers (function body updated in step 6) ---
  '''
CREATE TRIGGER coordination_item_entity_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.coordination_item
  FOR EACH ROW EXECUTE FUNCTION public.notify_entity_change('coordination_item');
''',
  '''
CREATE TRIGGER coordination_item_message_entity_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.coordination_item_message
  FOR EACH ROW EXECUTE FUNCTION public.notify_entity_change('coordination_item_message');
''',

  // --- 6. notify_entity_change: coordination_item / coordination_item_message ---
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
        SELECT array_agg(DISTINCT ho.user_id)
        FROM public.beacon_help_offer ho
        WHERE ho.beacon_id = entity_id AND ho.status = 0
      ), ARRAY[]::text[]);
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'notify_entity_change: beacon help_offerer lookup failed for %: %',
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

  ELSIF entity_type = 'help_offer' THEN
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
        UNION ALL
        SELECT unnest(
          CASE TG_OP
            WHEN 'DELETE' THEN COALESCE(OLD.mentions, ARRAY[]::text[])
            ELSE COALESCE(NEW.mentions, ARRAY[]::text[])
          END
        ) AS uid
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
          SELECT DISTINCT ho.user_id FROM public.beacon_help_offer ho
            WHERE ho.beacon_id = entity_id AND ho.status = 0
        ) q;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE WARNING 'notify_entity_change: fact_card public fan-out failed for %: %',
            entity_id, SQLERRM;
          user_ids := ARRAY[]::text[];
      END;
    END IF;

  ELSIF entity_type = 'blocker' THEN
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
          RAISE WARNING 'notify_entity_change: blocker room fan-out failed for %: %',
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
          SELECT DISTINCT ho.user_id FROM public.beacon_help_offer ho
            WHERE ho.beacon_id = entity_id AND ho.status = 0
        ) q;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE WARNING 'notify_entity_change: blocker public fan-out failed for %: %',
            entity_id, SQLERRM;
          user_ids := ARRAY[]::text[];
      END;
    END IF;

  ELSIF entity_type = 'activity_event' THEN
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
          RAISE WARNING 'notify_entity_change: activity_event room fan-out failed for %: %',
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
          SELECT DISTINCT ho.user_id FROM public.beacon_help_offer ho
            WHERE ho.beacon_id = entity_id AND ho.status = 0
        ) q;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE WARNING 'notify_entity_change: activity_event public fan-out failed for %: %',
            entity_id, SQLERRM;
          user_ids := ARRAY[]::text[];
      END;
    END IF;

  ELSIF entity_type = 'coordination_item' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    BEGIN
      SELECT coalesce(array_agg(DISTINCT q.uid), ARRAY[]::text[]) INTO user_ids
      FROM (
        SELECT bp.user_id AS uid FROM public.beacon_participant bp
          WHERE bp.beacon_id = entity_id AND bp.room_access = 3
        UNION ALL
        SELECT b.user_id FROM public.beacon b WHERE b.id = entity_id
        UNION ALL
        SELECT COALESCE(NEW.creator_id, OLD.creator_id) AS uid
        UNION ALL
        SELECT COALESCE(NEW.target_person_id, OLD.target_person_id) AS uid
        UNION ALL
        SELECT COALESCE(NEW.accepted_by_id, OLD.accepted_by_id) AS uid
      ) q
      WHERE q.uid IS NOT NULL;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'notify_entity_change: coordination_item fan-out failed for %: %',
          entity_id, SQLERRM;
        user_ids := ARRAY[]::text[];
    END;

  ELSIF entity_type = 'coordination_item_message' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    BEGIN
      SELECT coalesce(array_agg(DISTINCT q.uid), ARRAY[]::text[]) INTO user_ids
      FROM (
        SELECT bp.user_id AS uid FROM public.beacon_participant bp
          WHERE bp.beacon_id = entity_id AND bp.room_access = 3
        UNION ALL
        SELECT b.user_id FROM public.beacon b WHERE b.id = entity_id
        UNION ALL
        SELECT COALESCE(NEW.sender_id, OLD.sender_id) AS uid
        UNION ALL
        SELECT i.creator_id AS uid FROM public.coordination_item i
          WHERE i.id = COALESCE(NEW.item_id, OLD.item_id)
        UNION ALL
        SELECT i.target_person_id AS uid FROM public.coordination_item i
          WHERE i.id = COALESCE(NEW.item_id, OLD.item_id)
        UNION ALL
        SELECT i.accepted_by_id AS uid FROM public.coordination_item i
          WHERE i.id = COALESCE(NEW.item_id, OLD.item_id)
      ) q
      WHERE q.uid IS NOT NULL;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'notify_entity_change: coordination_item_message fan-out failed for %: %',
          entity_id, SQLERRM;
        user_ids := ARRAY[]::text[];
    END;

  ELSIF entity_type = 'person_capability_event' THEN
    entity_id := COALESCE(NEW.subject_user_id, OLD.subject_user_id);
    user_ids  := ARRAY[
      COALESCE(NEW.subject_user_id,  OLD.subject_user_id),
      COALESCE(NEW.observer_user_id, OLD.observer_user_id)
    ];

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
]);
