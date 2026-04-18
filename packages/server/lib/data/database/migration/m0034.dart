part of '_migrations.dart';

/// Numbered beacon author updates + invalidate watchers when posted.
///
/// - Adds column number on beacon_update (monotonic per beacon).
/// - Bumps beacon.updated_at on each insert/update to beacon_update so
///   My Work / Inbox "Updated …" lines and NewStuff treat it like a beacon change.
/// - Extends notify_entity_change for beacon so forward recipients are included
///   (author updates already reached committers via m0033).
final m0034 = Migration('0034', [
  '''
ALTER TABLE public.beacon_update
  ADD COLUMN IF NOT EXISTS number integer NOT NULL DEFAULT 0;
''',
  '''
UPDATE public.beacon_update bu
SET number = s.rn
FROM (
  SELECT id, row_number() OVER (
    PARTITION BY beacon_id ORDER BY created_at ASC
  ) AS rn
  FROM public.beacon_update
) s
WHERE bu.id = s.id AND (bu.number IS DISTINCT FROM s.rn);
''',
  '''
CREATE INDEX IF NOT EXISTS beacon_update_beacon_id_number_idx
  ON public.beacon_update (beacon_id, number);
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_entity_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  entity_type  text := TG_ARGV[0];
  entity_id    text;
  user_ids     text[];
  suppress_uid text;
BEGIN
  IF entity_type = 'beacon' THEN
    entity_id := COALESCE(NEW.id, OLD.id);
    user_ids  := ARRAY[COALESCE(NEW.user_id, OLD.user_id)];
    BEGIN
      user_ids := user_ids || coalesce((
        SELECT array_agg(DISTINCT bc.user_id)
        FROM public.beacon_commitment bc
        WHERE bc.beacon_id = entity_id AND bc.status = 0
      ), ARRAY[]::text[]);
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'notify_entity_change: beacon committer lookup failed for %: %',
          entity_id, SQLERRM;
    END;
    BEGIN
      user_ids := user_ids || coalesce((
        SELECT array_agg(DISTINCT fe.recipient_id)
        FROM public.beacon_forward_edge fe
        WHERE fe.beacon_id = entity_id
      ), ARRAY[]::text[]);
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'notify_entity_change: beacon forward recipient lookup failed for %: %',
          entity_id, SQLERRM;
    END;

  ELSIF entity_type = 'commitment' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    user_ids  := ARRAY[COALESCE(NEW.user_id, OLD.user_id)];
    BEGIN
      user_ids := user_ids || (
        SELECT ARRAY[b.user_id]
        FROM public.beacon b
        WHERE b.id = entity_id
      );
    EXCEPTION
      WHEN no_data_found THEN
        NULL;
      WHEN OTHERS THEN
        RAISE WARNING 'notify_entity_change: beacon author lookup failed for %: %',
          entity_id, SQLERRM;
    END;

  ELSIF entity_type = 'forward' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    user_ids  := ARRAY[
      COALESCE(NEW.sender_id, OLD.sender_id),
      COALESCE(NEW.recipient_id, OLD.recipient_id)
    ];
  END IF;

  suppress_uid := current_setting('tentura.mutating_user_id', true);
  IF suppress_uid IS NOT NULL AND suppress_uid <> '' THEN
    user_ids := array_remove(user_ids, suppress_uid);
  END IF;

  IF array_length(user_ids, 1) IS NULL THEN
    RETURN NULL;
  END IF;

  PERFORM pg_notify(
    'entity_changes',
    jsonb_build_object(
      'event',    lower(TG_OP),
      'entity',   entity_type,
      'id',       entity_id,
      'user_ids', to_jsonb(user_ids)
    )::text
  );
  RETURN NULL;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_beacon_update_bump_beacon()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  UPDATE public.beacon
  SET updated_at = now()
  WHERE id = NEW.beacon_id;
  RETURN NEW;
END;
$$;
''',
  '''
DROP TRIGGER IF EXISTS beacon_update_bump_beacon_updated_at ON public.beacon_update;
''',
  '''
CREATE TRIGGER beacon_update_bump_beacon_updated_at
  AFTER INSERT OR UPDATE ON public.beacon_update
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_beacon_update_bump_beacon();
''',
]);
