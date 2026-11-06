part of '_migrations.dart';

/// Opening a Request invalidates the reader's Field in every session.
/// Keep the global aggregate id: account ids identify block changes to clients.
final m0297 = Migration('0297', [
  r'''
CREATE OR REPLACE FUNCTION public.notify_constellation_field_global() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_TABLE_NAME = 'beacon_field_seen' THEN
    PERFORM public.emit_realtime_entity_change(
      'constellation_field',
      'global',
      'update',
      ARRAY[NEW.user_id]
    );
    RETURN NULL;
  END IF;

  IF TG_TABLE_NAME = 'user_trust_edge' THEN
    IF TG_OP = 'DELETE' THEN
      IF NOT EXISTS (SELECT 1 FROM old_rows) THEN
        RETURN NULL;
      END IF;
    ELSIF NOT EXISTS (SELECT 1 FROM new_rows) THEN
      RETURN NULL;
    END IF;
  END IF;
  PERFORM pg_notify('entity_changes', jsonb_build_object(
    'event', 'update',
    'entity', 'constellation_field',
    'id', 'global',
    'user_ids', '[]'::jsonb
  )::text);
  RETURN NULL;
END;
$$
''',
  '''
CREATE TRIGGER constellation_field_seen_trg
AFTER INSERT ON public.beacon_field_seen
FOR EACH ROW EXECUTE FUNCTION public.notify_constellation_field_global()
''',
]);
