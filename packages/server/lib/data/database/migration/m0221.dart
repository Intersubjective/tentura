part of '_migrations.dart';

/// Inbox Hasura reads (`InboxFetch`, `ActivityOffersHydrate`, …) evaluate
/// `beacon_can_read_content` → `person_are_mutually_visible_cached` once per
/// author. That helper took a blocking `pg_advisory_xact_lock` per person-pair
/// and held every lock until commit. Two concurrent inbox queries that walked
/// authors in different orders (ORDER BY latest_forward_at vs unordered
/// hydrate) deadlocked (40P01); Hasura surfaced it as `database query error`
/// (Sentry TENTURA-CLIENT-32).
///
/// Switch to `pg_try_advisory_xact_lock`: if another txn already holds the
/// pair lock, compute without writing the cache. `ON CONFLICT` still covers
/// the same-pair race when both win the try-lock window.
final m0221 = Migration('0221', [
  r'''
CREATE OR REPLACE FUNCTION public.person_are_mutually_visible_cached(a_id text, b_id text, ctx text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
#variable_conflict use_column
DECLARE
  _lo text := LEAST(a_id, b_id);
  _hi text := GREATEST(a_id, b_id);
  _ctx text := coalesce(ctx, '');
  _cur_epoch bigint;
  _cur_trust bigint;
  _row public.person_mutual_visibility_cache;
  _result boolean;
  _got_lock boolean;
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
  IF current_setting('transaction_read_only', true) = 'on' THEN
    BEGIN
      _result := public.person_are_mutually_visible(a_id, b_id, _ctx);
    EXCEPTION WHEN OTHERS THEN
      RETURN false;
    END;
    RETURN _result;
  END IF;
  _got_lock := pg_try_advisory_xact_lock(hashtext(_lo || ':' || _hi || ':' || _ctx));
  IF NOT _got_lock THEN
    BEGIN
      _result := public.person_are_mutually_visible(a_id, b_id, _ctx);
    EXCEPTION WHEN OTHERS THEN
      RETURN false;
    END;
    RETURN _result;
  END IF;
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
$$
''',
  '''
COMMENT ON FUNCTION public.person_are_mutually_visible_cached(text, text, text) IS
  'Cached mutual-visibility (m0163a). Pair lock is try-only since m0221 so concurrent Hasura inbox reads cannot 40P01 on crossed author order.';
''',
]);
