part of '_migrations.dart';

/// Adds the People-tab read watermark `beacon_people_seen` (issue #178 plan
/// P1.1), its attention bridge, and the `people_seen` realtime fan-out.
///
/// Writers upsert with `last_seen_at = GREATEST(...)`; `UPDATE OF
/// last_seen_at` fires even when `GREATEST` keeps the stored value, so the
/// trigger function no-ops when the timestamp did not advance.
///
/// `bridge_attention_people_seen` marks the writer's own
/// `help_offer_submitted` receipts seen up to the watermark. It runs outside
/// the fan-out's EXCEPTION block so bridge failures abort the write, while a
/// failed fan-out only raises a warning. The `people_seen` payload carries
/// `last_seen_at` only (no `seen_user_id`) and goes to active offerers of the
/// request, minus the writer.
final m0198 = Migration('0198', [
  '''
CREATE TABLE public.beacon_people_seen (
    user_id text NOT NULL
      REFERENCES public."user"(id) ON DELETE CASCADE,
    beacon_id text NOT NULL
      REFERENCES public.beacon(id) ON DELETE CASCADE,
    last_seen_at timestamp with time zone NOT NULL,
    PRIMARY KEY (user_id, beacon_id)
);
''',

  '''
CREATE INDEX beacon_people_seen_beacon_idx
  ON public.beacon_people_seen USING btree (beacon_id);
''',

  '''
COMMENT ON TABLE public.beacon_people_seen IS
  'Per-user People-tab read watermark for a request (beacon).';
''',

  r'''
CREATE FUNCTION public.bridge_attention_people_seen(p_account_id text, p_beacon_id text, p_last_seen_at timestamp with time zone) RETURNS integer
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  updated_count integer;
BEGIN
  UPDATE public.notification_outbox n
  SET seen_at = COALESCE(n.seen_at, now())
  WHERE n.account_id = p_account_id
    AND n.beacon_id = p_beacon_id
    AND n.destination_kind = 'beacon_people_offer'
    AND n.presentation_key = 'help_offer_submitted'
    AND n.created_at <= p_last_seen_at
    AND n.seen_at IS NULL;

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$
''',

  r'''
CREATE FUNCTION public.notify_people_seen_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  user_ids text[];
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.last_seen_at IS NOT DISTINCT FROM OLD.last_seen_at THEN
    RETURN NULL;
  END IF;

  PERFORM public.bridge_attention_people_seen(
    NEW.user_id,
    NEW.beacon_id,
    NEW.last_seen_at
  );

  BEGIN
    SELECT COALESCE(array_agg(o.user_id), ARRAY[]::text[])
    INTO user_ids
    FROM public.beacon_help_offer o
    WHERE o.beacon_id = NEW.beacon_id
      AND o.status = 0
      AND o.user_id <> NEW.user_id;

    PERFORM public.emit_realtime_entity_change(
      'people_seen',
      NEW.beacon_id,
      'update',
      user_ids,
      jsonb_build_object('last_seen_at', NEW.last_seen_at)
    );
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING
        'notify_people_seen_change fan-out failed without aborting write: %',
        SQLERRM;
  END;
  RETURN NULL;
END;
$$
''',

  '''
CREATE TRIGGER beacon_people_seen_notify
  AFTER INSERT OR UPDATE OF last_seen_at ON public.beacon_people_seen
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_people_seen_change();
''',
]);
