part of '_migrations.dart';

/// Canonical deferred constellation anchor hints (#235 U15).
///
/// The row trigger that published once per row operation is replaced by
/// `DEFERRABLE INITIALLY DEFERRED` constraint triggers on the anchor and
/// cursor tables. At commit each callback reads the final cursor revision and
/// publishes one `update` envelope (id and recipient = viewer, `revision` as a
/// decimal string). A transaction-local marker keyed by (viewer, revision)
/// makes the publisher run once per viewer per transaction. A viewer whose
/// cursor row is gone (cascade delete) gets nothing.
final m0229 = Migration('0229', [
  '''
DROP TRIGGER constellation_anchor_notify_trg ON public.constellation_anchor
''',

  r'''
CREATE OR REPLACE FUNCTION public.notify_constellation_anchor_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _viewer_id text;
  _revision bigint;
  _marker_key text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    _viewer_id := OLD.viewer_id;
  ELSE
    _viewer_id := NEW.viewer_id;
  END IF;

  SELECT c.revision INTO _revision
  FROM public.constellation_anchor_cursor c
  WHERE c.viewer_id = _viewer_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  _marker_key := 'tentura.anchor_hint_' || md5(_viewer_id);
  IF current_setting(_marker_key, true) = _revision::text THEN
    RETURN NULL;
  END IF;
  PERFORM set_config(_marker_key, _revision::text, true);

  PERFORM public.emit_realtime_entity_change_strict(
    'constellation_anchor',
    _viewer_id,
    'update',
    ARRAY[_viewer_id],
    jsonb_build_object('revision', _revision::text)
  );
  RETURN NULL;
END;
$$
''',

  '''
CREATE CONSTRAINT TRIGGER constellation_anchor_notify_trg
AFTER INSERT OR UPDATE OR DELETE ON public.constellation_anchor
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.notify_constellation_anchor_change()
''',

  '''
CREATE CONSTRAINT TRIGGER constellation_anchor_cursor_notify_trg
AFTER UPDATE ON public.constellation_anchor_cursor
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.notify_constellation_anchor_change()
''',
]);
