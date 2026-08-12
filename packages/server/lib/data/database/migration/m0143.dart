part of '_migrations.dart';

/// Capability evidence SQL functions (unit A3).
final m0143 = Migration('0143', [
  r'''
CREATE OR REPLACE FUNCTION public.cap_strength(
  _s double precision, _k double precision,
  _anchor timestamptz, _half_life_seconds double precision
) RETURNS double precision LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN _s <= 0 THEN 0 ELSE
    (_s * pow(2, -extract(epoch FROM (now() - _anchor)) / _half_life_seconds))
    / (_k + _s * pow(2, -extract(epoch FROM (now() - _anchor)) / _half_life_seconds))
  END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.cap_cell_lock(_o text, _s text, _t text)
RETURNS void LANGUAGE sql VOLATILE AS $$
  SELECT pg_advisory_xact_lock(
    hashtextextended(_o || chr(31) || _s || chr(31) || _t, 4242));
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.cap_generation_bump(_o text, _s text, _t text)
RETURNS bigint LANGUAGE sql VOLATILE AS $$
  INSERT INTO public.capability_evidence_generation AS g
    (observer_user_id, subject_user_id, tag_slug, generation)
  VALUES (_o, _s, _t, 1)
  ON CONFLICT (observer_user_id, subject_user_id, tag_slug)
    DO UPDATE SET generation = g.generation + 1
  RETURNING generation;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.cap_cell_rebuild(
  _o text,
  _s text,
  _t text,
  _window_months integer,
  _hl_out double precision,
  _hl_seed double precision
) RETURNS void
  LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  _gen bigint;
  _anchor timestamptz;
  _s_out double precision := 0;
  _s_seed double precision := 0;
  _next_expiry timestamptz;
BEGIN
  PERFORM public.cap_cell_lock(_o, _s, _t);

  SELECT g.generation
  INTO _gen
  FROM public.capability_evidence_generation AS g
  WHERE g.observer_user_id = _o
    AND g.subject_user_id = _s
    AND g.tag_slug = _t;

  _anchor := now();

  SELECT
    coalesce(sum(
      CASE
        WHEN e.source_type = 3 THEN
          pow(2, -extract(epoch FROM (_anchor - e.created_at)) / _hl_out)
        ELSE 0
      END
    ), 0),
    coalesce(sum(
      CASE
        WHEN e.source_type IN (1, 4) THEN
          pow(2, -extract(epoch FROM (_anchor - e.created_at)) / _hl_seed)
        ELSE 0
      END
    ), 0),
    min(e.created_at) + make_interval(months => _window_months)
  INTO _s_out, _s_seed, _next_expiry
  FROM public.person_capability_event AS e
  WHERE e.observer_user_id = _o
    AND e.subject_user_id = _s
    AND e.tag_slug = _t
    AND e.deleted_at IS NULL
    AND e.is_negative = false
    AND e.source_type IN (1, 3, 4)
    AND e.created_at + make_interval(months => _window_months) > now();

  IF _s_out = 0 AND _s_seed = 0 THEN
    DELETE FROM public.capability_evidence_edge AS c
    WHERE c.observer_user_id = _o
      AND c.subject_user_id = _s
      AND c.tag_slug = _t;
    RETURN;
  END IF;

  INSERT INTO public.capability_evidence_edge AS c (
    observer_user_id,
    subject_user_id,
    tag_slug,
    s_out,
    s_seed,
    anchor_at,
    built_from_gen,
    next_expiry_at,
    updated_at
  ) VALUES (
    _o,
    _s,
    _t,
    _s_out,
    _s_seed,
    _anchor,
    coalesce(_gen, 0),
    _next_expiry,
    now()
  )
  ON CONFLICT (observer_user_id, subject_user_id, tag_slug)
  DO UPDATE SET
    s_out = EXCLUDED.s_out,
    s_seed = EXCLUDED.s_seed,
    anchor_at = EXCLUDED.anchor_at,
    built_from_gen = EXCLUDED.built_from_gen,
    next_expiry_at = EXCLUDED.next_expiry_at,
    updated_at = now();
END;
$$;
''',
]);
