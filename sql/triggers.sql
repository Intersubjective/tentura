-- Triggers and trigger functions for MeritRank + app logic
-- Extracted from packages/server migrations m0002, m0003, m0005.
-- Prerequisites: mr_put_edge(), mr_delete_edge(); mr_set_new_edges_filter() optional (behind flag, unimplemented/WIP)
-- (e.g. from MeritRank/Hasura schema). Tables public.beacon,
-- vote_beacon, vote_user, "user", user_vsids, invitation, message,
-- polling, polling_variant, polling_act, user_updates must exist.
--
-- Usage: psql -U postgres -d your_db -f sql/triggers.sql

-- Helper used by updated_at triggers
CREATE OR REPLACE FUNCTION public.set_current_timestamp_updated_at()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;

-- NOTE: notify_meritrank_vote_user_mutation trigger dropped in migration m0088.
-- User→user MeritRank edges are published from the effective projection
-- (user_trust_edge) via trust_rebuild_effective_edge; legacy trust_apply_evidence,
-- meritrank_sweep, and trust_recompute_all were dropped in m0122.
-- (vote_user notify function body kept below for reference; do not re-attach.)

-- Trigger functions (before_insert / vsids)
CREATE OR REPLACE FUNCTION public.notify_meritrank_vote_user_mutation()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
    PERFORM mr_put_edge(
      NEW.subject,
      NEW.object,
      (NEW.amount)::double precision,
      ''::text, NEW.ticker
    );
    RETURN NEW;

  ELSIF (TG_OP = 'DELETE') THEN
    PERFORM mr_delete_edge(
      OLD.subject,
      OLD.object,
      ''::text
    );
    RETURN OLD;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.on_user_created()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  INSERT INTO user_vsids
    VALUES (NEW.id, DEFAULT, DEFAULT);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.vote_user_before_insert()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  UPDATE user_vsids SET counter = counter + 1
    WHERE user_id = NEW.subject
    RETURNING counter INTO NEW.ticker;
  RETURN NEW;
END;
$$;

-- Triggers
DROP TRIGGER IF EXISTS notify_meritrank_vote_user_mutation ON public.vote_user;

CREATE OR REPLACE TRIGGER set_public_user_updated_at
  BEFORE UPDATE ON public."user"
  FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE OR REPLACE TRIGGER on_user_created
  AFTER INSERT ON public."user"
  FOR EACH ROW EXECUTE FUNCTION public.on_user_created();

CREATE OR REPLACE TRIGGER public_vote_user_before_insert
  BEFORE INSERT ON public.vote_user
  FOR EACH ROW EXECUTE FUNCTION public.vote_user_before_insert();

CREATE OR REPLACE TRIGGER set_public_beacon_updated_at
  BEFORE UPDATE ON public.beacon
  FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE OR REPLACE TRIGGER set_public_invitation_updated_at
  BEFORE UPDATE ON public.invitation
  FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE OR REPLACE TRIGGER set_public_message_updated_at
  BEFORE UPDATE ON public.message
  FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE OR REPLACE TRIGGER set_public_user_vsids_updated_at
  BEFORE UPDATE ON public.user_vsids
  FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE OR REPLACE TRIGGER set_public_vote_beacon_updated_at
  BEFORE UPDATE ON public.vote_beacon
  FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE OR REPLACE TRIGGER set_public_vote_user_updated_at
  BEFORE UPDATE ON public.vote_user
  FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();

-- Trust-edge weight (single source of truth for Dirichlet posterior mean).
-- Inflated accumulators s_* are deflated by factor _f before applying Laplace prior.
-- Overflow: 2^(age/H) reaches Inf only after ~1024 half-lives (~510 years at H=182d); no rescale guard.
CREATE OR REPLACE FUNCTION public.trust_edge_weight(
  _s_very_bad double precision,
  _s_bad double precision,
  _s_no_effect double precision,
  _s_good double precision,
  _s_very_good double precision,
  _f double precision
) RETURNS double precision
  LANGUAGE sql
  IMMUTABLE
  AS $$
  SELECT (_f * (-5 * _s_very_bad - _s_bad + _s_good + 5 * _s_very_good))
       / (5 + _f * (_s_very_bad + _s_bad + _s_no_effect + _s_good + _s_very_good));
$$;

-- Typed trust source graphs (m0122) — reference tables (see migration m0122).
-- user_trust_edge remains the effective projection; source accumulators live
-- in user_trust_source_edge. Policy is frozen in trust_policy / trust_context_config.

CREATE TABLE IF NOT EXISTS public.user_trust_source_edge (
  trust_context text NOT NULL CHECK (
    trust_context IN ('personal','commitment','forward','legacy')),
  subject text NOT NULL REFERENCES public."user"(id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  object text NOT NULL REFERENCES public."user"(id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  s_very_bad double precision NOT NULL DEFAULT 0,
  s_bad double precision NOT NULL DEFAULT 0,
  s_no_effect double precision NOT NULL DEFAULT 0,
  s_good double precision NOT NULL DEFAULT 0,
  s_very_good double precision NOT NULL DEFAULT 0,
  anchor_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (trust_context, subject, object)
);

CREATE TABLE IF NOT EXISTS public.trust_policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  half_life_seconds double precision NOT NULL
    CHECK (half_life_seconds >= 86400 AND half_life_seconds <= 3.2e9),
  epsilon double precision NOT NULL CHECK (epsilon >= 0 AND epsilon <= 1),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.trust_context_config (
  trust_context text PRIMARY KEY CHECK (
    trust_context IN ('personal','commitment','forward','legacy')),
  evidence_multiplier double precision NOT NULL
    CHECK (evidence_multiplier >= 0 AND evidence_multiplier <= 100),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.trust_evidence_event (
  id text PRIMARY KEY DEFAULT concat('T', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)),
  trust_context text NOT NULL CHECK (
    trust_context IN ('personal','commitment','forward')),
  subject_user_id text NOT NULL,
  object_user_id text NOT NULL,
  bin text NOT NULL CHECK (bin IN ('very_bad','bad','no_effect','good','very_good')),
  count double precision NOT NULL CHECK (count >= 0 AND count <= 1e6),
  source_type text NOT NULL CHECK (source_type IN (
    'user_vote','finalized_request_evaluation',
    'propagated_author_evaluated_commitment',
    'negative_commitment_route_no_effect',
    'unsuccessful_request_forward')),
  source_id text,
  request_id text,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  applied_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS public.forward_decision_attribution (
  child_forward_batch_id text NOT NULL,
  parent_forward_edge_id text NOT NULL
    REFERENCES public.beacon_forward_edge(id) ON UPDATE CASCADE ON DELETE CASCADE,
  attribution_weight double precision NOT NULL
    CHECK (attribution_weight > 0 AND attribution_weight <= 1),
  attribution_method text NOT NULL CHECK (attribution_method IN
    ('explicit_single','explicit_multiple','opened_via')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (child_forward_batch_id, parent_forward_edge_id)
);

CREATE TABLE IF NOT EXISTS public.meritrank_edge_tombstone (
  subject text NOT NULL,
  object text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_error text,
  PRIMARY KEY (subject, object)
);

CREATE OR REPLACE FUNCTION public.trust_pair_lock(_subject text, _object text)
RETURNS void LANGUAGE sql VOLATILE AS $$
  SELECT pg_advisory_xact_lock(hashtextextended(_subject || chr(31) || _object, 4242));
$$;

CREATE OR REPLACE FUNCTION public.trust_apply_source_evidence(
  _context text,
  _subject text,
  _object text,
  _bin text,
  _count double precision
) RETURNS void
  LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  _r public.user_trust_source_edge%ROWTYPE;
  _hl double precision;
  _f_inflate double precision;
  _bump double precision;
BEGIN
  IF _context = 'legacy' THEN
    RAISE EXCEPTION 'trust_apply_source_evidence: legacy is migration-only';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.trust_context_config WHERE trust_context = _context
  ) THEN
    RAISE EXCEPTION 'trust_apply_source_evidence: unknown context %', _context;
  END IF;
  IF _count IS NULL OR NOT (_count >= 0 AND _count <= 1e6) THEN
    RAISE EXCEPTION 'trust_apply_source_evidence: invalid count %', _count;
  END IF;

  PERFORM public.trust_pair_lock(_subject, _object);

  SELECT half_life_seconds INTO STRICT _hl FROM public.trust_policy;

  INSERT INTO public.user_trust_source_edge (trust_context, subject, object, anchor_at)
  VALUES (_context, _subject, _object, now())
  ON CONFLICT (trust_context, subject, object) DO UPDATE SET updated_at = now()
  RETURNING * INTO _r;

  _f_inflate := pow(2,
    greatest(EXTRACT(EPOCH FROM (now() - _r.anchor_at)), 0) / _hl);
  _bump := _count * _f_inflate;

  UPDATE public.user_trust_source_edge SET
    s_very_bad  = s_very_bad  + CASE WHEN _bin = 'very_bad'  THEN _bump ELSE 0 END,
    s_bad       = s_bad       + CASE WHEN _bin = 'bad'       THEN _bump ELSE 0 END,
    s_no_effect = s_no_effect + CASE WHEN _bin = 'no_effect' THEN _bump ELSE 0 END,
    s_good      = s_good      + CASE WHEN _bin = 'good'      THEN _bump ELSE 0 END,
    s_very_good = s_very_good + CASE WHEN _bin = 'very_good' THEN _bump ELSE 0 END,
    updated_at = now()
  WHERE trust_context = _context AND subject = _subject AND object = _object;
END; $$;

CREATE OR REPLACE FUNCTION public.trust_rebuild_effective_edge(
  _subject text,
  _object text,
  _epsilon_override double precision DEFAULT NULL
) RETURNS double precision
  LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  _now timestamptz := now();
  _hl double precision;
  _eps double precision;
  _vb float8; _b float8; _ne float8; _g float8; _vg float8;
  _prev float8;
  _w float8;
BEGIN
  PERFORM public.trust_pair_lock(_subject, _object);

  SELECT half_life_seconds, epsilon INTO STRICT _hl, _eps FROM public.trust_policy;
  _eps := COALESCE(_epsilon_override, _eps);

  SELECT
    COALESCE(sum(c.evidence_multiplier * e.s_very_bad  * d.f), 0),
    COALESCE(sum(c.evidence_multiplier * e.s_bad       * d.f), 0),
    COALESCE(sum(c.evidence_multiplier * e.s_no_effect * d.f), 0),
    COALESCE(sum(c.evidence_multiplier * e.s_good      * d.f), 0),
    COALESCE(sum(c.evidence_multiplier * e.s_very_good * d.f), 0)
  INTO _vb, _b, _ne, _g, _vg
  FROM public.user_trust_source_edge e
  JOIN public.trust_context_config c
    ON c.trust_context = e.trust_context AND c.evidence_multiplier > 0
  CROSS JOIN LATERAL (
    SELECT pow(2, -greatest(EXTRACT(EPOCH FROM (_now - e.anchor_at)), 0) / _hl) AS f
  ) d
  WHERE e.subject = _subject AND e.object = _object;

  _w := public.trust_edge_weight(_vb, _b, _ne, _g, _vg, 1);

  SELECT prev_sent_weight INTO _prev FROM public.user_trust_edge
  WHERE subject = _subject AND object = _object;
  _prev := COALESCE(_prev, 0);

  INSERT INTO public.user_trust_edge
    (subject, object, s_very_bad, s_bad, s_no_effect,
     s_good, s_very_good, anchor_at, prev_sent_weight)
  VALUES (_subject, _object, _vb, _b, _ne, _g, _vg, _now, _prev)
  ON CONFLICT (subject, object) DO UPDATE SET
    s_very_bad = EXCLUDED.s_very_bad, s_bad = EXCLUDED.s_bad,
    s_no_effect = EXCLUDED.s_no_effect, s_good = EXCLUDED.s_good,
    s_very_good = EXCLUDED.s_very_good, anchor_at = EXCLUDED.anchor_at,
    updated_at = now();

  IF abs(_w - _prev) > _eps THEN
    BEGIN
      PERFORM mr_put_edge(_subject, _object, _w, ''::text, 0);
      UPDATE public.user_trust_edge SET prev_sent_weight = _w, updated_at = now()
      WHERE subject = _subject AND object = _object;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'trust_rebuild_effective_edge: publish %->% deferred: %',
        _subject, _object, SQLERRM;
    END;
  END IF;

  RETURN _w;
END; $$;

CREATE OR REPLACE FUNCTION public.trust_rebuild_effective_batch(
  _after_subject text,
  _after_object text,
  _limit integer,
  _epsilon_override double precision DEFAULT NULL
) RETURNS TABLE (last_subject text, last_object text, processed integer)
  LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  _pair record;
  _n integer := 0;
  _ls text := NULL; _lo text := NULL;
BEGIN
  IF _limit IS NULL OR _limit < 1 OR _limit > 10000 THEN
    RAISE EXCEPTION 'trust_rebuild_effective_batch: invalid limit %', _limit;
  END IF;
  PERFORM set_config('tentura.suppress_relationship_notify', '1', true);

  FOR _pair IN
    SELECT subject, object FROM (
      SELECT subject, object FROM public.user_trust_source_edge
      UNION
      SELECT subject, object FROM public.user_trust_edge
    ) p
    WHERE (subject, object) > (_after_subject, _after_object)
    ORDER BY subject, object
    LIMIT _limit
  LOOP
    PERFORM public.trust_rebuild_effective_edge(
      _pair.subject, _pair.object, _epsilon_override);
    _n := _n + 1;
    _ls := _pair.subject; _lo := _pair.object;
  END LOOP;

  RETURN QUERY SELECT _ls, _lo, _n;
END; $$;

CREATE OR REPLACE FUNCTION public.trust_resync_source(_subject text)
RETURNS integer
  LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  _pair record;
  _n integer := 0;
BEGIN
  PERFORM set_config('tentura.suppress_relationship_notify', '1', true);
  FOR _pair IN
    SELECT DISTINCT object FROM public.user_trust_source_edge
    WHERE subject = _subject
    ORDER BY object
  LOOP
    PERFORM public.trust_rebuild_effective_edge(_subject, _pair.object, -1);
    _n := _n + 1;
  END LOOP;
  RETURN _n;
END; $$;

CREATE OR REPLACE FUNCTION public.trust_edge_on_effective_delete()
  RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    PERFORM mr_delete_edge(OLD.subject, OLD.object, ''::text);
    DELETE FROM public.meritrank_edge_tombstone
    WHERE subject = OLD.subject AND object = OLD.object;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.meritrank_edge_tombstone (subject, object, last_error)
    VALUES (OLD.subject, OLD.object, left(SQLERRM, 500))
    ON CONFLICT (subject, object)
      DO UPDATE SET last_error = EXCLUDED.last_error;
    RAISE WARNING 'trust_edge_on_effective_delete %->%: % (tombstoned)',
      OLD.subject, OLD.object, SQLERRM;
  END;
  RETURN NULL;
END; $$;

CREATE OR REPLACE TRIGGER trust_edge_effective_delete_mr
  AFTER DELETE ON public.user_trust_edge
  FOR EACH ROW
  WHEN (OLD.prev_sent_weight <> 0)
  EXECUTE FUNCTION public.trust_edge_on_effective_delete();

-- meritrank_init(): backfill MeritRank from existing data (call via SELECT meritrank_init();)
-- Uses mr_bulk_load_edges for a single RPC instead of many mr_put_edge calls.
-- Unimplemented/WIP: new-edges filter behind _meritrank_new_edges_enabled (default false).
CREATE OR REPLACE FUNCTION public.meritrank_init()
  RETURNS integer
  LANGUAGE plpgsql
  STABLE
  AS $$
DECLARE
  -- Unimplemented/WIP: new-edges filter feature disabled; Meritrank service no longer supports
  -- mr_set_new_edges_filter / mr_fetch_new_edges / mr_get_new_edges_filter. Set to true when reimplemented.
  _meritrank_new_edges_enabled constant boolean := false;
  _src text[];
  _dst text[];
  _weight float8[];
  _magnitude bigint[];
  _context text[];
  _total integer := 0;
  _edge_count integer;
BEGIN
  WITH all_edges AS (
    -- Edges User -> User (Dirichlet trust; prev_sent_weight is MR seed)
    SELECT subject AS src, object AS dst, prev_sent_weight AS weight, 0::bigint AS magnitude, ''::text AS context
    FROM user_trust_edge
    UNION ALL
    -- Pollings and Variants (variant -> polling)
    SELECT pv.id, p.id, 1.0::float8, 0::bigint, ''::text
    FROM polling p
    JOIN polling_variant pv ON p.id = pv.polling_id
    WHERE p.enabled = true
    UNION ALL
    -- Pollings Acts
    SELECT pa.author_id, pa.polling_variant_id, 1.0::float8, 0::bigint, ''::text
    FROM polling_act pa
    JOIN polling p ON p.id = pa.polling_id
    WHERE p.enabled = true
  ),
  agg AS (
    SELECT
      coalesce(array_agg(src), ARRAY[]::text[]) AS src_arr,
      coalesce(array_agg(dst), ARRAY[]::text[]) AS dst_arr,
      coalesce(array_agg(weight), ARRAY[]::float8[]) AS weight_arr,
      coalesce(array_agg(magnitude), ARRAY[]::bigint[]) AS magnitude_arr,
      coalesce(array_agg(context), ARRAY[]::text[]) AS context_arr,
      count(*)::int AS cnt
    FROM all_edges
  )
  SELECT src_arr, dst_arr, weight_arr, magnitude_arr, context_arr, cnt
  INTO _src, _dst, _weight, _magnitude, _context, _edge_count
  FROM agg;

  _total := _total + _edge_count;

  PERFORM mr_bulk_load_edges(_src, _dst, _weight, _magnitude, _context, 120000::bigint);

  -- Unimplemented/WIP: new-edges filter; no calls when flag off.
  IF _meritrank_new_edges_enabled THEN
    SELECT _total + count(*)::int INTO _total
    FROM (SELECT mr_set_new_edges_filter(user_id, filter) FROM user_updates) AS _;
  END IF;

  RETURN _total;
END;
$$;
