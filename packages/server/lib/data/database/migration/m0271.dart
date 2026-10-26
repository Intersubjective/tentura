part of '_migrations.dart';

/// Serialize authored Post writes with closure, including indirect room writes
/// and Hasura votes. UPDATE column lists omit ON DELETE SET NULL references so
/// cleanup can still run in the archive; Requests keep their existing policy.
final m0271 = Migration('0271', [
  r'''
CREATE FUNCTION public.beacon_post_write_allowed(p_beacon text, p_lock text)
RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
  write_allowed boolean;
BEGIN
  -- These locks conflict with PostLockRepository's FOR UPDATE. Read the
  -- predicate under the lock so a waiting writer sees the committed close.
  IF p_lock = 'no_key_update' THEN
    SELECT b.kind <> 1 OR
      (b.status NOT IN (2, 6) AND (b.status <> 0 OR b.expires_at > now()))
    INTO write_allowed
    FROM public.beacon b WHERE b.id = p_beacon
    FOR NO KEY UPDATE;
  ELSIF p_lock = 'key_share' THEN
    SELECT b.kind <> 1 OR
      (b.status NOT IN (2, 6) AND (b.status <> 0 OR b.expires_at > now()))
    INTO write_allowed
    FROM public.beacon b WHERE b.id = p_beacon
    FOR KEY SHARE;
  ELSE
    RAISE EXCEPTION 'invalid Post write lock: %', p_lock
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  RETURN coalesce(write_allowed, false);
END;
$$
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

  IF public.discussion_internal_fixture_allowed() THEN
    RETURN NEW;
  END IF;

  IF NOT public.beacon_post_write_allowed(NEW.beacon_id, 'no_key_update') THEN
    RAISE EXCEPTION 'post_archived' USING ERRCODE = 'check_violation';
  END IF;

  SELECT b.status
  INTO beacon_status
  FROM public.beacon b
  WHERE b.id = NEW.beacon_id AND b.kind = 0;

  IF beacon_status IN (1, 2, 6) THEN
    RAISE EXCEPTION 'discussion_read_only'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$
''',
  'DROP TRIGGER beacon_room_message_lifecycle_write_guard_trg ON public.beacon_room_message',
  '''
CREATE TRIGGER beacon_room_message_lifecycle_write_guard_trg
  BEFORE INSERT OR UPDATE OF beacon_id, body, edited_at, linked_polling_id,
    linked_next_move_id, semantic_marker, mentions, mention_spans,
    linked_event_kind, thread_item_id, system_message_kind, system_payload,
    hierarchy_notice_identity, client_message_id
  ON public.beacon_room_message
  FOR EACH ROW EXECUTE FUNCTION public.beacon_room_message_lifecycle_write_guard()
''',
  r'''
CREATE FUNCTION public.beacon_post_related_write_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  beacon_ids text[];
  beacon_id text;
  polling_id text;
  lock_kind text := 'key_share';
BEGIN
  IF public.discussion_internal_fixture_allowed() THEN
    RETURN NEW;
  END IF;

  CASE TG_TABLE_NAME
    WHEN 'beacon_room_message_reaction', 'beacon_room_message_attachment' THEN
      beacon_ids := ARRAY(
        SELECT m.beacon_id FROM public.beacon_room_message m
        WHERE m.id = NEW.message_id
      );
      IF TG_TABLE_NAME = 'beacon_room_message_reaction' THEN
        lock_kind := 'no_key_update';
      END IF;
    WHEN 'polling' THEN
      polling_id := NEW.id;
    WHEN 'polling_variant', 'polling_act' THEN
      polling_id := NEW.polling_id;
    WHEN 'beacon_room_baton' THEN
      beacon_ids := ARRAY[NEW.beacon_id];
    WHEN 'beacon_room_baton_candidate' THEN
      beacon_ids := ARRAY(
        SELECT b.beacon_id FROM public.beacon_room_baton b
        WHERE b.id = NEW.baton_id
      );
    WHEN 'vote_beacon' THEN
      beacon_ids := ARRAY[NEW.object];
  END CASE;

  IF polling_id IS NOT NULL THEN
    -- Polls are created before their message, and standalone polls have no
    -- room. If several messages reference a poll, protect every host Post.
    beacon_ids := ARRAY(
      SELECT DISTINCT m.beacon_id FROM public.beacon_room_message m
      WHERE m.linked_polling_id = polling_id ORDER BY m.beacon_id
    );
  END IF;

  FOREACH beacon_id IN ARRAY coalesce(beacon_ids, ARRAY[]::text[]) LOOP
    IF NOT public.beacon_post_write_allowed(beacon_id, lock_kind) THEN
      RAISE EXCEPTION 'post_archived' USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$
''',
  '''
CREATE TRIGGER beacon_post_write_guard
  BEFORE INSERT OR UPDATE OF message_id, user_id, emoji
  ON public.beacon_room_message_reaction
  FOR EACH ROW EXECUTE FUNCTION public.beacon_post_related_write_guard()
''',
  '''
CREATE TRIGGER beacon_post_write_guard
  BEFORE INSERT OR UPDATE OF message_id, kind, file_url, mime, size_bytes,
    width, height, position, file_name
  ON public.beacon_room_message_attachment
  FOR EACH ROW EXECUTE FUNCTION public.beacon_post_related_write_guard()
''',
  '''
CREATE TRIGGER beacon_post_write_guard
  BEFORE INSERT OR UPDATE OF author_id, question, enabled, poll_type,
    is_anonymous, allow_revote ON public.polling
  FOR EACH ROW EXECUTE FUNCTION public.beacon_post_related_write_guard()
''',
  '''
CREATE TRIGGER beacon_post_write_guard
  BEFORE INSERT OR UPDATE OF polling_id, description ON public.polling_variant
  FOR EACH ROW EXECUTE FUNCTION public.beacon_post_related_write_guard()
''',
  '''
CREATE TRIGGER beacon_post_write_guard
  BEFORE INSERT OR UPDATE OF author_id, polling_id, polling_variant_id, score
  ON public.polling_act
  FOR EACH ROW EXECUTE FUNCTION public.beacon_post_related_write_guard()
''',
  '''
CREATE TRIGGER beacon_post_write_guard
  BEFORE INSERT OR UPDATE OF message_id, beacon_id, author_id, status,
    selection_mode, all_answered_notified_at, resolved_at ON public.beacon_room_baton
  FOR EACH ROW EXECUTE FUNCTION public.beacon_post_related_write_guard()
''',
  '''
CREATE TRIGGER beacon_post_write_guard
  BEFORE INSERT OR UPDATE OF baton_id, user_id, tier, response, responded_at
  ON public.beacon_room_baton_candidate
  FOR EACH ROW EXECUTE FUNCTION public.beacon_post_related_write_guard()
''',
  '''
CREATE TRIGGER beacon_post_write_guard
  BEFORE INSERT OR UPDATE OF subject, object, amount ON public.vote_beacon
  FOR EACH ROW EXECUTE FUNCTION public.beacon_post_related_write_guard()
''',
]);
