part of '_migrations.dart';

/// Realtime invalidation when author coordination response changes.
///
/// [beacon_commitment_coordination] had no trigger; only [beacon_commitment]
/// and [beacon] fired NOTIFY. Committers did not receive updates when the
/// author changed response type. This emits the same `commitment` payload
/// shape as [notify_entity_change] for the commitment branch.
final m0032 = Migration('0032', [
  r'''
CREATE OR REPLACE FUNCTION public.notify_coordination_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  entity_id    text;
  user_ids     text[];
  suppress_uid text;
BEGIN
  entity_id := COALESCE(NEW.commit_beacon_id, OLD.commit_beacon_id);
  user_ids := ARRAY[
    COALESCE(NEW.commit_user_id, OLD.commit_user_id),
    COALESCE(NEW.author_user_id, OLD.author_user_id)
  ];
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
      RAISE WARNING 'notify_coordination_change: beacon author lookup failed for %: %',
        entity_id, SQLERRM;
  END;

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
      'entity',   'commitment',
      'id',       entity_id,
      'user_ids', to_jsonb(user_ids)
    )::text
  );
  RETURN NULL;
END;
$$;
''',
  r'''
CREATE TRIGGER coordination_entity_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.beacon_commitment_coordination
  FOR EACH ROW EXECUTE FUNCTION public.notify_coordination_change();
''',
]);
