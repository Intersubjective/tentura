part of '_migrations.dart';

/// Constellation field hint producers (#235 U17).
///
/// Trust changes and MR publication emit ONE payload-free global
/// `constellation_field` marker per statement (no per-viewer enumeration;
/// coalescing and broadcast bounding belong to the fan-out). A block change
/// addresses both parties. The upsert path of `user_trust_edge` fires both the
/// insert and the update statement trigger, so each only emits when its
/// transition table is non-empty.
final m0232 = Migration('0232', [
  r'''
CREATE FUNCTION public.notify_constellation_field_global() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
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

  r'''
CREATE FUNCTION public.notify_constellation_field_block() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _row public.user_block := CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
BEGIN
  PERFORM public.emit_realtime_entity_change(
    'constellation_field',
    _row.blocker_id,
    'update',
    ARRAY[_row.blocker_id, _row.blocked_id]
  );
  RETURN NULL;
END;
$$
''',

  '''
CREATE TRIGGER constellation_field_trust_insert_trg
AFTER INSERT ON public.user_trust_edge
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION public.notify_constellation_field_global()
''',

  '''
CREATE TRIGGER constellation_field_trust_update_trg
AFTER UPDATE ON public.user_trust_edge
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION public.notify_constellation_field_global()
''',

  '''
CREATE TRIGGER constellation_field_trust_delete_trg
AFTER DELETE ON public.user_trust_edge
REFERENCING OLD TABLE AS old_rows
FOR EACH STATEMENT EXECUTE FUNCTION public.notify_constellation_field_global()
''',

  '''
CREATE TRIGGER constellation_field_mr_epoch_trg
AFTER UPDATE ON public.mr_publish_epoch
FOR EACH STATEMENT EXECUTE FUNCTION public.notify_constellation_field_global()
''',

  '''
CREATE TRIGGER constellation_field_block_trg
AFTER INSERT OR DELETE ON public.user_block
FOR EACH ROW EXECUTE FUNCTION public.notify_constellation_field_block()
''',
]);
