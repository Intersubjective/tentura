part of '_migrations.dart';

/// Installs the single authorization/preference relation used by attention
/// reads and bulk acknowledgement, plus the directed-room watermark bridge.
final m0117 = Migration('0117', [
  r'''
CREATE OR REPLACE FUNCTION public.visible_attention_receipts(
  p_account_id text
) RETURNS TABLE(receipt_id text, tombstone_copy boolean)
  LANGUAGE sql
  STABLE
  SECURITY INVOKER
  SET search_path = public, pg_temp
  AS $$
WITH candidates AS (
  SELECT
    n.*,
    CASE
      WHEN n.beacon_id IS NULL THEN false
      ELSE public.beacon_can_read_content(n.beacon_id, p_account_id)
    END AS can_read_content,
    CASE
      WHEN n.beacon_id IS NULL THEN false
      ELSE public.beacon_can_read_tombstone(n.beacon_id, p_account_id)
    END AS can_read_tombstone
  FROM public.notification_outbox n
  WHERE n.account_id = p_account_id
)
SELECT
  c.id,
  c.beacon_id IS NOT NULL
    AND NOT c.can_read_content
    AND c.can_read_tombstone AS tombstone_copy
FROM candidates c
WHERE
  CASE c.access_policy
    WHEN 'legacy' THEN
      c.beacon_id IS NULL OR c.can_read_content OR c.can_read_tombstone
    WHEN 'beacon_content' THEN c.can_read_content
    WHEN 'beacon_tombstone' THEN c.can_read_tombstone
    WHEN 'recipient_safe' THEN
      c.presentation_key IN (
        'room_member_removed', 'offer_declined', 'offer_removed'
      )
      AND c.destination_kind = 'safe_terminal'
    WHEN 'profile' THEN
      c.beacon_id IS NULL
      AND c.presentation_key IN (
        'mutual_connection_formed', 'invite_accepted'
      )
      AND c.destination_kind = 'profile'
    ELSE false
  END
  AND (
    c.suppression_class <> 'noisy'
    OR c.in_app_preference_class IS NULL
    OR NOT EXISTS (
      SELECT 1
      FROM public.notification_preference np
      WHERE np.account_id = p_account_id
        AND c.in_app_preference_class = ANY(
          np.muted_in_app_event_classes
        )
    )
  );
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.bridge_attention_room_seen(
  p_account_id text,
  p_beacon_id text,
  p_thread_item_id text,
  p_last_seen_at timestamptz
) RETURNS integer
  LANGUAGE plpgsql
  SECURITY INVOKER
  SET search_path = public, pg_temp
  AS $$
DECLARE
  updated_count integer;
BEGIN
  UPDATE public.notification_outbox n
  SET
    seen_at = COALESCE(n.seen_at, n.read_at, now()),
    read_at = COALESCE(n.read_at, n.seen_at, now())
  WHERE n.account_id = p_account_id
    AND n.beacon_id = p_beacon_id
    AND n.coordination_item_id IS NOT DISTINCT FROM p_thread_item_id
    AND n.destination_kind = 'beacon_room_message'
    AND (n.seen_at IS NULL OR n.read_at IS NULL)
    AND EXISTS (
      SELECT 1
      FROM public.beacon_room_message message
      WHERE message.id = n.target_entity_id
        AND message.beacon_id = p_beacon_id
        AND message.thread_item_id IS NOT DISTINCT FROM p_thread_item_id
        AND message.created_at <= p_last_seen_at
    );

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.bridge_attention_room_seen_trigger()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY INVOKER
  SET search_path = public, pg_temp
  AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.last_seen_at > OLD.last_seen_at THEN
    PERFORM public.bridge_attention_room_seen(
      NEW.user_id,
      NEW.beacon_id,
      NEW.thread_item_id,
      NEW.last_seen_at
    );
  END IF;
  RETURN NULL;
END;
$$;
''',
  '''
DROP TRIGGER IF EXISTS beacon_room_seen_attention_bridge
  ON public.beacon_room_seen;
''',
  '''
CREATE TRIGGER beacon_room_seen_attention_bridge
  AFTER INSERT OR UPDATE OF last_seen_at ON public.beacon_room_seen
  FOR EACH ROW
  EXECUTE FUNCTION public.bridge_attention_room_seen_trigger();
''',
]);
