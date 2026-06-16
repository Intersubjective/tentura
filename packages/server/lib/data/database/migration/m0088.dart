part of '_migrations.dart';

/// Dirichlet-Bayesian user→user trust edges (VSIDS inflation); SQL owns trust math.
final m0088 = Migration('0088', [
  '''
CREATE TABLE IF NOT EXISTS public.user_trust_edge (
  subject text NOT NULL,
  object text NOT NULL,
  s_very_bad double precision NOT NULL DEFAULT 0,
  s_bad double precision NOT NULL DEFAULT 0,
  s_no_effect double precision NOT NULL DEFAULT 0,
  s_good double precision NOT NULL DEFAULT 0,
  s_very_good double precision NOT NULL DEFAULT 0,
  anchor_at timestamp with time zone NOT NULL DEFAULT now(),
  prev_sent_weight double precision NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT user_trust_edge_pkey PRIMARY KEY (subject, object),
  CONSTRAINT user_trust_edge_subject_fkey FOREIGN KEY (subject)
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT user_trust_edge_object_fkey FOREIGN KEY (object)
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE
);
''',
  '''
DROP TRIGGER IF EXISTS notify_meritrank_vote_user_mutation ON public.vote_user;
''',
  r'''
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
''',
  r'''
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
  -- Row lock via upsert; anchor_at fixed on conflict (never advanced by evidence).
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
''',
  r'''
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
''',
  r'''
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
''',
  r'''
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
''',
  r'''
CREATE OR REPLACE FUNCTION public.meritrank_init()
  RETURNS integer
    LANGUAGE plpgsql
    STABLE
    AS $$
DECLARE
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
    SELECT subject AS src, object AS dst, prev_sent_weight AS weight, 0::bigint AS magnitude, ''::text AS context FROM user_trust_edge
    UNION ALL
    SELECT pv.id, p.id, 1.0::float8, 0::bigint, ''::text FROM polling p JOIN polling_variant pv ON p.id = pv.polling_id WHERE p.enabled = true
    UNION ALL
    SELECT pa.author_id, pa.polling_variant_id, 1.0::float8, 0::bigint, ''::text FROM polling_act pa JOIN polling p ON p.id = pa.polling_id WHERE p.enabled = true
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

  IF _meritrank_new_edges_enabled THEN
    SELECT _total + count(*)::int INTO _total FROM (SELECT mr_set_new_edges_filter(user_id, filter) FROM user_updates) AS _;
  END IF;

  RETURN _total;
END;
$$;
''',
]);
