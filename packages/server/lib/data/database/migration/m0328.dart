part of '_migrations.dart';

/// Account erasure invalidations use the affected rows' recipients, including
/// when the authored Request becomes a tombstone or its draft is removed.
final m0328 = Migration('0328', [
  r'''
CREATE FUNCTION public.notify_erased_request_dependents(
  p_beacon_id text, p_erased_id text, p_include_forwards boolean
) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  hint record;
BEGIN
  FOR hint IN
    SELECT entity, array_agg(user_id) AS user_ids
    FROM (
      SELECT 'participant' AS entity, user_id
      FROM public.beacon_participant WHERE beacon_id = p_beacon_id
      UNION ALL
      SELECT 'inbox_item', user_id
      FROM public.inbox_item WHERE beacon_id = p_beacon_id
      UNION ALL
      SELECT 'forward', recipient_id
      FROM public.beacon_forward_edge
      WHERE p_include_forwards AND beacon_id = p_beacon_id
    ) AS affected
    WHERE user_id <> p_erased_id
    GROUP BY entity
  LOOP
    PERFORM public.emit_realtime_entity_change(
      hint.entity, p_beacon_id, 'delete', hint.user_ids
    );
  END LOOP;
END;
$$
''',
  r'''
CREATE FUNCTION public.notify_request_author_erasure() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  -- The tombstone retains room and inbox records. Invalidate their former
  -- live views. Edges sent by the erased owner have their own delete trigger.
  PERFORM public.notify_erased_request_dependents(OLD.id, OLD.user_id, false);
  RETURN NULL;
END;
$$
''',
  '''
CREATE TRIGGER request_author_erasure_notify
AFTER UPDATE OF user_id ON public.beacon
FOR EACH ROW
WHEN (OLD.kind = 0 AND OLD.user_id IS NOT NULL
      AND NEW.user_id IS NULL AND NEW.status = 2)
EXECUTE FUNCTION public.notify_request_author_erasure()
''',
  r'''
CREATE FUNCTION public.notify_participant_user_erasure() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public."user" WHERE id = OLD.user_id) THEN
    PERFORM public.emit_realtime_entity_change(
      'participant', OLD.beacon_id, 'delete',
      ARRAY(SELECT user_id FROM public.beacon WHERE id = OLD.beacon_id)
    );
  END IF;
  RETURN NULL;
END;
$$
''',
  '''
CREATE TRIGGER beacon_participant_user_erasure_notify
AFTER DELETE ON public.beacon_participant
FOR EACH ROW EXECUTE FUNCTION public.notify_participant_user_erasure()
''',
  r'''
CREATE FUNCTION public.notify_forward_delete() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  user_ids text[];
BEGIN
  user_ids := ARRAY(
    SELECT id FROM public."user" WHERE id IN (OLD.sender_id, OLD.recipient_id)
  );
  IF OLD.sender_id = ANY(user_ids) AND OLD.recipient_id = ANY(user_ids) THEN
    -- Ordinary forward deletes retain the existing Request audience.
    user_ids := public.realtime_beacon_recipients(OLD.beacon_id) || user_ids;
  END IF;
  PERFORM public.emit_realtime_entity_change(
    'forward', OLD.beacon_id, 'delete', user_ids
  );
  RETURN NULL;
END;
$$
''',
  'DROP TRIGGER forward_entity_notify ON public.beacon_forward_edge',
  '''
CREATE TRIGGER forward_entity_notify
AFTER INSERT OR UPDATE ON public.beacon_forward_edge
FOR EACH ROW EXECUTE FUNCTION public.notify_entity_change('forward')
''',
  '''
CREATE TRIGGER forward_entity_delete_notify
AFTER DELETE ON public.beacon_forward_edge
FOR EACH ROW EXECUTE FUNCTION public.notify_forward_delete()
''',
]);
