part of '_migrations.dart';

/// Tag magnets on the Field (people tags E9a): `constellation_tag_magnet`.
///
/// One `(x, y)` per viewer and own tag. The composite foreign key keeps a
/// magnet under its viewer's own tag only, and both it and the viewer cascade,
/// so deleting a tag or erasing the viewer needs no code. The V2 API is the
/// only reader and writer, so Hasura never tracks the table. Changes publish
/// the viewer's `person_tag` hint through a deferred constraint trigger that
/// shares the once-per-transaction marker of `notify_person_tag_change`
/// (m0262): a magnet change together with a tag change is announced once.
final m0268 = Migration('0268', [
  '''
CREATE TABLE public.constellation_tag_magnet (
  viewer_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  tag_id text NOT NULL,
  x_units double precision NOT NULL,
  y_units double precision NOT NULL,
  revision bigint NOT NULL DEFAULT 1,
  PRIMARY KEY (viewer_id, tag_id),
  FOREIGN KEY (tag_id, viewer_id)
    REFERENCES public.person_tag (id, owner_id) ON DELETE CASCADE
)
''',
  r'''
CREATE FUNCTION public.notify_constellation_tag_magnet_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _owner_id text;
  _revision bigint;
  _marker_key text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    _owner_id := OLD.viewer_id;
  ELSE
    _owner_id := NEW.viewer_id;
  END IF;

  _marker_key := 'tentura.person_tag_hint_' || md5(_owner_id);
  IF current_setting(_marker_key, true) = 'done' THEN
    RETURN NULL;
  END IF;

  UPDATE public.person_tag_revision
  SET revision = revision + 1
  WHERE owner_id = _owner_id
  RETURNING revision INTO _revision;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  PERFORM set_config(_marker_key, 'done', true);

  PERFORM public.emit_realtime_entity_change_strict(
    'person_tag',
    _owner_id,
    'update',
    ARRAY[_owner_id],
    jsonb_build_object('revision', _revision::text)
  );
  RETURN NULL;
END;
$$
''',
  '''
CREATE CONSTRAINT TRIGGER constellation_tag_magnet_notify_trg
AFTER INSERT OR UPDATE OR DELETE ON public.constellation_tag_magnet
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.notify_constellation_tag_magnet_change()
''',
]);
