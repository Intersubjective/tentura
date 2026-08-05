part of '_migrations.dart';

/// Room message NOTIFY extras (`message_id`) and attachment invalidation.
final m0133 = Migration('0133', [
  'DROP FUNCTION IF EXISTS public.emit_realtime_entity_change(text, text, text, text[]);',
  r'''
CREATE OR REPLACE FUNCTION public.emit_realtime_entity_change(
  p_entity text,
  p_id text,
  p_event text,
  p_user_ids text[],
  p_extra jsonb DEFAULT '{}'::jsonb
) RETURNS void
  LANGUAGE plpgsql
  AS $$
DECLARE
  normalized_user_ids text[];
  actor_user_id text;
  recipient_index integer := 1;
  recipient_count integer;
  take_count integer;
  recipient_chunk text[];
  payload text;
BEGIN
  IF p_entity IS NULL OR p_entity = ''
     OR p_id IS NULL OR p_id = ''
     OR p_event NOT IN ('insert', 'update', 'delete') THEN
    RAISE WARNING 'emit_realtime_entity_change: invalid envelope for kind %',
      COALESCE(p_entity, '<null>');
    RETURN;
  END IF;

  SELECT COALESCE(array_agg(DISTINCT user_id ORDER BY user_id), ARRAY[]::text[])
  INTO normalized_user_ids
  FROM unnest(COALESCE(p_user_ids, ARRAY[]::text[])) AS user_id
  WHERE user_id IS NOT NULL AND user_id <> '';

  IF cardinality(normalized_user_ids) = 0 THEN
    RETURN;
  END IF;

  actor_user_id := NULLIF(
    current_setting('tentura.mutating_user_id', true),
    ''
  );
  recipient_count := cardinality(normalized_user_ids);

  WHILE recipient_index <= recipient_count LOOP
    take_count := LEAST(100, recipient_count - recipient_index + 1);

    LOOP
      recipient_chunk := normalized_user_ids[
        recipient_index:recipient_index + take_count - 1
      ];
      payload := jsonb_strip_nulls(
        jsonb_build_object(
          'event', p_event,
          'entity', p_entity,
          'id', p_id,
          'user_ids', to_jsonb(recipient_chunk),
          'actor_user_id', actor_user_id
        ) || COALESCE(p_extra, '{}'::jsonb)
      )::text;

      EXIT WHEN octet_length(payload) < 7900;
      IF take_count = 1 THEN
        RAISE WARNING
          'emit_realtime_entity_change: one-recipient payload exceeded byte budget for kind %',
          p_entity;
        payload := NULL;
        EXIT;
      END IF;
      take_count := GREATEST(1, take_count / 2);
    END LOOP;

    IF payload IS NOT NULL THEN
      BEGIN
        PERFORM pg_notify('entity_changes', payload);
      EXCEPTION
        WHEN OTHERS THEN
          RAISE WARNING
            'emit_realtime_entity_change: pg_notify failed for kind % recipients %: %',
            p_entity, take_count, SQLERRM;
      END;
    END IF;
    recipient_index := recipient_index + take_count;
  END LOOP;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'emit_realtime_entity_change: envelope failed for kind %: %',
      COALESCE(p_entity, '<null>'), SQLERRM;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_entity_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  entity_type text := TG_ARGV[0];
  wire_entity text := entity_type;
  entity_id text;
  user_ids text[] := ARRAY[]::text[];
  visibility smallint;
  thread_item_id text;
  polling_id text;
  extra_payload jsonb := '{}'::jsonb;
BEGIN
  IF entity_type = 'beacon' THEN
    entity_id := COALESCE(NEW.id, OLD.id);
    user_ids := public.realtime_beacon_recipients(entity_id);

  ELSIF entity_type = 'help_offer' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    user_ids := public.realtime_beacon_recipients(entity_id) || ARRAY[
      COALESCE(NEW.user_id, OLD.user_id)
    ];

  ELSIF entity_type = 'forward' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    user_ids := public.realtime_beacon_recipients(entity_id) || ARRAY[
      COALESCE(NEW.sender_id, OLD.sender_id),
      COALESCE(NEW.recipient_id, OLD.recipient_id)
    ];

  ELSIF entity_type = 'room_message' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    thread_item_id := COALESCE(NEW.thread_item_id, OLD.thread_item_id);
    extra_payload := jsonb_build_object(
      'message_id', COALESCE(NEW.id, OLD.id)
    );
    user_ids := public.realtime_room_recipients(entity_id) || ARRAY[
      COALESCE(NEW.author_id, OLD.author_id)
    ] || CASE TG_OP
      WHEN 'DELETE' THEN COALESCE(OLD.mentions, ARRAY[]::text[])
      ELSE COALESCE(NEW.mentions, ARRAY[]::text[])
    END;
    IF thread_item_id IS NOT NULL THEN
      user_ids := user_ids || COALESCE(
        (
          SELECT ARRAY[ci.creator_id, ci.target_person_id, ci.accepted_by_id]
          FROM public.coordination_item ci
          WHERE ci.id = thread_item_id
        ),
        ARRAY[]::text[]
      );
    END IF;

  ELSIF entity_type = 'participant' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    user_ids := public.realtime_room_recipients(entity_id) || ARRAY[
      COALESCE(NEW.user_id, OLD.user_id)
    ];

  ELSIF entity_type IN ('fact_card', 'blocker', 'activity_event') THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    visibility := COALESCE(NEW.visibility, OLD.visibility);
    user_ids := CASE
      WHEN visibility = 1 THEN public.realtime_room_recipients(entity_id)
      ELSE public.realtime_beacon_recipients(entity_id)
    END;

  ELSIF entity_type = 'coordination_item' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    IF (TG_OP = 'DELETE' AND NOT COALESCE(OLD.published, true))
       OR (TG_OP <> 'DELETE' AND NOT COALESCE(NEW.published, true)) THEN
      user_ids := ARRAY[COALESCE(NEW.creator_id, OLD.creator_id)];
    ELSE
      user_ids := public.realtime_room_recipients(entity_id) || ARRAY[
        COALESCE(NEW.creator_id, OLD.creator_id),
        COALESCE(NEW.target_person_id, OLD.target_person_id),
        COALESCE(NEW.accepted_by_id, OLD.accepted_by_id)
      ];
    END IF;

  ELSIF entity_type = 'person_capability_event' THEN
    entity_id := COALESCE(NEW.subject_user_id, OLD.subject_user_id);
    user_ids := ARRAY[
      COALESCE(NEW.subject_user_id, OLD.subject_user_id),
      COALESCE(NEW.observer_user_id, OLD.observer_user_id)
    ];

  ELSIF entity_type = 'inbox_item' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    user_ids := ARRAY[COALESCE(NEW.user_id, OLD.user_id)];

  ELSIF entity_type = 'contact' THEN
    entity_id := COALESCE(NEW.subject_id, OLD.subject_id);
    user_ids := ARRAY[COALESCE(NEW.viewer_id, OLD.viewer_id)];

  ELSIF entity_type = 'room_reaction' THEN
    SELECT message.beacon_id
    INTO entity_id
    FROM public.beacon_room_message message
    WHERE message.id = COALESCE(NEW.message_id, OLD.message_id);
    user_ids := public.realtime_room_recipients(entity_id) || ARRAY[
      COALESCE(NEW.user_id, OLD.user_id)
    ];

  ELSIF entity_type IN ('room_poll', 'room_poll_act') THEN
    wire_entity := 'room_poll';
    polling_id := CASE
      WHEN entity_type = 'room_poll' THEN COALESCE(NEW.id, OLD.id)
      ELSE COALESCE(NEW.polling_id, OLD.polling_id)
    END;
    SELECT message.beacon_id
    INTO entity_id
    FROM public.beacon_room_message message
    WHERE message.linked_polling_id = polling_id
    ORDER BY message.created_at DESC
    LIMIT 1;
    user_ids := public.realtime_room_recipients(entity_id);
    IF entity_type = 'room_poll_act' THEN
      user_ids := user_ids || ARRAY[COALESCE(NEW.author_id, OLD.author_id)];
    END IF;

  ELSIF entity_type = 'room_seen' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    user_ids := ARRAY[COALESCE(NEW.user_id, OLD.user_id)];

  ELSIF entity_type = 'profile' THEN
    entity_id := COALESCE(NEW.id, OLD.id);
    user_ids := public.realtime_subject_recipients(ARRAY[entity_id]);

  ELSIF entity_type = 'notification' THEN
    entity_id := COALESCE(NEW.account_id, OLD.account_id);
    user_ids := ARRAY[entity_id];

  ELSE
    RAISE WARNING 'notify_entity_change: unsupported trigger argument %', entity_type;
    RETURN NULL;
  END IF;

  PERFORM public.emit_realtime_entity_change(
    wire_entity,
    entity_id,
    lower(TG_OP),
    user_ids,
    extra_payload
  );
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_entity_change: kind % failed without aborting write: %',
      entity_type, SQLERRM;
    RETURN NULL;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_room_message_attachment_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  message_id text;
  beacon_id text;
  author_id text;
  thread_item_id text;
  user_ids text[];
BEGIN
  message_id := COALESCE(NEW.message_id, OLD.message_id);

  SELECT m.beacon_id, m.author_id, m.thread_item_id
  INTO beacon_id, author_id, thread_item_id
  FROM public.beacon_room_message m
  WHERE m.id = message_id;

  IF beacon_id IS NULL THEN
    RETURN NULL;
  END IF;

  user_ids := public.realtime_room_recipients(beacon_id) || ARRAY[author_id];
  IF thread_item_id IS NOT NULL THEN
    user_ids := user_ids || COALESCE(
      (
        SELECT ARRAY[ci.creator_id, ci.target_person_id, ci.accepted_by_id]
        FROM public.coordination_item ci
        WHERE ci.id = thread_item_id
      ),
      ARRAY[]::text[]
    );
  END IF;

  PERFORM public.emit_realtime_entity_change(
    'room_message',
    beacon_id,
    'update',
    user_ids,
    jsonb_build_object('message_id', message_id)
  );
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'notify_room_message_attachment_change failed without aborting write: %',
      SQLERRM;
    RETURN NULL;
END;
$$;
''',
  'DROP TRIGGER IF EXISTS beacon_room_message_attachment_notify '
      'ON public.beacon_room_message_attachment;',
  '''
CREATE TRIGGER beacon_room_message_attachment_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.beacon_room_message_attachment
  FOR EACH ROW EXECUTE FUNCTION public.notify_room_message_attachment_change();
''',
]);
