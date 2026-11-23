part of '_migrations.dart';

/// One private invalidation per surviving owner and committed transaction.
final m0334 = Migration('0334', [
  r'''
CREATE FUNCTION public.notify_phantom_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _owner_id text;
  _marker_key text;
BEGIN
  _owner_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.owner_id ELSE NEW.owner_id END;
  _marker_key := 'tentura.phantom_hint_' || md5(_owner_id);
  IF current_setting(_marker_key, true) = 'done'
     OR NOT EXISTS (SELECT 1 FROM public."user" WHERE id = _owner_id) THEN
    RETURN NULL;
  END IF;
  PERFORM set_config(_marker_key, 'done', true);

  PERFORM public.emit_realtime_entity_change_strict(
    'phantom', _owner_id, 'update', ARRAY[_owner_id]
  );
  RETURN NULL;
END;
$$
''',
  '''
CREATE CONSTRAINT TRIGGER phantom_notify_trg
AFTER INSERT OR UPDATE OR DELETE ON public.phantom
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.notify_phantom_change()
''',
]);
