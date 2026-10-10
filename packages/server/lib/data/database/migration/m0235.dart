part of '_migrations.dart';

/// Cross-request visible-set cache (#235 U48, ARCH §7.4a).
///
/// `person_visible_set_cache` keeps one visible set per (viewer, context),
/// stamped with the MR publish epoch and the trust generation it was computed
/// under. `visibility_trust_generation` is a single counter row bumped, in the
/// writing transaction, by every statement that changes trust or blocks, so a
/// reader's snapshot sees exactly the generation of the data it reads and a
/// rolled-back change leaves no bump. A stored set is served only when both
/// stamps equal the snapshot's; a set computed from a MeritRank failure (the
/// fail-closed empty fallback) is never stored, and a fill never replaces a
/// row of a newer stamp. A fill that cannot write (read-only transaction,
/// serialization conflict) is skipped: the read stays correct, just uncached.
final m0235 = Migration('0235', [
  '''
CREATE TABLE public.visibility_trust_generation (
    id boolean DEFAULT true NOT NULL PRIMARY KEY,
    generation bigint DEFAULT 0 NOT NULL,
    CONSTRAINT visibility_trust_generation_id_check CHECK (id)
)
''',

  'INSERT INTO public.visibility_trust_generation (id, generation) VALUES (true, 0)',

  r'''
CREATE FUNCTION public.bump_visibility_trust_generation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE public.visibility_trust_generation SET generation = generation + 1 WHERE id = true;
  RETURN NULL;
END;
$$
''',

  '''
CREATE TRIGGER visibility_trust_generation_vote_user_trg
AFTER INSERT OR UPDATE OR DELETE ON public.vote_user
FOR EACH STATEMENT EXECUTE FUNCTION public.bump_visibility_trust_generation()
''',

  '''
CREATE TRIGGER visibility_trust_generation_trust_edge_trg
AFTER INSERT OR UPDATE OR DELETE ON public.user_trust_edge
FOR EACH STATEMENT EXECUTE FUNCTION public.bump_visibility_trust_generation()
''',

  '''
CREATE TRIGGER visibility_trust_generation_user_block_trg
AFTER INSERT OR UPDATE OR DELETE ON public.user_block
FOR EACH STATEMENT EXECUTE FUNCTION public.bump_visibility_trust_generation()
''',

  '''
CREATE TABLE public.person_visible_set_cache (
    viewer_id text NOT NULL,
    ctx text NOT NULL,
    mr_epoch bigint NOT NULL,
    trust_gen bigint NOT NULL,
    peer_ids text[] NOT NULL,
    computed_at timestamp with time zone DEFAULT now() NOT NULL,
    PRIMARY KEY (viewer_id, ctx)
)
''',

  r'''
CREATE OR REPLACE FUNCTION public.person_visible_peer_ids_tx(viewer_id text, ctx text) RETURNS text[]
    LANGUAGE plpgsql
    COST 500
    AS $$
DECLARE
  _v text := nullif(trim(coalesce(viewer_id, '')), '');
  _ctx text := coalesce(ctx, '');
  _key text;
  _epoch bigint;
  _gen bigint;
  _stamp text;
  _memo text;
  _ids text[];
BEGIN
  IF _v IS NULL THEN
    RETURN '{}'::text[];
  END IF;
  _key := 'tentura_visibility.p' || md5(_v || chr(31) || _ctx);
  _memo := current_setting(_key, true);
  IF _memo IS NOT NULL AND _memo <> ''
     AND current_setting('tentura_visibility.frozen', true) = 'on' THEN
    RETURN regexp_replace(_memo, '^[^:]*:[^:]*:', '')::text[];
  END IF;
  _epoch := coalesce((SELECT epoch FROM public.mr_publish_epoch WHERE id = true), 0);
  _stamp := _epoch || ':' || public.direct_trust_current_version() || ':';
  IF _memo IS NOT NULL AND starts_with(_memo, _stamp) THEN
    RETURN substr(_memo, length(_stamp) + 1)::text[];
  END IF;
  _gen := (SELECT g.generation FROM public.visibility_trust_generation g WHERE g.id = true);
  SELECT c.peer_ids INTO _ids
  FROM public.person_visible_set_cache c
  WHERE c.viewer_id = _v AND c.ctx = _ctx AND c.mr_epoch = _epoch AND c.trust_gen = _gen;
  IF FOUND THEN
    PERFORM set_config(_key, _stamp || _ids::text, true);
    RETURN _ids;
  END IF;
  BEGIN
    SELECT coalesce(array_agg(s.peer_id ORDER BY s.peer_id), '{}'::text[])
    INTO _ids
    FROM public.person_visible_peers_symmetric(_v, _ctx) s;
  EXCEPTION WHEN OTHERS THEN
    -- MeritRank unavailable: fail closed for the rest of this transaction
    -- instead of retrying (and timing out) once per row. Never stored.
    _ids := '{}'::text[];
    PERFORM set_config(_key, _stamp || _ids::text, true);
    RETURN _ids;
  END;
  BEGIN
    INSERT INTO public.person_visible_set_cache AS c (viewer_id, ctx, mr_epoch, trust_gen, peer_ids)
    VALUES (_v, _ctx, _epoch, _gen, _ids)
    ON CONFLICT ON CONSTRAINT person_visible_set_cache_pkey DO UPDATE
    SET mr_epoch = EXCLUDED.mr_epoch,
        trust_gen = EXCLUDED.trust_gen,
        peer_ids = EXCLUDED.peer_ids,
        computed_at = now()
    WHERE (c.mr_epoch, c.trust_gen) < (EXCLUDED.mr_epoch, EXCLUDED.trust_gen);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  PERFORM set_config(_key, _stamp || _ids::text, true);
  RETURN _ids;
END;
$$
''',
]);
