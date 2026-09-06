part of '_migrations.dart';

/// General-only persistence protection and lifecycle write-guard DB backstop
/// (Task 07). Dormant-mechanics PG tests bypass non-General scope via
/// `SET LOCAL tentura.discussion_internal_fixture = 'allow_non_general'`.
final m0156 = Migration('0156', [
  r'''
CREATE OR REPLACE FUNCTION public.discussion_internal_fixture_allowed()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT current_setting('tentura.discussion_internal_fixture', true)
  = 'allow_non_general';
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_room_message_general_only_guard()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.thread_item_id IS DISTINCT FROM OLD.thread_item_id THEN
    IF NEW.thread_item_id IS NOT NULL
      AND NOT public.discussion_internal_fixture_allowed() THEN
      RAISE EXCEPTION 'discussion_scope_disabled'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
''',
  r'''
DROP TRIGGER IF EXISTS beacon_room_message_general_only_guard_trg
  ON public.beacon_room_message;
''',
  r'''
CREATE TRIGGER beacon_room_message_general_only_guard_trg
  BEFORE INSERT OR UPDATE ON public.beacon_room_message
  FOR EACH ROW
  EXECUTE FUNCTION public.beacon_room_message_general_only_guard();
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_room_message_lifecycle_write_guard()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  beacon_status smallint;
BEGIN
  IF NEW.system_message_kind IS NOT NULL OR NEW.author_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT b.status
  INTO beacon_status
  FROM public.beacon b
  WHERE b.id = NEW.beacon_id;

  IF beacon_status IN (1, 2, 6) THEN
    RAISE EXCEPTION 'discussion_read_only'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;
''',
  r'''
DROP TRIGGER IF EXISTS beacon_room_message_lifecycle_write_guard_trg
  ON public.beacon_room_message;
''',
  r'''
CREATE TRIGGER beacon_room_message_lifecycle_write_guard_trg
  BEFORE INSERT OR UPDATE ON public.beacon_room_message
  FOR EACH ROW
  EXECUTE FUNCTION public.beacon_room_message_lifecycle_write_guard();
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_room_seen_general_only_guard()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF NEW.thread_item_id IS NOT NULL
    AND NOT public.discussion_internal_fixture_allowed() THEN
    RAISE EXCEPTION 'discussion_scope_disabled'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
''',
  r'''
DROP TRIGGER IF EXISTS beacon_room_seen_general_only_guard_trg
  ON public.beacon_room_seen;
''',
  r'''
CREATE TRIGGER beacon_room_seen_general_only_guard_trg
  BEFORE INSERT OR UPDATE ON public.beacon_room_seen
  FOR EACH ROW
  EXECUTE FUNCTION public.beacon_room_seen_general_only_guard();
''',
  r'''
CREATE OR REPLACE FUNCTION public.polling_room_general_visible(
  p_polling_id text,
  p_viewer_id text
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT CASE
  WHEN NOT EXISTS (
    SELECT 1
    FROM public.beacon_room_message m
    WHERE m.linked_polling_id = p_polling_id
  ) THEN true
  ELSE EXISTS (
    SELECT 1
    FROM public.beacon_room_message m
    WHERE m.linked_polling_id = p_polling_id
      AND m.thread_item_id IS NULL
      AND public.beacon_effective_admission(m.beacon_id, p_viewer_id)
  )
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.polling_get_room_general_visible(
  polling_row public.polling,
  hasura_session json
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT public.polling_room_general_visible(
  polling_row.id,
  hasura_session ->> 'x-hasura-user-id'
);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_room_state_general_visible(
  state_row public.beacon_room_state,
  hasura_session json
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT public.beacon_effective_admission(
  state_row.beacon_id,
  hasura_session ->> 'x-hasura-user-id'
);
$$;
''',
]);
