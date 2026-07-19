part of '_migrations.dart';

/// Typed trust source graphs (rev 6): source accumulators, policy tables,
/// evidence ledger, effective projector, and MeritRank deletion tombstones.
///
/// `user_trust_edge` stays the effective projection (unchanged schema).
/// Context multipliers scale evidence mass, not posterior weight; they need
/// not sum to 1. Policy changes follow the quiesced migration contract only.
final m0122 = Migration('0122', [
  // §5.1 Source table
  r'''
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
CREATE INDEX IF NOT EXISTS user_trust_source_edge_pair_idx
  ON public.user_trust_source_edge (subject, object);
CREATE INDEX IF NOT EXISTS user_trust_source_edge_object_idx
  ON public.user_trust_source_edge (object);
''',
  // §5.2 Policy table
  r'''
CREATE TABLE IF NOT EXISTS public.trust_policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  half_life_seconds double precision NOT NULL
    CHECK (half_life_seconds >= 86400 AND half_life_seconds <= 3.2e9),
  epsilon double precision NOT NULL CHECK (epsilon >= 0 AND epsilon <= 1),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.trust_policy (half_life_seconds, epsilon)
VALUES (15724800, 0.1)
ON CONFLICT DO NOTHING;
''',
  // §5.2 Context config
  r'''
CREATE TABLE IF NOT EXISTS public.trust_context_config (
  trust_context text PRIMARY KEY CHECK (
    trust_context IN ('personal','commitment','forward','legacy')),
  evidence_multiplier double precision NOT NULL
    CHECK (evidence_multiplier >= 0 AND evidence_multiplier <= 100),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.trust_context_config (trust_context, evidence_multiplier) VALUES
  ('legacy', 1.0), ('personal', 1.0), ('commitment', 1.0), ('forward', 0.20)
ON CONFLICT (trust_context) DO NOTHING;
''',
  // §5.3 Legacy source copy
  r'''
INSERT INTO public.user_trust_source_edge
  (trust_context, subject, object, s_very_bad, s_bad, s_no_effect, s_good,
   s_very_good, anchor_at, created_at, updated_at)
SELECT 'legacy', subject, object, s_very_bad, s_bad, s_no_effect, s_good,
       s_very_good, anchor_at, created_at, updated_at
FROM public.user_trust_edge
ON CONFLICT (trust_context, subject, object) DO NOTHING;
''',
  // §5.4 Evidence ledger
  r'''
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
CREATE UNIQUE INDEX IF NOT EXISTS trust_evidence_event_propagated_unique
  ON public.trust_evidence_event
  (trust_context, source_type, request_id, subject_user_id, object_user_id, bin)
  WHERE request_id IS NOT NULL
    AND source_type IN ('propagated_author_evaluated_commitment',
                        'negative_commitment_route_no_effect');
CREATE UNIQUE INDEX IF NOT EXISTS trust_evidence_event_unsuccessful_unique
  ON public.trust_evidence_event
  (trust_context, request_id, subject_user_id, object_user_id)
  WHERE request_id IS NOT NULL
    AND source_type = 'unsuccessful_request_forward';
CREATE UNIQUE INDEX IF NOT EXISTS trust_evidence_event_request_unique
  ON public.trust_evidence_event
  (trust_context, source_type, request_id, subject_user_id, object_user_id)
  WHERE request_id IS NOT NULL
    AND source_type NOT IN ('propagated_author_evaluated_commitment',
                            'negative_commitment_route_no_effect',
                            'unsuccessful_request_forward');
CREATE INDEX IF NOT EXISTS trust_evidence_event_pair_idx
  ON public.trust_evidence_event (subject_user_id, object_user_id, applied_at DESC);
CREATE INDEX IF NOT EXISTS trust_evidence_event_request_idx
  ON public.trust_evidence_event (request_id) WHERE request_id IS NOT NULL;
''',
  // §5.4 Forward attribution
  r'''
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
CREATE INDEX IF NOT EXISTS fda_parent_idx
  ON public.forward_decision_attribution (parent_forward_edge_id);
''',
  // §5.4 MeritRank tombstone
  r'''
CREATE TABLE IF NOT EXISTS public.meritrank_edge_tombstone (
  subject text NOT NULL,
  object text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_error text,
  PRIMARY KEY (subject, object)
);
''',
  // §5.5 Pair lock
  r'''
CREATE OR REPLACE FUNCTION public.trust_pair_lock(_subject text, _object text)
RETURNS void LANGUAGE sql VOLATILE AS $$
  SELECT pg_advisory_xact_lock(hashtextextended(_subject || chr(31) || _object, 4242));
$$;
''',
  // §5.5 Source evidence apply
  r'''
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
''',
  // §5.6 Effective edge rebuild
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
''',
  // §5.6 Batched effective rebuild
  r'''
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
''',
  // §5.7 Drop superseded functions
  r'''
DROP FUNCTION IF EXISTS public.trust_apply_evidence(
  text, text, text, double precision, double precision, double precision);
DROP FUNCTION IF EXISTS public.meritrank_sweep(double precision, double precision);
DROP FUNCTION IF EXISTS public.trust_recompute_all(double precision);
DROP FUNCTION IF EXISTS public.trust_resync_source(text, double precision);
''',
  // §5.7 New one-argument resync
  r'''
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
''',
  // §5.8 Effective delete trigger
  r'''
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
''',
]);
