part of '_migrations.dart';

/// Entity-change notifications via Postgres LISTEN/NOTIFY.
///
/// Adds a generic trigger function `notify_entity_change` and attaches it to
/// `beacon`, `beacon_commitment`, and `beacon_forward_edge` so that the V2
/// server can fan out lightweight invalidation signals over the existing
/// WebSocket to affected clients.
final m0027 = Migration('0027', [
  r'''
CREATE OR REPLACE FUNCTION public.notify_entity_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  entity_type text := TG_ARGV[0];
  entity_id   text;
  user_ids    text[];
BEGIN
  IF entity_type = 'beacon' THEN
    entity_id := COALESCE(NEW.id, OLD.id);
    user_ids  := ARRAY[COALESCE(NEW.user_id, OLD.user_id)];

  ELSIF entity_type = 'commitment' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    user_ids  := ARRAY[COALESCE(NEW.user_id, OLD.user_id)];
    -- Include the beacon author so they see commitment changes.
    BEGIN
      user_ids := user_ids || (
        SELECT ARRAY[b.user_id]
        FROM public.beacon b
        WHERE b.id = entity_id
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

  ELSIF entity_type = 'forward' THEN
    entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    user_ids  := ARRAY[
      COALESCE(NEW.sender_id, OLD.sender_id),
      COALESCE(NEW.recipient_id, OLD.recipient_id)
    ];
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
  '''
CREATE TRIGGER beacon_entity_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.beacon
  FOR EACH ROW EXECUTE FUNCTION public.notify_entity_change('beacon');
''',
  '''
CREATE TRIGGER commitment_entity_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.beacon_commitment
  FOR EACH ROW EXECUTE FUNCTION public.notify_entity_change('commitment');
''',
  '''
CREATE TRIGGER forward_entity_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.beacon_forward_edge
  FOR EACH ROW EXECUTE FUNCTION public.notify_entity_change('forward');
''',
]);
