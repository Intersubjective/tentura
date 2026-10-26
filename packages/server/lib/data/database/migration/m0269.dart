part of '_migrations.dart';

/// Post lifetime (post-ttl S1): `beacon.expires_at` and
/// `beacon.expiry_warning_eligible`.
///
/// Open Posts are backfilled to 72 hours after publication, with a 24 hour
/// grace from the migration for those already past it. A defaulting trigger
/// gives every Post that becomes open without an `expires_at` the same 72 hour
/// lifetime, so inserts that predate this column keep working. The CHECK ties
/// `expires_at` to Posts, and requires it while a Post is open; it has no
/// upper bound, because grace rows exceed `published_at + 72h`.
final m0269 = Migration('0269', [
  '''
ALTER TABLE public.beacon ADD COLUMN expires_at timestamp with time zone, ADD COLUMN expiry_warning_eligible boolean DEFAULT false NOT NULL
''',
  '''
UPDATE public.beacon SET expires_at = greatest(coalesce(published_at, created_at) + interval '72 hours', now() + interval '24 hours'), expiry_warning_eligible = true WHERE kind = 1 AND status = 0
''',
  '''
ALTER TABLE public.beacon
    ADD CONSTRAINT beacon_post_expires_at_ck CHECK (((kind = 1) OR (expires_at IS NULL)) AND ((kind <> 1) OR (status <> 0) OR (expires_at IS NOT NULL)))
''',
  r'''
CREATE FUNCTION public.beacon_post_expires_at_default() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.kind = 1 AND NEW.status = 0 AND NEW.expires_at IS NULL THEN
    NEW.expires_at := coalesce(NEW.published_at, now()) + interval '72 hours';
    NEW.expiry_warning_eligible := true;
  END IF;
  RETURN NEW;
END
$$
''',
  '''
CREATE TRIGGER beacon_a_post_expires_at_default_trg BEFORE INSERT OR UPDATE OF status ON public.beacon FOR EACH ROW EXECUTE FUNCTION public.beacon_post_expires_at_default()
''',
  '''
CREATE INDEX beacon_open_post_expires_at_idx ON public.beacon USING btree (expires_at) WHERE ((kind = 1) AND (status = 0))
''',
]);
