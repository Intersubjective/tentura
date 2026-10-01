part of '_migrations.dart';

final m0207 = Migration('0207', [
  // A changed wall level always reaches MR, even within epsilon.
  r'''
CREATE OR REPLACE FUNCTION public.trust_project_pair(p_subject text, p_object text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  _t double precision;
  _recent double precision;
  _noisy double precision;
  _eps double precision;
  _walls boolean;
  _level double precision;
  _target double precision;
  _prev double precision;
BEGIN
  PERFORM public.trust_pair_lock(p_subject, p_object);

  SELECT f.trust_w, f.trust_recent, f.n_noisy
    INTO _t, _recent, _noisy
    FROM public.trust_fold_pair(p_subject, p_object) f;

  SELECT (c.value)::text::double precision INTO _eps
    FROM public.trust_config c WHERE c.key = 'epsilon';
  _eps := coalesce(_eps, 0.1);

  SELECT (c.value)::text::boolean INTO _walls
    FROM public.trust_config c WHERE c.key = 'wall_publish_enabled';

  -- level(n): highest wall_levels entry with min_n <= n; the tolerance keeps
  -- observations made an instant ago (decay just below 1) on the threshold.
  _level := NULL;
  IF coalesce(_walls, false) AND _recent < 0.05 THEN
    SELECT (w->>'level')::double precision INTO _level
      FROM public.trust_kind_config k,
           jsonb_array_elements(k.wall_levels) w
      WHERE k.kind = 7
        AND (w->>'min_n')::double precision <= _noisy + 0.001
      ORDER BY (w->>'min_n')::double precision DESC
      LIMIT 1;
  END IF;

  _target := CASE
    WHEN EXISTS (SELECT 1 FROM public.user_block
                 WHERE blocker_id = p_subject AND blocked_id = p_object)
    THEN CASE WHEN coalesce(_walls, false) THEN -1 ELSE 0 END
    WHEN _level IS NOT NULL THEN -_level
    WHEN _t > 0 THEN _t
    ELSE 0
  END;

  INSERT INTO public.user_trust_edge (subject, object, trust_w, wall_d, target_w)
  VALUES (p_subject, p_object, _t, coalesce(_level, 0), _target)
  ON CONFLICT (subject, object) DO UPDATE SET
    trust_w = EXCLUDED.trust_w,
    wall_d = EXCLUDED.wall_d,
    target_w = EXCLUDED.target_w,
    updated_at = now()
  RETURNING prev_sent_weight INTO _prev;
  _prev := coalesce(_prev, 0);

  IF _target = 0 AND _prev = 0 THEN
    DELETE FROM public.user_trust_edge
    WHERE subject = p_subject AND object = p_object;
  END IF;

  IF abs(_target - _prev) > _eps OR sign(_target) <> sign(_prev)
     OR (_target < 0 AND _target <> _prev) THEN
    INSERT INTO public.trust_publish_queue (subject_user_id, object_user_id)
    VALUES (p_subject, p_object)
    ON CONFLICT (subject_user_id, object_user_id)
      DO UPDATE SET next_attempt_at = now();
  END IF;
END;
$$
''',
]);
