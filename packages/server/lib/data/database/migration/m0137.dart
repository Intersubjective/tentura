part of '_migrations.dart';

/// B3 withdrawal gate on `trust_rebuild_effective_edge` publish step.
/// See docs/plans/user-block-implementation-spec.md §5.
final m0137 = Migration('0137', [
  r'''
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
  _target double precision;
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

  _target := CASE
    WHEN EXISTS (SELECT 1 FROM public.user_block
                 WHERE blocker_id = _subject AND blocked_id = _object)
    THEN 0 ELSE _w END;

  IF abs(_target - _prev) > _eps THEN
    BEGIN
      PERFORM mr_put_edge(_subject, _object, _target, ''::text, 0);
      UPDATE public.user_trust_edge SET prev_sent_weight = _target, updated_at = now()
      WHERE subject = _subject AND object = _object;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'trust_rebuild_effective_edge: publish %->% deferred: %',
        _subject, _object, SQLERRM;
    END;
  END IF;

  RETURN _w;
END; $$;
''',
]);
