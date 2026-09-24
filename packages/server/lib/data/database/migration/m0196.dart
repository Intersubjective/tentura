part of '_migrations.dart';

/// Adds the `room_seen_peer` realtime fan-out for General discussion seen
/// state, plus the partial index that backs its per-beacon read pattern.
///
/// The existing `room_seen` entity stays self-only (`notify_entity_change`
/// sends it to the seen user alone). This migration adds a *separate* entity,
/// `room_seen_peer`, emitted by a standalone trigger function in the
/// `notify_room_message_attachment_change()` style, so that other room
/// members (author, admitted participants, stewards) can invalidate their
/// peer read-state without waiting for the self channel.
///
/// The trigger fires `AFTER INSERT OR UPDATE OF last_seen_at` on General rows
/// only (`WHEN (NEW.thread_item_id IS NULL)`). `markBeaconRoomSeen` upserts
/// with `last_seen_at = GREATEST(...)`, and `UPDATE OF last_seen_at` fires
/// even when `GREATEST` keeps the stored value, so the function body
/// explicitly no-ops when the timestamp did not advance. The wire event is
/// always `'update'`, including for the INSERT that creates the row.
final m0196 = Migration('0196', [
  '''
CREATE INDEX beacon_room_seen_beacon_general_idx
  ON public.beacon_room_seen USING btree (beacon_id, last_seen_at DESC)
  WHERE (thread_item_id IS NULL);
''',

  r'''
CREATE FUNCTION public.notify_room_seen_peer_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  user_ids text[];
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.last_seen_at IS NOT DISTINCT FROM OLD.last_seen_at THEN
    RETURN NULL;
  END IF;

  user_ids := public.realtime_room_recipients(NEW.beacon_id) || COALESCE(
    (
      SELECT array_agg(s.user_id)
      FROM public.beacon_steward s
      WHERE s.beacon_id = NEW.beacon_id
    ),
    ARRAY[]::text[]
  );

  PERFORM public.emit_realtime_entity_change(
    'room_seen_peer',
    NEW.beacon_id,
    'update',
    user_ids,
    jsonb_build_object(
      'seen_user_id', NEW.user_id,
      'last_seen_at', NEW.last_seen_at
    )
  );
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'notify_room_seen_peer_change failed without aborting write: %',
      SQLERRM;
    RETURN NULL;
END;
$$
''',

  '''
CREATE TRIGGER room_seen_peer_notify
  AFTER INSERT OR UPDATE OF last_seen_at ON public.beacon_room_seen
  FOR EACH ROW WHEN (NEW.thread_item_id IS NULL)
  EXECUTE FUNCTION public.notify_room_seen_peer_change();
''',

  // Plan §P1.6 (measure, then decide): EXPLAIN of the
  // `bridge_attention_room_seen` UPDATE under `SET enable_seqscan = off`
  // showed both an obligation-heavy author and an optional-only helper
  // (~200 outbox rows each) falling back to `notification_outbox__feed`
  // (account_id only) and filtering beacon_id/destination_kind/seen_at
  // post-scan. No existing partial index matches
  // destination_kind='beacon_room_message' with seen_at IS NULL, so this
  // narrow partial index backs the per-watermark-advance UPDATE.
  '''
CREATE INDEX notification_outbox__room_message_unseen
  ON public.notification_outbox USING btree (account_id, beacon_id)
  WHERE destination_kind = 'beacon_room_message' AND seen_at IS NULL;
''',
]);
