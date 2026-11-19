part of '_migrations.dart';

/// Realtime invalidations about a Post's bud follow the same read rules as
/// the bud and the notices that refer to it.
final m0322 = Migration('0322', [
  r'''
CREATE FUNCTION public.realtime_is_post_bud(p_beacon_id text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
SELECT EXISTS (
  SELECT 1
  FROM public.beacon child
  JOIN public.beacon parent ON parent.id = child.parent_beacon_id
  WHERE child.id = p_beacon_id AND child.kind = 0 AND parent.kind = 1
)
$$
''',
  r'''
CREATE FUNCTION public.realtime_room_notice_recipients(
  p_room_id text, p_kind smallint, p_payload jsonb, p_user_ids text[]
) RETURNS text[]
    LANGUAGE sql STABLE
    AS $$
SELECT CASE WHEN p_kind IS NULL THEN p_user_ids ELSE ARRAY(
  SELECT user_id FROM unnest(p_user_ids) AS user_id
  WHERE public.beacon_can_read_room_notice(p_room_id, p_kind, p_payload, user_id)
) END
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.emit_realtime_entity_change(p_entity text, p_id text, p_event text, p_user_ids text[], p_extra jsonb DEFAULT '{}'::jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  normalized_user_ids text[];
  is_post_bud boolean;
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

  -- Cascaded row deletes can supply former recipients after the beacon
  -- itself is gone. No recipient can read that beacon now.
  IF p_event = 'delete' AND p_entity IN (
    'activity_event', 'beacon', 'beacon_hierarchy', 'blocker',
    'coordination_item', 'fact_card', 'forward', 'help_offer', 'inbox_item',
    'participant', 'room_message', 'room_poll', 'room_reaction', 'room_seen'
  ) AND NOT EXISTS (SELECT 1 FROM public.beacon WHERE id = p_id) THEN
    RETURN;
  END IF;

  is_post_bud := public.realtime_is_post_bud(p_id);

  SELECT COALESCE(array_agg(DISTINCT user_id ORDER BY user_id), ARRAY[]::text[])
  INTO normalized_user_ids
  FROM unnest(COALESCE(p_user_ids, ARRAY[]::text[])) AS user_id
  WHERE user_id IS NOT NULL AND user_id <> ''
    AND (NOT is_post_bud OR public.beacon_can_read_content(p_id, user_id));

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
      -- Only the envelope drops nulls: an extra may be an explicit null
      -- (room_seen's Discussion scope).
      payload := (
        jsonb_strip_nulls(
          jsonb_build_object(
            'event', p_event,
            'entity', p_entity,
            'id', p_id,
            'user_ids', to_jsonb(recipient_chunk),
            'actor_user_id', actor_user_id
          )
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
$$
''',
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
  notice public.beacon_room_message%ROWTYPE;
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
    -- A first read changes only the sender's receipt display. Sending this
    -- hint to the reader or other members would refresh their whole Request.
    IF TG_OP = 'UPDATE'
       AND OLD.recipient_read_at IS NULL
       AND NEW.recipient_read_at IS NOT NULL
       AND (to_jsonb(NEW) - 'recipient_read_at') =
           (to_jsonb(OLD) - 'recipient_read_at') THEN
      user_ids := ARRAY[NEW.sender_id];
    ELSE
      user_ids := public.realtime_beacon_recipients(entity_id) || ARRAY[
        COALESCE(NEW.sender_id, OLD.sender_id),
        COALESCE(NEW.recipient_id, OLD.recipient_id)
      ];
    END IF;

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
    IF public.realtime_is_post_bud(entity_id) THEN
      user_ids := user_ids || ARRAY(
        SELECT fe.recipient_id FROM public.beacon_forward_edge fe
        WHERE fe.beacon_id = entity_id
          AND fe.cancelled_at IS NULL AND NOT fe.recipient_rejected
      );
    END IF;
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

    IF TG_OP = 'DELETE' THEN
      notice := OLD;
    ELSE
      notice := NEW;
    END IF;
    user_ids := public.realtime_room_notice_recipients(
      entity_id, notice.system_message_kind, notice.system_payload, user_ids
    );

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
    -- The reader's persisted cursor and its scope (null = Discussion), so
    -- every session of the reader applies it without refetching the room.
    IF TG_OP = 'DELETE' THEN
      extra_payload := jsonb_build_object(
        'thread_item_id', OLD.thread_item_id,
        'last_seen_at', OLD.last_seen_at
      );
    ELSE
      extra_payload := jsonb_build_object(
        'thread_item_id', NEW.thread_item_id,
        'last_seen_at', NEW.last_seen_at
      );
    END IF;

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
  r'''
CREATE OR REPLACE FUNCTION public.notify_room_message_attachment_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  message_id text;
  beacon_id text;
  author_id text;
  thread_item_id text;
  notice_kind smallint;
  notice_payload jsonb;
  user_ids text[];
BEGIN
  message_id := COALESCE(NEW.message_id, OLD.message_id);

  SELECT m.beacon_id, m.author_id, m.thread_item_id,
         m.system_message_kind, m.system_payload
  INTO beacon_id, author_id, thread_item_id, notice_kind, notice_payload
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
    public.realtime_room_notice_recipients(
      beacon_id, notice_kind, notice_payload, user_ids
    ),
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
$$
''',
  r'''
CREATE FUNCTION public.realtime_beacon_hierarchy_emit(
  p_projection_owner_beacon_id text, p_event text,
  p_extra_user_ids text[], p_changed_child_id text
) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  user_ids text[];
BEGIN
  IF p_projection_owner_beacon_id IS NULL OR p_projection_owner_beacon_id = '' THEN
    RETURN;
  END IF;

  user_ids := public.realtime_beacon_hierarchy_recipients(
    p_projection_owner_beacon_id
  ) || COALESCE(p_extra_user_ids, ARRAY[]::text[]);

  -- A child's change can invalidate the Post projection, but its readers
  -- still have to be able to see the child. A Post's own changes have no
  -- child scope, and Request parents keep their existing audience.
  IF p_changed_child_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.beacon
    WHERE id = p_projection_owner_beacon_id AND kind = 1
  ) THEN
    user_ids := ARRAY(
      SELECT user_id FROM unnest(user_ids) AS user_id
      WHERE public.beacon_can_read_content(p_changed_child_id, user_id)
    );
  END IF;

  PERFORM public.emit_realtime_entity_change(
    'beacon_hierarchy', p_projection_owner_beacon_id, p_event, user_ids
  );
END;
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.realtime_beacon_hierarchy_emit(
  p_projection_owner_beacon_id text, p_event text,
  p_extra_user_ids text[] DEFAULT ARRAY[]::text[]
) RETURNS void
    LANGUAGE sql
    AS $$
SELECT public.realtime_beacon_hierarchy_emit(
  p_projection_owner_beacon_id, p_event, p_extra_user_ids, NULL
)
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_beacon_hierarchy_beacon_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  child_row record;
  parent_id text;
  projected_changed boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.published_at IS NOT NULL AND NEW.parent_beacon_id IS NOT NULL THEN
      PERFORM public.realtime_beacon_hierarchy_emit(
        NEW.parent_beacon_id, 'insert', ARRAY[]::text[], NEW.id
      );
    END IF;
    RETURN NULL;
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF OLD.published_at IS NOT NULL AND OLD.parent_beacon_id IS NOT NULL THEN
      PERFORM public.realtime_beacon_hierarchy_emit(
        OLD.parent_beacon_id, 'delete', ARRAY[]::text[], OLD.id
      );
      PERFORM public.realtime_beacon_hierarchy_emit(OLD.id, 'delete');
    ELSIF OLD.published_at IS NOT NULL THEN
      PERFORM public.realtime_beacon_hierarchy_emit(OLD.id, 'delete');
      FOR child_row IN
        SELECT b.id
        FROM public.beacon b
        WHERE b.parent_beacon_id = OLD.id
          AND b.published_at IS NOT NULL
      LOOP
        PERFORM public.realtime_beacon_hierarchy_emit(child_row.id, 'delete');
      END LOOP;
    END IF;
    RETURN NULL;
  END IF;

  -- Draft edits stay on the ordinary beacon channel for the owner only.
  IF NEW.published_at IS NULL THEN
    RETURN NULL;
  END IF;

  IF OLD.published_at IS NULL AND NEW.published_at IS NOT NULL
     AND NEW.parent_beacon_id IS NOT NULL THEN
    PERFORM public.realtime_beacon_hierarchy_emit(
      NEW.parent_beacon_id, 'update', ARRAY[]::text[], NEW.id
    );
    RETURN NULL;
  END IF;

  parent_id := NEW.parent_beacon_id;

  projected_changed :=
    OLD.title IS DISTINCT FROM NEW.title
    OR OLD.status IS DISTINCT FROM NEW.status
    OR OLD.user_id IS DISTINCT FROM NEW.user_id
    OR OLD.description IS DISTINCT FROM NEW.description
    OR OLD.cover_source IS DISTINCT FROM NEW.cover_source
    OR OLD.cover_image_id IS DISTINCT FROM NEW.cover_image_id
    OR OLD.cover_thumb_image_id IS DISTINCT FROM NEW.cover_thumb_image_id
    OR OLD.primary_need_slug IS DISTINCT FROM NEW.primary_need_slug
    OR OLD.needs IS DISTINCT FROM NEW.needs
    OR OLD.status_changed_at IS DISTINCT FROM NEW.status_changed_at;

  IF projected_changed THEN
    -- Chat preview listens on the child aggregate id; Now list on the parent.
    PERFORM public.realtime_beacon_hierarchy_emit(NEW.id, 'update');
    IF parent_id IS NOT NULL THEN
      PERFORM public.realtime_beacon_hierarchy_emit(
        parent_id, 'update', ARRAY[]::text[], NEW.id
      );
    END IF;
  END IF;

  IF OLD.status IS DISTINCT FROM NEW.status AND NEW.status IN (2, 3) THEN
    FOR child_row IN
      SELECT b.id
      FROM public.beacon b
      WHERE b.parent_beacon_id = NEW.id
        AND b.published_at IS NOT NULL
    LOOP
      PERFORM public.realtime_beacon_hierarchy_emit(child_row.id, 'update');
    END LOOP;
  END IF;

  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'notify_beacon_hierarchy_beacon_change failed without aborting write: %',
      SQLERRM;
    RETURN NULL;
END;
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_beacon_hierarchy_admission_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  beacon_id text;
  parent_id text;
  affected_user_id text;
  extra_users text[] := ARRAY[]::text[];
  target record;
BEGIN
  IF TG_TABLE_NAME = 'beacon_participant' THEN
    beacon_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    affected_user_id := COALESCE(NEW.user_id, OLD.user_id);
  ELSIF TG_TABLE_NAME = 'beacon_steward' THEN
    beacon_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    affected_user_id := COALESCE(NEW.user_id, OLD.user_id);
  ELSIF TG_TABLE_NAME = 'user_block' THEN
    affected_user_id := COALESCE(NEW.blocked_id, OLD.blocked_id);
    extra_users := ARRAY[
      COALESCE(NEW.blocker_id, OLD.blocker_id),
      COALESCE(NEW.blocked_id, OLD.blocked_id)
    ];
    FOR target IN
      SELECT q.beacon_id, q.child_id
      FROM (
        SELECT b.id AS beacon_id, NULL::text AS child_id
        FROM public.beacon b
        WHERE b.user_id IN (
          COALESCE(NEW.blocker_id, OLD.blocker_id),
          COALESCE(NEW.blocked_id, OLD.blocked_id)
        )
        UNION
        SELECT b.id, NULL::text
        FROM public.beacon b
        JOIN public.beacon parent ON parent.id = b.parent_beacon_id
        WHERE parent.user_id IN (
          COALESCE(NEW.blocker_id, OLD.blocker_id),
          COALESCE(NEW.blocked_id, OLD.blocked_id)
        )
          AND b.published_at IS NOT NULL
        UNION
        SELECT parent.id, CASE WHEN parent.kind = 1 THEN b.id END
        FROM public.beacon b
        JOIN public.beacon parent ON parent.id = b.parent_beacon_id
        WHERE b.user_id IN (
          COALESCE(NEW.blocker_id, OLD.blocker_id),
          COALESCE(NEW.blocked_id, OLD.blocked_id)
        )
          AND b.published_at IS NOT NULL
      ) q
      LIMIT 50
    LOOP
      PERFORM public.realtime_beacon_hierarchy_emit(
        target.beacon_id, lower(TG_OP), extra_users, target.child_id
      );
    END LOOP;
    RETURN NULL;
  ELSE
    RETURN NULL;
  END IF;

  IF affected_user_id IS NOT NULL AND affected_user_id <> '' THEN
    extra_users := extra_users || ARRAY[affected_user_id];
  END IF;

  PERFORM public.realtime_beacon_hierarchy_emit(
    beacon_id,
    lower(TG_OP),
    extra_users
  );

  SELECT b.parent_beacon_id
  INTO parent_id
  FROM public.beacon b
  WHERE b.id = beacon_id;

  IF parent_id IS NOT NULL AND parent_id <> '' THEN
    PERFORM public.realtime_beacon_hierarchy_emit(
      parent_id, lower(TG_OP), extra_users, beacon_id
    );
  END IF;

  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'notify_beacon_hierarchy_admission_change failed without aborting write: %',
      SQLERRM;
    RETURN NULL;
END;
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_beacon_hierarchy_profile_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  target record;
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RETURN NULL;
  END IF;

  IF NOT (
    OLD.display_name IS DISTINCT FROM NEW.display_name
    OR OLD.image_id IS DISTINCT FROM NEW.image_id
  ) THEN
    RETURN NULL;
  END IF;

  -- Owned published beacons (+ their parents) and admitted-helper memberships.
  FOR target IN
    SELECT q.beacon_id, q.child_id
    FROM (
      SELECT b.id AS beacon_id, NULL::text AS child_id
      FROM public.beacon b
      WHERE b.user_id = NEW.id
        AND b.published_at IS NOT NULL
      UNION
      SELECT parent.id, CASE WHEN parent.kind = 1 THEN b.id END
      FROM public.beacon b
      JOIN public.beacon parent ON parent.id = b.parent_beacon_id
      WHERE b.user_id = NEW.id
        AND b.published_at IS NOT NULL
      UNION
      SELECT bah.beacon_id, NULL::text
      FROM public.beacon_admitted_helper bah
      WHERE bah.user_id = NEW.id
      UNION
      SELECT parent.id, CASE WHEN parent.kind = 1 THEN b.id END
      FROM public.beacon_admitted_helper bah
      JOIN public.beacon b ON b.id = bah.beacon_id
      JOIN public.beacon parent ON parent.id = b.parent_beacon_id
      WHERE bah.user_id = NEW.id
    ) q
    LIMIT 50
  LOOP
    PERFORM public.realtime_beacon_hierarchy_emit(
      target.beacon_id, 'update', ARRAY[]::text[], target.child_id
    );
  END LOOP;

  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'notify_beacon_hierarchy_profile_change failed without aborting write: %',
      SQLERRM;
    RETURN NULL;
END;
$$
''',
]);
