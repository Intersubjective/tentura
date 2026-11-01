part of '_migrations.dart';

/// Room poll votes reach the open chats live (#738).
///
/// The `room_poll` / `room_poll_act` branch of `notify_entity_change` picked
/// the poll id with one CASE expression naming both `NEW.id` (polling) and
/// `NEW.polling_id` (polling_act). PL/pgSQL plans the whole expression, so it
/// raised «record "new" has no field …» on either table; the function's
/// exception handler turned that into a warning and no `room_poll` hint was
/// ever sent. The function is otherwise unchanged from `m0193.dart`.
final m0281 = Migration('0281', [
  r'''
CREATE OR REPLACE FUNCTION public.notify_entity_change() RETURNS trigger
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
    -- Separate statements: PL/pgSQL plans a whole expression at once, so a
    -- CASE naming both NEW.id and NEW.polling_id fails on either table.
    IF entity_type = 'room_poll' THEN
      polling_id := COALESCE(NEW.id, OLD.id);
    ELSE
      polling_id := COALESCE(NEW.polling_id, OLD.polling_id);
    END IF;
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
$$
''',
]);
