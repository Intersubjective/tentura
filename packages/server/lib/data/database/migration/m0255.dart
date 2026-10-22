part of '_migrations.dart';

/// Request **Questions** realtime hints reach only the Questions audience
/// (follow-up to m0254, lane 4 codex finding).
///
/// Before: the generic General publishers (`notify_entity_change` for
/// `room_message` / `room_reaction`, `notify_room_message_attachment_change`)
/// fanned out every row, Questions rows included, to the General room
/// recipients. People removed from Questions (`beacon_lobby_ban`), people
/// blocked with the message author and everyone else outside the Questions
/// audience therefore still got a bare hint (Request id + message id) that a
/// Questions message, reaction or attachment exists.
///
/// After:
/// - The generic triggers skip Questions rows through a `WHEN` clause (the
///   trigger functions themselves are untouched, so every non-Questions row
///   is published byte-for-byte as before). A General row
///   (`thread_item_id IS NULL`) never reaches the lookup.
/// - The Questions publishers send all three event kinds to
///   `questions_hint_recipients`: the whole Questions audience (General
///   recipients included, since they no longer get the General hint) minus
///   anyone blocked with the message author.
/// - Fail closed on the edges the API never takes: an UPDATE that moves a
///   row into or out of Questions goes through the Questions path only; the
///   Questions item deletes its messages BEFORE it goes (the FK cascade would
///   otherwise run after the item is gone, when nothing can classify them);
///   and a Questions message can never link a poll (the `room_poll`
///   publisher resolves its Request through the message and sends to the
///   General room).
final m0255 = Migration('0255', [
  // True when the thread scope is the Request's own Questions item (kind 7).
  r'''
CREATE FUNCTION public.realtime_is_questions_thread(p_beacon_id text, p_thread_item_id text)
RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT p_thread_item_id IS NOT NULL AND EXISTS (
  SELECT 1 FROM public.coordination_item ci
  WHERE ci.id = p_thread_item_id
    AND ci.beacon_id = p_beacon_id
    AND ci.kind = 7
)
$$
''',
  // True when the message is a Questions message (reactions, attachments).
  r'''
CREATE FUNCTION public.realtime_is_questions_message(p_message_id text)
RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
  SELECT 1
  FROM public.beacon_room_message m
  JOIN public.coordination_item ci
    ON ci.id = m.thread_item_id
   AND ci.beacon_id = m.beacon_id
   AND ci.kind = 7
  WHERE m.id = p_message_id
)
$$
''',
  // Everyone who may get a hint about a Questions message by [p_author_id]:
  // the Questions audience minus people blocked with the author either way.
  r'''
CREATE FUNCTION public.questions_hint_recipients(p_beacon_id text, p_author_id text)
RETURNS text[]
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT COALESCE(array_agg(a.user_id), ARRAY[]::text[])
FROM public.questions_audience(p_beacon_id) a
WHERE p_author_id IS NULL
   OR NOT public.block_hides(p_author_id, a.user_id)
$$
''',

  // --- Generic General path: skip Questions rows. ---------------------------
  // An UPDATE is skipped when the row is a Questions row before OR after
  // (a move into or out of Questions is published to the audience only).
  '''
DROP TRIGGER beacon_room_message_notify ON public.beacon_room_message
''',
  '''
CREATE TRIGGER beacon_room_message_notify_ins
  AFTER INSERT ON public.beacon_room_message
  FOR EACH ROW WHEN (
    NEW.thread_item_id IS NULL
    OR NOT public.realtime_is_questions_thread(NEW.beacon_id, NEW.thread_item_id)
  )
  EXECUTE FUNCTION public.notify_entity_change('room_message')
''',
  '''
CREATE TRIGGER beacon_room_message_notify_upd
  AFTER UPDATE ON public.beacon_room_message
  FOR EACH ROW WHEN (
    (OLD.thread_item_id IS NULL AND NEW.thread_item_id IS NULL)
    OR NOT (
      public.realtime_is_questions_thread(OLD.beacon_id, OLD.thread_item_id)
      OR public.realtime_is_questions_thread(NEW.beacon_id, NEW.thread_item_id)
    )
  )
  EXECUTE FUNCTION public.notify_entity_change('room_message')
''',
  '''
CREATE TRIGGER beacon_room_message_notify_del
  AFTER DELETE ON public.beacon_room_message
  FOR EACH ROW WHEN (
    OLD.thread_item_id IS NULL
    OR NOT public.realtime_is_questions_thread(OLD.beacon_id, OLD.thread_item_id)
  )
  EXECUTE FUNCTION public.notify_entity_change('room_message')
''',
  '''
DROP TRIGGER room_reaction_entity_notify ON public.beacon_room_message_reaction
''',
  '''
CREATE TRIGGER room_reaction_entity_notify_ins
  AFTER INSERT ON public.beacon_room_message_reaction
  FOR EACH ROW WHEN (NOT public.realtime_is_questions_message(NEW.message_id))
  EXECUTE FUNCTION public.notify_entity_change('room_reaction')
''',
  '''
CREATE TRIGGER room_reaction_entity_notify_upd
  AFTER UPDATE ON public.beacon_room_message_reaction
  FOR EACH ROW WHEN (NOT (
    public.realtime_is_questions_message(OLD.message_id)
    OR public.realtime_is_questions_message(NEW.message_id)
  ))
  EXECUTE FUNCTION public.notify_entity_change('room_reaction')
''',
  '''
CREATE TRIGGER room_reaction_entity_notify_del
  AFTER DELETE ON public.beacon_room_message_reaction
  FOR EACH ROW WHEN (NOT public.realtime_is_questions_message(OLD.message_id))
  EXECUTE FUNCTION public.notify_entity_change('room_reaction')
''',
  '''
DROP TRIGGER beacon_room_message_attachment_notify ON public.beacon_room_message_attachment
''',
  '''
CREATE TRIGGER beacon_room_message_attachment_notify_ins
  AFTER INSERT ON public.beacon_room_message_attachment
  FOR EACH ROW WHEN (NOT public.realtime_is_questions_message(NEW.message_id))
  EXECUTE FUNCTION public.notify_room_message_attachment_change()
''',
  '''
CREATE TRIGGER beacon_room_message_attachment_notify_upd
  AFTER UPDATE ON public.beacon_room_message_attachment
  FOR EACH ROW WHEN (NOT (
    public.realtime_is_questions_message(OLD.message_id)
    OR public.realtime_is_questions_message(NEW.message_id)
  ))
  EXECUTE FUNCTION public.notify_room_message_attachment_change()
''',
  '''
CREATE TRIGGER beacon_room_message_attachment_notify_del
  AFTER DELETE ON public.beacon_room_message_attachment
  FOR EACH ROW WHEN (NOT public.realtime_is_questions_message(OLD.message_id))
  EXECUTE FUNCTION public.notify_room_message_attachment_change()
''',

  // --- Questions path: all three event kinds, audience only. ----------------
  // Same wire kinds and envelopes as the General path; the websocket layer
  // paints no thread text (bare hint) and clients refetch through the gated
  // API. Now the only producer for Questions rows, so General recipients are
  // no longer excluded.
  r'''
CREATE OR REPLACE FUNCTION public.notify_questions_message_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_beacon_id text := COALESCE(NEW.beacon_id, OLD.beacon_id);
  v_thread_item_id text := COALESCE(NEW.thread_item_id, OLD.thread_item_id);
BEGIN
  IF NOT public.realtime_is_questions_thread(v_beacon_id, v_thread_item_id) THEN
    RETURN NULL;
  END IF;
  PERFORM public.emit_realtime_entity_change(
    'room_message',
    v_beacon_id,
    lower(TG_OP),
    public.questions_hint_recipients(
      v_beacon_id, COALESCE(NEW.author_id, OLD.author_id)
    ),
    jsonb_build_object('message_id', COALESCE(NEW.id, OLD.id))
  );
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_questions_message_change failed without aborting write: %', SQLERRM;
    RETURN NULL;
END;
$$
''',
  // Reaction hint: the General `room_reaction` envelope (Request id only).
  r'''
CREATE FUNCTION public.notify_questions_reaction_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  r record;
BEGIN
  -- Both parents on an UPDATE (a reaction moved between messages).
  FOR r IN
    SELECT DISTINCT m.beacon_id, m.author_id
    FROM public.beacon_room_message m
    JOIN public.coordination_item ci
      ON ci.id = m.thread_item_id
     AND ci.beacon_id = m.beacon_id
     AND ci.kind = 7
    WHERE m.id IN (NEW.message_id, OLD.message_id)
  LOOP
    PERFORM public.emit_realtime_entity_change(
      'room_reaction',
      r.beacon_id,
      lower(TG_OP),
      public.questions_hint_recipients(r.beacon_id, r.author_id),
      '{}'::jsonb
    );
  END LOOP;
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_questions_reaction_change failed without aborting write: %', SQLERRM;
    RETURN NULL;
END;
$$
''',
  '''
CREATE TRIGGER beacon_room_message_reaction_questions_notify
  AFTER INSERT OR DELETE OR UPDATE ON public.beacon_room_message_reaction
  FOR EACH ROW EXECUTE FUNCTION public.notify_questions_reaction_change()
''',
  // Attachment hint: the General attachment envelope (`room_message` update
  // with the message id). The API refuses attachments in Questions today;
  // this keeps any row that does exist off the General fan-out.
  r'''
CREATE FUNCTION public.notify_questions_attachment_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  r record;
BEGIN
  -- Both parents on an UPDATE (an attachment moved between messages).
  FOR r IN
    SELECT m.id, m.beacon_id, m.author_id
    FROM public.beacon_room_message m
    JOIN public.coordination_item ci
      ON ci.id = m.thread_item_id
     AND ci.beacon_id = m.beacon_id
     AND ci.kind = 7
    WHERE m.id IN (NEW.message_id, OLD.message_id)
  LOOP
    PERFORM public.emit_realtime_entity_change(
      'room_message',
      r.beacon_id,
      'update',
      public.questions_hint_recipients(r.beacon_id, r.author_id),
      jsonb_build_object('message_id', r.id)
    );
  END LOOP;
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_questions_attachment_change failed without aborting write: %', SQLERRM;
    RETURN NULL;
END;
$$
''',
  '''
CREATE TRIGGER beacon_room_message_attachment_questions_notify
  AFTER INSERT OR DELETE OR UPDATE ON public.beacon_room_message_attachment
  FOR EACH ROW EXECUTE FUNCTION public.notify_questions_attachment_change()
''',
  // The Questions item takes its messages with it BEFORE it goes, so their
  // DELETE hints are still classified as Questions (the FK cascade runs
  // after the item row is gone). Reactions and attachments cascade from the
  // messages while those rows still point at the item.
  r'''
CREATE FUNCTION public.questions_item_delete_messages_first() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM public.beacon_room_message m
  WHERE m.thread_item_id = OLD.id;
  RETURN OLD;
END;
$$
''',
  '''
CREATE TRIGGER coordination_item_questions_delete_messages_first
  BEFORE DELETE ON public.coordination_item
  FOR EACH ROW WHEN (OLD.kind = 7)
  EXECUTE FUNCTION public.questions_item_delete_messages_first()
''',
  // Polls are General-only: the `room_poll` publisher resolves the Request
  // through the poll's message and sends to the General room.
  r'''
CREATE FUNCTION public.reject_questions_message_poll() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF public.realtime_is_questions_thread(NEW.beacon_id, NEW.thread_item_id) THEN
    RAISE EXCEPTION 'discussion_scope_disabled'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$
''',
  '''
CREATE TRIGGER beacon_room_message_questions_poll_guard
  BEFORE INSERT OR UPDATE OF linked_polling_id, thread_item_id
  ON public.beacon_room_message
  FOR EACH ROW WHEN (
    NEW.linked_polling_id IS NOT NULL AND NEW.thread_item_id IS NOT NULL
  )
  EXECUTE FUNCTION public.reject_questions_message_poll()
''',
]);
