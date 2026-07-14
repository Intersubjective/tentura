part of '_migrations.dart';

/// Completes the realtime invalidation producer contract.
///
/// All publishers delegate to the SQL `emit_realtime_entity_change`, which keeps actor
/// metadata, normalizes recipients, and bounds every NOTIFY payload. Relationship
/// tables use statement-level transition tables so bulk trust writes coalesce.
final m0114 = Migration('0114', [
  // Shared, indexed recipient lookups used by trigger functions.
  r'''
CREATE OR REPLACE FUNCTION public.realtime_room_recipients(p_beacon_id text)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  AS $$
SELECT COALESCE(array_agg(DISTINCT q.user_id ORDER BY q.user_id), ARRAY[]::text[])
FROM (
  SELECT b.user_id
  FROM public.beacon b
  WHERE b.id = p_beacon_id
  UNION ALL
  SELECT bp.user_id
  FROM public.beacon_participant bp
  WHERE bp.beacon_id = p_beacon_id AND bp.room_access = 3
) q
WHERE q.user_id IS NOT NULL AND q.user_id <> '';
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.realtime_beacon_recipients(p_beacon_id text)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  AS $$
SELECT COALESCE(array_agg(DISTINCT q.user_id ORDER BY q.user_id), ARRAY[]::text[])
FROM (
  SELECT b.user_id
  FROM public.beacon b
  WHERE b.id = p_beacon_id
  UNION ALL
  SELECT bp.user_id
  FROM public.beacon_participant bp
  WHERE bp.beacon_id = p_beacon_id
  UNION ALL
  SELECT ho.user_id
  FROM public.beacon_help_offer ho
  WHERE ho.beacon_id = p_beacon_id AND ho.status = 0
  UNION ALL
  SELECT fe.sender_id
  FROM public.beacon_forward_edge fe
  WHERE fe.beacon_id = p_beacon_id AND fe.cancelled_at IS NULL
  UNION ALL
  SELECT fe.recipient_id
  FROM public.beacon_forward_edge fe
  WHERE fe.beacon_id = p_beacon_id AND fe.cancelled_at IS NULL
) q
WHERE q.user_id IS NOT NULL AND q.user_id <> '';
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.realtime_subject_recipients(p_subject_ids text[])
  RETURNS text[]
  LANGUAGE sql
  STABLE
  AS $$
WITH subjects AS (
  SELECT DISTINCT subject_id
  FROM unnest(COALESCE(p_subject_ids, ARRAY[]::text[])) AS subject_id
  WHERE subject_id IS NOT NULL AND subject_id <> ''
),
mutual_friends AS (
  SELECT DISTINCT CASE
    WHEN vu.subject = s.subject_id THEN vu.object
    ELSE vu.subject
  END AS user_id
  FROM subjects s
  JOIN public.vote_user vu
    ON (vu.subject = s.subject_id OR vu.object = s.subject_id)
   AND vu.amount > 0
  WHERE EXISTS (
    SELECT 1
    FROM public.vote_user reverse_vote
    WHERE reverse_vote.subject = vu.object
      AND reverse_vote.object = vu.subject
      AND reverse_vote.amount > 0
  )
),
shared_beacons AS (
  SELECT b.id AS beacon_id
  FROM subjects s JOIN public.beacon b ON b.user_id = s.subject_id
  UNION
  SELECT bp.beacon_id
  FROM subjects s JOIN public.beacon_participant bp ON bp.user_id = s.subject_id
  UNION
  SELECT ho.beacon_id
  FROM subjects s JOIN public.beacon_help_offer ho ON ho.user_id = s.subject_id
  WHERE ho.status = 0
  UNION
  SELECT fe.beacon_id
  FROM subjects s JOIN public.beacon_forward_edge fe
    ON fe.sender_id = s.subject_id OR fe.recipient_id = s.subject_id
  WHERE fe.cancelled_at IS NULL
),
recipients AS (
  SELECT subject_id AS user_id FROM subjects
  UNION
  SELECT user_id FROM mutual_friends
  UNION
  SELECT unnest(public.realtime_beacon_recipients(beacon_id))
  FROM shared_beacons
)
SELECT COALESCE(
  ARRAY(
    SELECT DISTINCT user_id
    FROM recipients
    WHERE user_id IS NOT NULL AND user_id <> ''
    ORDER BY user_id
    LIMIT 2000
  ),
  ARRAY[]::text[]
);
$$;
''',

  // One failure-contained, byte-safe emission path for every producer.
  'DROP FUNCTION IF EXISTS public.emit_realtime_entity_change(text, text, text, text[], text[]);',
  r'''
CREATE OR REPLACE FUNCTION public.emit_realtime_entity_change(
  p_entity text,
  p_id text,
  p_event text,
  p_user_ids text[]
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
      payload := jsonb_strip_nulls(jsonb_build_object(
        'event', p_event,
        'entity', p_entity,
        'id', p_id,
        'user_ids', to_jsonb(recipient_chunk),
        'actor_user_id', actor_user_id
      ))::text;

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
      -- Notification-queue exhaustion is raised at COMMIT, outside this block,
      -- so it still fails the transaction instead of being swallowed here.
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

  // The generic row publisher retains the existing entities and adds all
  // remaining state-bearing projection sources.
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
    user_ids
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

  // Both specialized help-offer publishers now use the same emitter.
  r'''
CREATE OR REPLACE FUNCTION public.notify_coordination_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  entity_id text;
  user_ids text[];
BEGIN
  entity_id := COALESCE(NEW.offer_beacon_id, OLD.offer_beacon_id);
  user_ids := public.realtime_beacon_recipients(entity_id) || ARRAY[
    COALESCE(NEW.offer_user_id, OLD.offer_user_id),
    COALESCE(NEW.author_user_id, OLD.author_user_id)
  ];
  PERFORM public.emit_realtime_entity_change(
    'help_offer', entity_id, lower(TG_OP), user_ids
  );
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_coordination_change failed without aborting write: %', SQLERRM;
    RETURN NULL;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_help_offer_admission_event_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  entity_id text;
  user_ids text[];
BEGIN
  entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
  user_ids := public.realtime_beacon_recipients(entity_id) || ARRAY[
    COALESCE(NEW.offer_user_id, OLD.offer_user_id),
    COALESCE(NEW.actor_user_id, OLD.actor_user_id)
  ];
  PERFORM public.emit_realtime_entity_change(
    'help_offer', entity_id, lower(TG_OP), user_ids
  );
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'notify_help_offer_admission_event_change failed without aborting write: %',
      SQLERRM;
    RETURN NULL;
END;
$$;
''',

  // Coalesce relationship mutations once per SQL statement. Changed users are
  // split before the indexed bounded-recipient lookup and emission.
  r'''
CREATE OR REPLACE FUNCTION public.notify_relationship_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  changed_subject_ids text[];
  subject_chunk text[];
  user_ids text[];
  subject_index integer := 1;
  subject_count integer;
BEGIN
  -- Bulk trust maintenance (full recompute / single-source resync) rewrites
  -- prev_sent_weight for decay bookkeeping without changing any client-visible
  -- relationship. Those paths set this transaction-local flag so the rewrite
  -- does not fan a relationship invalidation out to every recipient.
  IF current_setting('tentura.suppress_relationship_notify', true) = '1' THEN
    RETURN NULL;
  END IF;
  IF TG_OP = 'INSERT' THEN
    SELECT array_agg(DISTINCT id ORDER BY id)
    INTO changed_subject_ids
    FROM (
      SELECT subject AS id FROM new_rows
      UNION
      SELECT object AS id FROM new_rows
    ) changed;
  ELSIF TG_OP = 'DELETE' THEN
    SELECT array_agg(DISTINCT id ORDER BY id)
    INTO changed_subject_ids
    FROM (
      SELECT subject AS id FROM old_rows
      UNION
      SELECT object AS id FROM old_rows
    ) changed;
  ELSE
    SELECT array_agg(DISTINCT id ORDER BY id)
    INTO changed_subject_ids
    FROM (
      SELECT subject AS id FROM new_rows
      UNION
      SELECT object AS id FROM new_rows
      UNION
      SELECT subject AS id FROM old_rows
      UNION
      SELECT object AS id FROM old_rows
    ) changed;
  END IF;

  subject_count := cardinality(COALESCE(changed_subject_ids, ARRAY[]::text[]));
  WHILE subject_index <= subject_count LOOP
    subject_chunk := changed_subject_ids[
      subject_index:LEAST(subject_index + 99, subject_count)
    ];
    user_ids := public.realtime_subject_recipients(subject_chunk);
    PERFORM public.emit_realtime_entity_change(
      'relationship',
      subject_chunk[1],
      lower(TG_OP),
      user_ids
    );
    subject_index := subject_index + cardinality(subject_chunk);
  END LOOP;
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_relationship_change failed without aborting write: %', SQLERRM;
    RETURN NULL;
END;
$$;
''',

  // Bulk trust maintenance must not storm the relationship fan-out. Full
  // recompute is a bookkeeping-only rewrite of prev_sent_weight (no
  // client-visible relationship moves), so it (a) suppresses the notify via
  // the transaction-local flag and (b) runs as a single set-based UPDATE
  // instead of a per-row PL/pgSQL loop. Both were previously m0088 loops that
  // fired the statement trigger once per edge.
  r'''
CREATE OR REPLACE FUNCTION public.trust_recompute_all(
  _half_life_seconds double precision
) RETURNS integer
  LANGUAGE plpgsql
  VOLATILE
  AS $$
DECLARE
  _updated integer;
BEGIN
  PERFORM set_config('tentura.suppress_relationship_notify', '1', true);
  UPDATE public.user_trust_edge SET
    prev_sent_weight = public.trust_edge_weight(
      s_very_bad, s_bad, s_no_effect, s_good, s_very_good,
      CASE
        WHEN _half_life_seconds <= 0 THEN 1
        ELSE pow(
          2,
          -greatest(EXTRACT(EPOCH FROM (now() - anchor_at)), 0) / _half_life_seconds
        )
      END
    ),
    updated_at = now();
  GET DIAGNOSTICS _updated = ROW_COUNT;
  RETURN _updated;
END;
$$;
''',
  // Single-source resync keeps its per-row loop because it pushes each edge to
  // the MeritRank engine (mr_put_edge) individually, but it is still a
  // bookkeeping resync, so it suppresses the relationship fan-out the same way.
  r'''
CREATE OR REPLACE FUNCTION public.trust_resync_source(
  _subject text,
  _half_life_seconds double precision
) RETURNS integer
  LANGUAGE plpgsql
  VOLATILE
  AS $$
DECLARE
  _r public.user_trust_edge%ROWTYPE;
  _f double precision;
  _w double precision;
  _pushed integer := 0;
BEGIN
  PERFORM set_config('tentura.suppress_relationship_notify', '1', true);
  FOR _r IN
    SELECT * FROM public.user_trust_edge WHERE subject = _subject FOR UPDATE
  LOOP
    IF _half_life_seconds <= 0 THEN
      _f := 1;
    ELSE
      _f := pow(
        2,
        -greatest(EXTRACT(EPOCH FROM (now() - _r.anchor_at)), 0) / _half_life_seconds
      );
    END IF;

    _w := public.trust_edge_weight(
      _r.s_very_bad, _r.s_bad, _r.s_no_effect, _r.s_good, _r.s_very_good, _f
    );

    PERFORM mr_put_edge(_r.subject, _r.object, _w, ''::text, 0);
    UPDATE public.user_trust_edge
    SET prev_sent_weight = _w, updated_at = now()
    WHERE subject = _r.subject AND object = _r.object;
    _pushed := _pushed + 1;
  END LOOP;

  RETURN _pushed;
END;
$$;
''',

  // Missing row-level projection sources.
  'DROP TRIGGER IF EXISTS inbox_item_entity_notify ON public.inbox_item;',
  '''
CREATE TRIGGER inbox_item_entity_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.inbox_item
  FOR EACH ROW EXECUTE FUNCTION public.notify_entity_change('inbox_item');
''',
  'DROP TRIGGER IF EXISTS user_contact_entity_notify ON public.user_contact;',
  '''
CREATE TRIGGER user_contact_entity_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.user_contact
  FOR EACH ROW EXECUTE FUNCTION public.notify_entity_change('contact');
''',
  '''
DROP TRIGGER IF EXISTS room_reaction_entity_notify
  ON public.beacon_room_message_reaction;''',
  '''
CREATE TRIGGER room_reaction_entity_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.beacon_room_message_reaction
  FOR EACH ROW EXECUTE FUNCTION public.notify_entity_change('room_reaction');
''',
  'DROP TRIGGER IF EXISTS polling_entity_notify ON public.polling;',
  '''
CREATE TRIGGER polling_entity_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.polling
  FOR EACH ROW EXECUTE FUNCTION public.notify_entity_change('room_poll');
''',
  'DROP TRIGGER IF EXISTS polling_act_entity_notify ON public.polling_act;',
  '''
CREATE TRIGGER polling_act_entity_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.polling_act
  FOR EACH ROW EXECUTE FUNCTION public.notify_entity_change('room_poll_act');
''',
  'DROP TRIGGER IF EXISTS room_seen_entity_notify ON public.beacon_room_seen;',
  '''
DROP TRIGGER IF EXISTS room_seen_update_entity_notify
  ON public.beacon_room_seen;''',
  '''
CREATE TRIGGER room_seen_entity_notify
  AFTER INSERT OR DELETE ON public.beacon_room_seen
  FOR EACH ROW EXECUTE FUNCTION public.notify_entity_change('room_seen');
''',
  '''
CREATE TRIGGER room_seen_update_entity_notify
  AFTER UPDATE ON public.beacon_room_seen
  FOR EACH ROW
  WHEN (OLD.last_seen_at IS DISTINCT FROM NEW.last_seen_at)
  EXECUTE FUNCTION public.notify_entity_change('room_seen');
''',
  'DROP TRIGGER IF EXISTS profile_entity_notify ON public."user";',
  '''
DROP TRIGGER IF EXISTS profile_update_entity_notify ON public."user";''',
  '''
CREATE TRIGGER profile_entity_notify
  AFTER INSERT OR DELETE ON public."user"
  FOR EACH ROW EXECUTE FUNCTION public.notify_entity_change('profile');
''',
  '''
CREATE TRIGGER profile_update_entity_notify
  AFTER UPDATE ON public."user"
  FOR EACH ROW
  WHEN (
    OLD.display_name IS DISTINCT FROM NEW.display_name
    OR OLD.description IS DISTINCT FROM NEW.description
    OR OLD.handle IS DISTINCT FROM NEW.handle
    OR OLD.image_id IS DISTINCT FROM NEW.image_id
  )
  EXECUTE FUNCTION public.notify_entity_change('profile');
''',
  '''
DROP TRIGGER IF EXISTS notification_outbox_entity_notify
  ON public.notification_outbox;''',
  '''
CREATE TRIGGER notification_outbox_entity_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.notification_outbox
  FOR EACH ROW EXECUTE FUNCTION public.notify_entity_change('notification');
''',

  // Relationship/trust producers: three transition-table triggers per table.
  '''
DROP TRIGGER IF EXISTS vote_user_relationship_insert_notify
  ON public.vote_user;''',
  '''
DROP TRIGGER IF EXISTS vote_user_relationship_update_notify
  ON public.vote_user;''',
  '''
DROP TRIGGER IF EXISTS vote_user_relationship_delete_notify
  ON public.vote_user;''',
  '''
CREATE TRIGGER vote_user_relationship_insert_notify
  AFTER INSERT ON public.vote_user
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION public.notify_relationship_change();
''',
  '''
CREATE TRIGGER vote_user_relationship_update_notify
  AFTER UPDATE ON public.vote_user
  REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION public.notify_relationship_change();
''',
  '''
CREATE TRIGGER vote_user_relationship_delete_notify
  AFTER DELETE ON public.vote_user
  REFERENCING OLD TABLE AS old_rows
  FOR EACH STATEMENT EXECUTE FUNCTION public.notify_relationship_change();
''',
  '''
DROP TRIGGER IF EXISTS trust_edge_relationship_insert_notify
  ON public.user_trust_edge;''',
  '''
DROP TRIGGER IF EXISTS trust_edge_relationship_update_notify
  ON public.user_trust_edge;''',
  '''
DROP TRIGGER IF EXISTS trust_edge_relationship_delete_notify
  ON public.user_trust_edge;''',
  '''
CREATE TRIGGER trust_edge_relationship_insert_notify
  AFTER INSERT ON public.user_trust_edge
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION public.notify_relationship_change();
''',
  '''
CREATE TRIGGER trust_edge_relationship_update_notify
  AFTER UPDATE ON public.user_trust_edge
  REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION public.notify_relationship_change();
''',
  '''
CREATE TRIGGER trust_edge_relationship_delete_notify
  AFTER DELETE ON public.user_trust_edge
  REFERENCING OLD TABLE AS old_rows
  FOR EACH STATEMENT EXECUTE FUNCTION public.notify_relationship_change();
''',

  // Indexes cover every new recipient/aggregate lookup. The broad subject
  // helper is deliberately capped; EXPLAIN in the PG contract test verifies
  // these indexable predicates rather than an all-row observer scan.
  '''
CREATE INDEX IF NOT EXISTS vote_user_object_amount_idx
  ON public.vote_user (object, amount);
''',
  '''
CREATE INDEX IF NOT EXISTS user_trust_edge_object_idx
  ON public.user_trust_edge (object);
''',
  '''
CREATE INDEX IF NOT EXISTS polling_act_polling_id_idx
  ON public.polling_act (polling_id);
''',
  '''
CREATE INDEX IF NOT EXISTS beacon_room_message_linked_polling_idx
  ON public.beacon_room_message (linked_polling_id)
  WHERE linked_polling_id IS NOT NULL;
''',
  '''
CREATE INDEX IF NOT EXISTS beacon_participant_user_beacon_idx
  ON public.beacon_participant (user_id, beacon_id);
''',
  '''
CREATE INDEX IF NOT EXISTS beacon_help_offer_user_beacon_idx
  ON public.beacon_help_offer (user_id, beacon_id)
  WHERE status = 0;
''',
]);
