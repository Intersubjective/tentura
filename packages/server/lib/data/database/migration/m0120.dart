part of '_migrations.dart';

/// Contracts the legacy Notification Center read model after the minimum
/// supported client has moved to the Updates-only API.
final m0120 = Migration('0120', [
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
  SET seen_at = COALESCE(n.seen_at, now())
  WHERE n.account_id = p_account_id
    AND n.beacon_id = p_beacon_id
    AND n.coordination_item_id IS NOT DISTINCT FROM p_thread_item_id
    AND n.destination_kind = 'beacon_room_message'
    AND n.seen_at IS NULL
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
  '''
CREATE UNIQUE INDEX notification_outbox__dedup_seen
  ON public.notification_outbox (dedup_key)
  WHERE seen_at IS NULL;
''',
  'DROP INDEX public.notification_outbox__dedup;',
  '''
CREATE INDEX notification_outbox__unread_seen
  ON public.notification_outbox (account_id, created_at DESC, id DESC)
  WHERE seen_at IS NULL;
''',
  'DROP INDEX public.notification_outbox__unread;',
  'ALTER INDEX public.notification_outbox__dedup_seen RENAME TO notification_outbox__dedup;',
  'ALTER INDEX public.notification_outbox__unread_seen RENAME TO notification_outbox__unread;',
]);
