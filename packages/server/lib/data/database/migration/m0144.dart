part of '_migrations.dart';

/// MR publish epoch bumps at MeritRank publish sites (unit B3).
final m0144 = Migration('0144', [
  r'''
CREATE OR REPLACE FUNCTION public.mr_bump_publish_epoch()
RETURNS void
LANGUAGE sql
VOLATILE
AS $$
  UPDATE public.mr_publish_epoch SET epoch = epoch + 1 WHERE id = true;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_meritrank_beacon_mutation()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    PERFORM mr_put_edge(
      NEW.id,
      NEW.user_id,
      1::double precision,
      NEW.context,
      0
    );
    PERFORM mr_put_edge(
      NEW.user_id,
      NEW.id,
      1::double precision,
      NEW.context,
      NEW.ticker
    );
    PERFORM public.mr_bump_publish_epoch();
    RETURN NEW;

  ELSIF (TG_OP = 'DELETE') THEN
    PERFORM mr_delete_edge(OLD.id, OLD.user_id, OLD.context);
    PERFORM mr_delete_edge(OLD.user_id, OLD.id, OLD.context);
    PERFORM public.mr_bump_publish_epoch();
    RETURN OLD;
  END IF;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_meritrank_comment_mutation()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  context text;
BEGIN
  SELECT beacon.context
    INTO context
    FROM beacon
    WHERE beacon.id = NEW.beacon_id;

  IF (TG_OP = 'INSERT') THEN
    PERFORM mr_put_edge(
      NEW.id,
      NEW.user_id,
      1::double precision,
      context,
      0
    );
    PERFORM mr_put_edge(
      NEW.user_id,
      NEW.id,
      1::double precision,
      context,
      NEW.ticker
    );
    PERFORM public.mr_bump_publish_epoch();
    RETURN NEW;

  ELSIF (TG_OP = 'DELETE') THEN
    PERFORM mr_delete_edge(OLD.id, OLD.user_id, context);
    PERFORM mr_delete_edge(OLD.user_id, OLD.id, context);
    PERFORM public.mr_bump_publish_epoch();
    RETURN OLD;
  END IF;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_meritrank_opinion_mutation()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    PERFORM mr_put_edge(
      NEW.subject,
      NEW.id,
      (abs(NEW.amount))::double precision,
      '',
      NEW.ticker
    );
    PERFORM mr_put_edge(
      NEW.id,
      NEW.subject,
      (1)::double precision,
      '',
      NEW.ticker
    );
    PERFORM mr_put_edge(
      NEW.id,
      NEW.object,
      (sign(NEW.amount))::double precision,
      '',
      NEW.ticker
    );
    PERFORM public.mr_bump_publish_epoch();
    RETURN NEW;

  ELSIF (TG_OP = 'DELETE') THEN
    PERFORM mr_delete_edge(OLD.subject, OLD.id);
    PERFORM mr_delete_edge(OLD.id, OLD.subject);
    PERFORM mr_delete_edge(OLD.id, OLD.object);
    PERFORM public.mr_bump_publish_epoch();
    RETURN OLD;
  END IF;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_meritrank_vote_beacon_mutation()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  _context text;
BEGIN
  SELECT beacon.context
    INTO STRICT _context
    FROM beacon
    WHERE beacon.id = NEW.object;

  IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
    PERFORM mr_put_edge(
      NEW.subject,
      NEW.object,
      (NEW.amount)::double precision,
      _context,
      NEW.ticker
    );
    PERFORM public.mr_bump_publish_epoch();
    RETURN NEW;

  ELSIF (TG_OP = 'DELETE') THEN
    PERFORM mr_delete_edge(
      OLD.subject,
      OLD.object,
      _context
    );
    PERFORM public.mr_bump_publish_epoch();
    RETURN OLD;
  END IF;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_meritrank_vote_comment_mutation()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  _context text;
  beacon_id text;
BEGIN
  SELECT comment.beacon_id
    INTO beacon_id
    FROM comment
    WHERE comment.id = NEW.object;

  SELECT beacon.context
    INTO _context
    FROM beacon
    WHERE beacon.id = beacon_id;

  IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
    PERFORM mr_put_edge(
      NEW.subject,
      NEW.object,
      (NEW.amount)::double precision,
      _context,
      NEW.ticker
    );
    PERFORM public.mr_bump_publish_epoch();
    RETURN NEW;

  ELSIF (TG_OP = 'DELETE') THEN
    PERFORM mr_delete_edge(
      OLD.subject,
      OLD.object,
      _context
    );
    PERFORM public.mr_bump_publish_epoch();
    RETURN OLD;
  END IF;
END;
$$;
''',
  r'''
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
    PERFORM public.mr_bump_publish_epoch();
    RETURN NEW;

  ELSIF (TG_OP = 'DELETE') THEN
    PERFORM mr_delete_edge(
      OLD.subject,
      OLD.object,
      ''::text
    );
    PERFORM public.mr_bump_publish_epoch();
    RETURN OLD;
  END IF;
END;
$$;
''',
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
      PERFORM public.mr_bump_publish_epoch();
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
