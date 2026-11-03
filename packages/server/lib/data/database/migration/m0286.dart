part of '_migrations.dart';

/// ADR 0012 D5/D19 (#897): every tag a person gives is a routing seed.
///
/// `cap_cell_rebuild` now also reads `privateLabel` (0) under the seed rules
/// (seed half-life, θ_seed). One observer+subject+tag given both as a label
/// and as a legacy `seedRoutingAttestation` (4) counts once: the fresher of
/// the two. `commitRole` (2) still never aggregates.
///
/// The invite-accepted sheet now writes labels, so standing seed attestations
/// become labels (original `created_at` kept); then every labelled cell is
/// rebuilt (constants as of this migration: 24-month window, 365-day outcome
/// half-life, 90-day seed half-life).
final m0286 = Migration('0286', [
  r'''
CREATE OR REPLACE FUNCTION public.cap_cell_rebuild(_o text, _s text, _t text, _window_months integer, _hl_out double precision, _hl_seed double precision) RETURNS void
    LANGUAGE plpgsql
    AS $$
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
        WHEN e.source_type = 1 THEN
          pow(2, -extract(epoch FROM (_anchor - e.created_at)) / _hl_seed)
        ELSE 0
      END
    ), 0)
    + coalesce(max(
      CASE
        WHEN e.source_type IN (0, 4) THEN
          pow(2, -extract(epoch FROM (_anchor - e.created_at)) / _hl_seed)
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
    AND e.source_type IN (0, 1, 3, 4)
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
$$
''',
  '''
INSERT INTO public.person_capability_event (
  id, subject_user_id, observer_user_id, tag_slug, source_type, visibility,
  created_at
)
SELECT
  'CE' || substr(md5(seed.id), 1, 12),
  seed.subject_user_id,
  seed.observer_user_id,
  seed.tag_slug,
  0,
  0,
  seed.created_at
FROM public.person_capability_event AS seed
WHERE seed.source_type = 4
  AND seed.deleted_at IS NULL
  AND seed.is_negative = false
ON CONFLICT DO NOTHING
''',
  r'''
DO $$
DECLARE
  _cell record;
BEGIN
  FOR _cell IN
    SELECT DISTINCT observer_user_id, subject_user_id, tag_slug
    FROM public.person_capability_event
    WHERE source_type = 0
      AND is_negative = false
      AND deleted_at IS NULL
    ORDER BY observer_user_id, subject_user_id, tag_slug
  LOOP
    PERFORM public.cap_generation_bump(
      _cell.observer_user_id, _cell.subject_user_id, _cell.tag_slug
    );
    PERFORM public.cap_cell_rebuild(
      _cell.observer_user_id, _cell.subject_user_id, _cell.tag_slug,
      24, 31536000::double precision, 7776000::double precision
    );
  END LOOP;
END;
$$
''',
]);
