part of '_migrations.dart';

/// Prompt-state invalidation: recipient-targeted, transaction-aborting.
final m0165 = Migration('0165', [
  r'''
CREATE OR REPLACE FUNCTION public.emit_realtime_entity_change_strict(
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
    RAISE EXCEPTION
      'emit_realtime_entity_change_strict: invalid envelope for kind %',
      COALESCE(p_entity, '<null>');
  END IF;

  SELECT COALESCE(array_agg(DISTINCT user_id ORDER BY user_id), ARRAY[]::text[])
  INTO normalized_user_ids
  FROM unnest(COALESCE(p_user_ids, ARRAY[]::text[])) AS user_id
  WHERE user_id IS NOT NULL AND user_id <> '';

  IF cardinality(normalized_user_ids) = 0 THEN
    RAISE EXCEPTION
      'emit_realtime_entity_change_strict: empty recipients for kind %',
      p_entity;
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
        RAISE EXCEPTION
          'emit_realtime_entity_change_strict: payload exceeded byte budget for kind %',
          p_entity;
      END IF;
      take_count := GREATEST(1, take_count / 2);
    END LOOP;

    PERFORM pg_notify('entity_changes', payload);
    recipient_index := recipient_index + take_count;
  END LOOP;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_invite_seed_prompt_state_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.state IS NOT DISTINCT FROM NEW.state THEN
      RETURN NEW;
    END IF;
    PERFORM public.emit_realtime_entity_change_strict(
      'invite_seed_prompt',
      NEW.invitee_user_id,
      'update',
      ARRAY[NEW.inviter_user_id]
    );
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;
''',
  r'''
CREATE TRIGGER invite_seed_prompt_state_notify
  AFTER UPDATE ON public.invite_seed_prompt_state
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_invite_seed_prompt_state_change();
''',
]);
