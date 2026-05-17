part of '_migrations.dart';

/// Unify coordination_item_message into beacon_room_message via thread_item_id.
final m0072 = Migration('0072', [
  // 1. New column on beacon_room_message
  '''
ALTER TABLE public.beacon_room_message
  ADD COLUMN thread_item_id text NULL
  REFERENCES public.coordination_item(id) ON DELETE CASCADE;
''',
  '''
CREATE INDEX idx_beacon_room_message_thread_item
  ON public.beacon_room_message(thread_item_id, created_at)
  WHERE thread_item_id IS NOT NULL;
''',

  // 2. New beacon_room_seen table
  '''
CREATE TABLE public.beacon_room_seen (
  user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  beacon_id text NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
  thread_item_id text NULL REFERENCES public.coordination_item(id) ON DELETE CASCADE,
  last_seen_at timestamptz NOT NULL
);
''',
  // Two partial unique indexes since NULL ≠ NULL in btree
  '''
CREATE UNIQUE INDEX uq_beacon_room_seen_main
  ON public.beacon_room_seen(user_id, beacon_id)
  WHERE thread_item_id IS NULL;
''',
  '''
CREATE UNIQUE INDEX uq_beacon_room_seen_thread
  ON public.beacon_room_seen(user_id, beacon_id, thread_item_id)
  WHERE thread_item_id IS NOT NULL;
''',

  // 3. Backfill: coordination_item_message rows → beacon_room_message
  //    (preserves 'J…' ids and timestamps)
  '''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body,
  reply_to_message_id,
  linked_blocker_id, linked_next_move_id, linked_fact_card_id,
  linked_polling_id, linked_item_id, linked_event_kind,
  semantic_marker, system_payload,
  created_at, edited_at, mentions,
  thread_item_id
)
SELECT
  cim.id, cim.beacon_id, cim.sender_id, cim.body,
  NULL,
  NULL, NULL, NULL,
  NULL, NULL, NULL,
  NULL, NULL,
  cim.created_at, cim.edited_at, ARRAY[]::text[],
  cim.item_id
FROM public.coordination_item_message cim;
''',

  // 4. Backfill: coordination_item_user_seen → beacon_room_seen
  '''
INSERT INTO public.beacon_room_seen (user_id, beacon_id, thread_item_id, last_seen_at)
SELECT s.user_id, ci.beacon_id, s.item_id, s.last_seen_at
FROM public.coordination_item_user_seen s
JOIN public.coordination_item ci ON ci.id = s.item_id;
''',

  // 5. Backfill: beacon_participant.last_seen_room_at → beacon_room_seen (thread_item_id NULL)
  '''
INSERT INTO public.beacon_room_seen (user_id, beacon_id, thread_item_id, last_seen_at)
SELECT bp.user_id, bp.beacon_id, NULL, bp.last_seen_room_at
FROM public.beacon_participant bp
WHERE bp.last_seen_room_at IS NOT NULL;
''',

  // 6. Replace notify_entity_change()
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
  thread_iid   text;
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
    entity_id  := COALESCE(NEW.beacon_id, OLD.beacon_id);
    thread_iid := COALESCE(NEW.thread_item_id, OLD.thread_item_id);
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
        UNION ALL
        SELECT ci.creator_id AS uid FROM public.coordination_item ci
          WHERE thread_iid IS NOT NULL AND ci.id = thread_iid
        UNION ALL
        SELECT ci.target_person_id AS uid FROM public.coordination_item ci
          WHERE thread_iid IS NOT NULL AND ci.id = thread_iid
        UNION ALL
        SELECT ci.accepted_by_id AS uid FROM public.coordination_item ci
          WHERE thread_iid IS NOT NULL AND ci.id = thread_iid
      ) q
      WHERE q.uid IS NOT NULL;
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
    IF (TG_OP = 'DELETE' AND NOT COALESCE(OLD.published, true))
       OR (TG_OP <> 'DELETE' AND NOT COALESCE(NEW.published, true)) THEN
      user_ids := ARRAY[COALESCE(NEW.creator_id, OLD.creator_id)];
    ELSE
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
    END IF;

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

  // 7. Drop legacy trigger (function no longer handles coordination_item_message)
  '''
DROP TRIGGER IF EXISTS coordination_item_message_entity_notify
  ON public.coordination_item_message;
''',

  // 8. Drop legacy tables (after data migrated)
  '''
DROP TABLE public.coordination_item_user_seen;
''',
  '''
DROP TABLE public.coordination_item_message;
''',

  // 9. Drop legacy column on beacon_participant
  '''
ALTER TABLE public.beacon_participant DROP COLUMN last_seen_room_at;
''',
]);

