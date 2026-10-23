part of '_migrations.dart';

/// Field item hint producer (#671). A Request that becomes discoverable —
/// published, `is_discoverable`, kind Request — emits ONE
/// `constellation_item` hint (id = the beacon id, event `insert`) to the
/// people whose field has the author as a direct contact (#246): everyone who
/// explicitly trusts the author (`vote_user`, amount > 0), minus anyone with a
/// block either way. Someone only the author trusts is not addressed: they
/// chose no relation to the author, so they are not told the author published.
/// Their open field then reads just that Request through the authorized
/// `constellationFieldRequests` query; the hint carries no content and grants
/// nothing (it does tell those people, by an opaque id, that the author
/// published something findable). Bounded: one indexed lookup per transition
/// (`vote_user_object_amount_idx`), at most 1000 recipients; later edits of an
/// already discoverable Request emit nothing. Second-degree viewers (the
/// author is visible to them only through MeritRank) are not addressed here
/// and stay on the lazy FULL.
final m0259 = Migration('0259', [
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
    SELECT vu.subject AS id
    FROM public.vote_user vu
    WHERE vu.object = NEW.user_id
      AND vu.amount > 0
      AND vu.subject <> NEW.user_id
      AND NOT public.block_hides(vu.subject, NEW.user_id)
    ORDER BY vu.subject
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
