part of '_migrations.dart';

/// Remove former Post members completely, including their personal room and
/// attention state. Repair only Requests marked as converted from a Post.
final m0224 = Migration('0224', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_participant_removal_cleanup()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM public.beacon_room_seen
  WHERE beacon_id = OLD.beacon_id AND user_id = OLD.user_id;
  DELETE FROM public.inbox_item
  WHERE beacon_id = OLD.beacon_id AND user_id = OLD.user_id;
  DELETE FROM public.attention_request_state
  WHERE beacon_id = OLD.beacon_id AND account_id = OLD.user_id;
  UPDATE public.notification_outbox
  SET cleared_at = now(), clear_reason = 'sweep'
  WHERE beacon_id = OLD.beacon_id AND account_id = OLD.user_id
    AND NOT requires_action AND cleared_at IS NULL;
  UPDATE public.notification_outbox
  SET settlement_kind = 'superseded', settled_at = now(),
      settled_by_user_id = NULL, settled_by_occurrence_id = NULL
  WHERE beacon_id = OLD.beacon_id AND account_id = OLD.user_id
    AND requires_action AND settlement_kind IS NULL;
  RETURN OLD;
END;
$$
''',
  '''
DROP TRIGGER IF EXISTS beacon_participant_removal_cleanup_trg
ON public.beacon_participant
''',
  '''
CREATE TRIGGER beacon_participant_removal_cleanup_trg
AFTER DELETE ON public.beacon_participant
FOR EACH ROW EXECUTE FUNCTION public.beacon_participant_removal_cleanup()
''',
  '''
DELETE FROM public.beacon_participant p
USING public.beacon b
WHERE p.beacon_id = b.id AND p.role = 6 AND b.kind = 0
  AND EXISTS (
    SELECT 1 FROM public.beacon_room_message m
    WHERE m.beacon_id = b.id AND m.system_message_kind = 4
  )
''',
]);
