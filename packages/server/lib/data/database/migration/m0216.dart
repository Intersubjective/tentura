part of '_migrations.dart';

/// Noisy-contact wall gets its own switch, `trust_config.noisy_wall_enabled`
/// (default off). Off: the projection ignores `n_noisy`, so pairs fall back to
/// T or 0, while `ContactResolutionSweepCase` keeps writing kind-7 evidence.
/// Ban walls (−1) still follow `wall_publish_enabled`. The server overwrites
/// the row from `TRUST_NOISY_WALL_ENABLED` on boot; the boot-time maintenance
/// sweep then re-projects existing walls.
///
/// `user_trust_preference.noisy_wall_enabled` lets the wall owner (the
/// recipient, `subject`) override that default for their own frame; no row
/// means "follow the default". Changing it re-projects the owner's pairs.
/// See `docs/plans/noisy-contact-sanctions-design.md` § 9 (R3, R4) and § 12.
final m0216 = Migration('0216', [
  r'''
INSERT INTO public.trust_config (key, value)
VALUES ('noisy_wall_enabled', 'false')
ON CONFLICT (key) DO NOTHING
''',
  r'''
CREATE TABLE public.user_trust_preference (
    user_id text NOT NULL,
    noisy_wall_enabled boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_trust_preference_pkey PRIMARY KEY (user_id),
    CONSTRAINT user_trust_preference_user_id_fkey FOREIGN KEY (user_id)
      REFERENCES public."user"(id) ON DELETE CASCADE
)
''',
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
  _noisy_walls boolean;
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

  -- The noisy wall has its own switch (the owner's preference, else the
  -- default); ban walls stay on wall_publish_enabled. Noisy evidence keeps
  -- being recorded either way.
  SELECT coalesce(
           (SELECT p.noisy_wall_enabled FROM public.user_trust_preference p
            WHERE p.user_id = p_subject),
           (c.value)::text::boolean)
    INTO _noisy_walls
    FROM public.trust_config c WHERE c.key = 'noisy_wall_enabled';

  -- level(n): highest wall_levels entry with min_n <= n; the tolerance keeps
  -- observations made an instant ago (decay just below 1) on the threshold.
  _level := NULL;
  IF coalesce(_walls, false) AND coalesce(_noisy_walls, false)
     AND _recent < 0.05 THEN
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
  // Re-projects every pair the subject may hold a noisy wall on: existing
  // edges plus live noisy evidence (whose pairs have no row while target is 0).
  r'''
CREATE OR REPLACE FUNCTION public.trust_reproject_subject(p_subject text)
    RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  _object text;
BEGIN
  FOR _object IN
    SELECT o FROM (
      SELECT e.object AS o FROM public.user_trust_edge e
      WHERE e.subject = p_subject
      UNION
      SELECT t.object_user_id FROM public.trust_evidence t
      WHERE t.subject_user_id = p_subject AND t.kind = 7
        AND t.retracted_at IS NULL
    ) pairs
    ORDER BY o
  LOOP
    PERFORM public.trust_project_pair(p_subject, _object);
  END LOOP;
END;
$$
''',
  r'''
CREATE FUNCTION public.user_trust_preference_reproject() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM public.trust_reproject_subject(NEW.user_id);
  RETURN NULL;
END;
$$
''',
  // No DELETE: rows go only with a cascading user delete, when re-projecting
  // the departing user's pairs would be wrong.
  r'''
CREATE TRIGGER user_trust_preference_reproject
    AFTER INSERT OR UPDATE OF noisy_wall_enabled
    ON public.user_trust_preference
    FOR EACH ROW EXECUTE FUNCTION public.user_trust_preference_reproject()
''',
]);
