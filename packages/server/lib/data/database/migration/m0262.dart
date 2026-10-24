part of '_migrations.dart';

/// Deferred `person_tag` realtime hints (#699).
///
/// `DEFERRABLE INITIALLY DEFERRED` constraint triggers on every table whose
/// rows make up an owner's tag state call one publisher at commit. It bumps
/// the owner's existing `person_tag_revision` row with a single
/// `UPDATE ... RETURNING` (never an insert or a read-back) and publishes one
/// `update` envelope per owner per transaction: id and only recipient = owner,
/// `revision` as a decimal string, never a tag name or glyph. A
/// transaction-local marker keyed by owner makes the publisher run once per
/// owner. An owner whose revision row is gone (erased owner, cascade delete)
/// gets nothing and the commit still succeeds; erasing a tagged person bumps
/// and notifies each surviving owner once.
final m0262 = Migration('0262', [
  r'''
CREATE FUNCTION public.notify_person_tag_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _owner_id text;
  _revision bigint;
  _marker_key text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    _owner_id := OLD.owner_id;
  ELSE
    _owner_id := NEW.owner_id;
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

  for (final table in const [
    'person_tag',
    'person_tag_member',
    'person_auto_tag_pref',
    'person_tag_suggestion_state',
  ])
    '''
CREATE CONSTRAINT TRIGGER ${table}_notify_trg
AFTER INSERT OR UPDATE OR DELETE ON public.$table
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.notify_person_tag_change()
''',
]);
