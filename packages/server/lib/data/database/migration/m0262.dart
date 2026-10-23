part of '_migrations.dart';

/// PROVISIONAL NUMBER (lane FR, 2026-10-23): renumber at merge if another
/// lane lands m0259–m0262 first.
///
/// Field item hint producer (#671). A Request that becomes discoverable —
/// published, `is_discoverable`, kind Request — emits ONE
/// `constellation_item` hint (id = the beacon id, event `insert`) to its
/// author's direct contacts: everyone who trusts the author or whom the
/// author trusts (explicit `vote_user`, amount > 0), minus anyone with a block
/// either way. Their open field then reads just that Request through the
/// authorized `constellationFieldRequests` query; the hint carries no content
/// and grants nothing. Bounded: one indexed lookup per transition (both
/// `vote_user` directions are indexed), at most 1000 recipients; later edits
/// of an already discoverable Request emit nothing. Second-degree viewers
/// (the author is visible to them only through MeritRank) are not addressed
/// here and stay on the lazy FULL.
final m0262 = Migration('0262', [
  r'''
CREATE FUNCTION public.notify_constellation_item_discoverable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _recipients text[];
BEGIN
  IF NEW.kind <> 0
     OR NEW.published_at IS NULL
     OR NOT NEW.is_discoverable THEN
    RETURN NULL;
  END IF;
  IF TG_OP = 'UPDATE'
     AND OLD.kind = 0
     AND OLD.published_at IS NOT NULL
     AND OLD.is_discoverable THEN
    RETURN NULL;
  END IF;
  SELECT COALESCE(array_agg(c.id ORDER BY c.id), ARRAY[]::text[])
  INTO _recipients
  FROM (
    SELECT contacts.id
    FROM (
      SELECT vu.subject AS id
      FROM public.vote_user vu
      WHERE vu.object = NEW.user_id AND vu.amount > 0
      UNION
      SELECT vu.object AS id
      FROM public.vote_user vu
      WHERE vu.subject = NEW.user_id AND vu.amount > 0
    ) contacts
    WHERE contacts.id <> NEW.user_id
      AND NOT public.block_hides(contacts.id, NEW.user_id)
    ORDER BY contacts.id
    LIMIT 1000
  ) c;
  PERFORM public.emit_realtime_entity_change(
    'constellation_item',
    NEW.id,
    'insert',
    _recipients
  );
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_constellation_item_discoverable failed without aborting write: %', SQLERRM;
    RETURN NULL;
END;
$$
''',

  '''
CREATE TRIGGER constellation_item_discoverable_trg
AFTER INSERT OR UPDATE OF published_at, is_discoverable, kind ON public.beacon
FOR EACH ROW EXECUTE FUNCTION public.notify_constellation_item_discoverable()
''',
]);
