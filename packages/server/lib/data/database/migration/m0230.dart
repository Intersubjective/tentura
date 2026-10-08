part of '_migrations.dart';

/// Frozen visibility memo (#235 U46).
///
/// A transaction that sets `tentura_visibility.frozen` to `on` (constellation
/// read and apply transactions) keeps the first visible-set computation per
/// (viewer, context) for its remainder, whatever trust other connections
/// commit meanwhile. Without the flag the memo is still invalidated by every
/// stamp change. Trust-mutating transactions never set the flag. The
/// fail-closed empty set is memoised like any other result.
final m0230 = Migration('0230', [
  r'''
CREATE OR REPLACE FUNCTION public.person_visible_peer_ids_tx(viewer_id text, ctx text) RETURNS text[]
    LANGUAGE plpgsql
    COST 500
    AS $$
DECLARE
  _v text := nullif(trim(coalesce(viewer_id, '')), '');
  _ctx text := coalesce(ctx, '');
  _key text;
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
  _stamp := coalesce((SELECT epoch FROM public.mr_publish_epoch WHERE id = true), 0)
    || ':' || public.direct_trust_current_version() || ':';
  IF _memo IS NOT NULL AND starts_with(_memo, _stamp) THEN
    RETURN substr(_memo, length(_stamp) + 1)::text[];
  END IF;
  BEGIN
    SELECT coalesce(array_agg(s.peer_id ORDER BY s.peer_id), '{}'::text[])
    INTO _ids
    FROM public.person_visible_peers_symmetric(_v, _ctx) s;
  EXCEPTION WHEN OTHERS THEN
    -- MeritRank unavailable: fail closed for the rest of this transaction
    -- instead of retrying (and timing out) once per row.
    _ids := '{}'::text[];
  END;
  PERFORM set_config(_key, _stamp || _ids::text, true);
  RETURN _ids;
END;
$$
''',
]);
