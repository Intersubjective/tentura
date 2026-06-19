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
-- User→user MeritRank edges are written by SQL trust_apply_evidence / meritrank_sweep.
-- (Function body kept below for reference; do not re-attach the trigger.)

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

CREATE OR REPLACE FUNCTION public.on_public_user_update()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  IF NEW.has_picture = false THEN
    _new.blur_hash = '';
    _new.pic_height = 0;
    _new.pic_width = 0;
  END IF;
  RETURN _new;
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

CREATE OR REPLACE TRIGGER on_public_user_update
  BEFORE UPDATE ON public."user"
  FOR EACH ROW EXECUTE FUNCTION public.on_public_user_update();

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

-- Apply evidence to one edge (VSIDS inflate bump, epsilon-gated mr_put_edge).
CREATE OR REPLACE FUNCTION public.trust_apply_evidence(
  _subject text,
  _object text,
  _bin text,
  _count double precision,
  _half_life_seconds double precision,
  _epsilon double precision
) RETURNS double precision
  LANGUAGE plpgsql
  VOLATILE
  AS $$
DECLARE
  _r public.user_trust_edge%ROWTYPE;
  _f_inflate double precision;
  _f double precision;
  _w double precision;
  _bump double precision;
BEGIN
  INSERT INTO public.user_trust_edge (subject, object, anchor_at)
  VALUES (_subject, _object, now())
  ON CONFLICT (subject, object) DO UPDATE
    SET updated_at = now()
  RETURNING * INTO _r;

  IF _half_life_seconds <= 0 THEN
    _f_inflate := 1;
  ELSE
    _f_inflate := pow(
      2,
      greatest(EXTRACT(EPOCH FROM (now() - _r.anchor_at)), 0) / _half_life_seconds
    );
  END IF;

  _bump := _count * _f_inflate;
  _f := 1.0 / _f_inflate;

  UPDATE public.user_trust_edge SET
    s_very_bad = s_very_bad + CASE WHEN _bin = 'very_bad' THEN _bump ELSE 0 END,
    s_bad = s_bad + CASE WHEN _bin = 'bad' THEN _bump ELSE 0 END,
    s_no_effect = s_no_effect + CASE WHEN _bin = 'no_effect' THEN _bump ELSE 0 END,
    s_good = s_good + CASE WHEN _bin = 'good' THEN _bump ELSE 0 END,
    s_very_good = s_very_good + CASE WHEN _bin = 'very_good' THEN _bump ELSE 0 END,
    updated_at = now()
  WHERE subject = _subject AND object = _object
  RETURNING * INTO _r;

  _w := public.trust_edge_weight(
    _r.s_very_bad, _r.s_bad, _r.s_no_effect, _r.s_good, _r.s_very_good, _f
  );

  IF abs(_w - _r.prev_sent_weight) > _epsilon THEN
    PERFORM mr_put_edge(_subject, _object, _w, ''::text, 0);
    UPDATE public.user_trust_edge
    SET prev_sent_weight = _w, updated_at = now()
    WHERE subject = _subject AND object = _object;
  END IF;

  RETURN _w;
END;
$$;

-- Proactive decay drift push (schedule via SELECT meritrank_sweep(H, epsilon)).
-- Ops reference: docs/features/trust_edges.md
CREATE OR REPLACE FUNCTION public.meritrank_sweep(
  _half_life_seconds double precision,
  _epsilon double precision
) RETURNS integer
  LANGUAGE plpgsql
  VOLATILE
  AS $$
DECLARE
  _r public.user_trust_edge%ROWTYPE;
  _f double precision;
  _w double precision;
  _pushed integer := 0;
BEGIN
  FOR _r IN SELECT * FROM public.user_trust_edge FOR UPDATE LOOP
    IF _half_life_seconds <= 0 THEN
      _f := 1;
    ELSE
      _f := pow(
        2,
        -greatest(EXTRACT(EPOCH FROM (now() - _r.anchor_at)), 0) / _half_life_seconds
      );
    END IF;

    _w := public.trust_edge_weight(
      _r.s_very_bad, _r.s_bad, _r.s_no_effect, _r.s_good, _r.s_very_good, _f
    );

    IF abs(_w - _r.prev_sent_weight) > _epsilon THEN
      PERFORM mr_put_edge(_r.subject, _r.object, _w, ''::text, 0);
      UPDATE public.user_trust_edge
      SET prev_sent_weight = _w, updated_at = now()
      WHERE subject = _r.subject AND object = _r.object;
      _pushed := _pushed + 1;
    END IF;
  END LOOP;

  RETURN _pushed;
END;
$$;

CREATE OR REPLACE FUNCTION public.trust_resync_source(
  _subject text,
  _half_life_seconds double precision
) RETURNS integer
  LANGUAGE plpgsql
  VOLATILE
  AS $$
DECLARE
  _r public.user_trust_edge%ROWTYPE;
  _f double precision;
  _w double precision;
  _pushed integer := 0;
BEGIN
  FOR _r IN
    SELECT * FROM public.user_trust_edge WHERE subject = _subject FOR UPDATE
  LOOP
    IF _half_life_seconds <= 0 THEN
      _f := 1;
    ELSE
      _f := pow(
        2,
        -greatest(EXTRACT(EPOCH FROM (now() - _r.anchor_at)), 0) / _half_life_seconds
      );
    END IF;

    _w := public.trust_edge_weight(
      _r.s_very_bad, _r.s_bad, _r.s_no_effect, _r.s_good, _r.s_very_good, _f
    );

    PERFORM mr_put_edge(_r.subject, _r.object, _w, ''::text, 0);
    UPDATE public.user_trust_edge
    SET prev_sent_weight = _w, updated_at = now()
    WHERE subject = _r.subject AND object = _r.object;
    _pushed := _pushed + 1;
  END LOOP;

  RETURN _pushed;
END;
$$;

CREATE OR REPLACE FUNCTION public.trust_recompute_all(
  _half_life_seconds double precision
) RETURNS integer
  LANGUAGE plpgsql
  VOLATILE
  AS $$
DECLARE
  _r public.user_trust_edge%ROWTYPE;
  _f double precision;
  _w double precision;
  _updated integer := 0;
BEGIN
  FOR _r IN SELECT * FROM public.user_trust_edge FOR UPDATE LOOP
    IF _half_life_seconds <= 0 THEN
      _f := 1;
    ELSE
      _f := pow(
        2,
        -greatest(EXTRACT(EPOCH FROM (now() - _r.anchor_at)), 0) / _half_life_seconds
      );
    END IF;

    _w := public.trust_edge_weight(
      _r.s_very_bad, _r.s_bad, _r.s_no_effect, _r.s_good, _r.s_very_good, _f
    );

    UPDATE public.user_trust_edge
    SET prev_sent_weight = _w, updated_at = now()
    WHERE subject = _r.subject AND object = _r.object;
    _updated := _updated + 1;
  END LOOP;

  RETURN _updated;
END;
$$;

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
