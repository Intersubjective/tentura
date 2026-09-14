part of '_migrations.dart';

/// Discoverability mutual-visibility cache (Constellation GATE-14.1 / UNIT 04a).
final m0163a = Migration('0163a', [
  r'''
CREATE TABLE IF NOT EXISTS public.person_mutual_visibility_cache (
  person_lo        text NOT NULL,
  person_hi        text NOT NULL,
  ctx              text NOT NULL,
  is_mutually_visible boolean NOT NULL,
  mr_epoch         bigint NOT NULL,
  trust_version    bigint NOT NULL,
  computed_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (person_lo, person_hi, ctx)
);
''',
  r'''
CREATE SEQUENCE IF NOT EXISTS public.direct_trust_version_seq;
''',
  r'''
CREATE OR REPLACE FUNCTION public.direct_trust_current_version()
  RETURNS bigint LANGUAGE sql STABLE AS $$
    SELECT last_value FROM public.direct_trust_version_seq;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.bump_direct_trust_version()
  RETURNS trigger LANGUAGE plpgsql AS $$
  BEGIN
    PERFORM nextval('public.direct_trust_version_seq');
    RETURN NULL;
  END;
$$;
''',
  r'''
CREATE OR REPLACE TRIGGER vote_user_bump_direct_trust_version
  AFTER INSERT OR UPDATE OR DELETE ON public.vote_user
  FOR EACH STATEMENT EXECUTE FUNCTION public.bump_direct_trust_version();
''',
  r'''
CREATE OR REPLACE FUNCTION public.person_are_mutually_visible_cached(
  a_id text, b_id text, ctx text
) RETURNS boolean LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
  _lo text := LEAST(a_id, b_id);
  _hi text := GREATEST(a_id, b_id);
  _ctx text := coalesce(ctx, '');
  _cur_epoch bigint;
  _cur_trust bigint;
  _row public.person_mutual_visibility_cache;
  _result boolean;
BEGIN
  SELECT epoch INTO _cur_epoch FROM public.mr_publish_epoch WHERE id = true;
  _cur_trust := public.direct_trust_current_version();
  SELECT * INTO _row FROM public.person_mutual_visibility_cache c
    WHERE c.person_lo = _lo AND c.person_hi = _hi AND c.ctx = _ctx
    AND c.mr_epoch = _cur_epoch AND c.trust_version = _cur_trust
    AND c.computed_at > now() - interval '60 seconds';
  IF FOUND THEN
    RETURN _row.is_mutually_visible;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext(_lo || ':' || _hi || ':' || _ctx));
  SELECT * INTO _row FROM public.person_mutual_visibility_cache c
    WHERE c.person_lo = _lo AND c.person_hi = _hi AND c.ctx = _ctx
    AND c.mr_epoch = _cur_epoch AND c.trust_version = _cur_trust
    AND c.computed_at > now() - interval '60 seconds';
  IF FOUND THEN
    RETURN _row.is_mutually_visible;
  END IF;
  BEGIN
    _result := public.person_are_mutually_visible(a_id, b_id, _ctx);
  EXCEPTION WHEN OTHERS THEN
    RETURN false;
  END;
  INSERT INTO public.person_mutual_visibility_cache
    (person_lo, person_hi, ctx, is_mutually_visible, mr_epoch, trust_version, computed_at)
  VALUES (_lo, _hi, _ctx, _result, _cur_epoch, _cur_trust, now())
  ON CONFLICT (person_lo, person_hi, ctx) DO UPDATE SET
    is_mutually_visible = EXCLUDED.is_mutually_visible,
    mr_epoch = EXCLUDED.mr_epoch,
    trust_version = EXCLUDED.trust_version,
    computed_at = EXCLUDED.computed_at;
  RETURN _result;
END;
$$;
''',
]);
