part of '_migrations.dart';

/// B2: noisy-contact wall (Arch §4.1, §4.2, §6). Forward edges gain a contact
/// resolution (`contact_outcome` 1 engaged / 2 declined / 3 ignored), kinds 6
/// `engaged` and 7 `noisy` are seeded, and the projection publishes
/// `-level(n_noisy)` when `T_recent < 0.05` and `n_noisy >= 3`.
///
/// The transition writers are triggers, so every path that creates an edge,
/// offers help, forwards on, cancels or declines resolves the contact the same
/// way; the 1 h sweep (`ContactResolutionSweepCase`) handles the deadline.
final m0206 = Migration('0206', [
  '''
ALTER TABLE public.beacon_forward_edge
    ADD COLUMN contact_outcome smallint,
    ADD COLUMN contact_resolved_at timestamp with time zone,
    ADD COLUMN contact_deadline_at timestamp with time zone
''',
  '''
CREATE INDEX beacon_forward_edge_contact_deadline ON public.beacon_forward_edge USING btree (contact_deadline_at) WHERE (contact_resolved_at IS NULL)
''',
  r'''
INSERT INTO public.trust_kind_config
    (kind, slug, polarity, half_life_s, k_sat, mix_weight, wall_levels, linear_window_s, counts_for_immunity)
VALUES
    (6, 'engaged', 0, 7776000, 2, 0.2, NULL, NULL, true),
    (7, 'noisy', 1, 1209600, 1, 0, '[{"min_n": 3, "level": 0.1}, {"min_n": 6, "level": 0.3}, {"min_n": 10, "level": 0.6}]', NULL, false)
''',

  // Deadline: only for edges created after this migration, and not for
  // self-edges or edges to the request author.
  r'''
CREATE FUNCTION public.contact_edge_set_deadline() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.sender_id <> NEW.recipient_id
     AND NEW.recipient_id IS DISTINCT FROM
         (SELECT b.user_id FROM public.beacon b WHERE b.id = NEW.beacon_id) THEN
    NEW.contact_deadline_at := NEW.created_at + interval '7 days'
      + ((('x' || substr(md5(NEW.id), 1, 8))::bit(32)::bigint % 172801) - 86400)
        * interval '1 second';
  END IF;
  RETURN NEW;
END;
$$
''',
  r'''
CREATE TRIGGER contact_edge_set_deadline BEFORE INSERT ON public.beacon_forward_edge FOR EACH ROW EXECUTE FUNCTION public.contact_edge_set_deadline()
''',

  // Sender cancels before resolution: resolved, outcome stays NULL.
  r'''
CREATE FUNCTION public.contact_edge_on_cancel() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.contact_resolved_at := now();
  RETURN NEW;
END;
$$
''',
  r'''
CREATE TRIGGER contact_edge_on_cancel BEFORE UPDATE OF cancelled_at ON public.beacon_forward_edge FOR EACH ROW WHEN (OLD.cancelled_at IS NULL AND NEW.cancelled_at IS NOT NULL AND NEW.contact_deadline_at IS NOT NULL AND NEW.contact_resolved_at IS NULL) EXECUTE FUNCTION public.contact_edge_on_cancel()
''',

  // Recipient declines: resolved as declined, no evidence.
  r'''
CREATE FUNCTION public.contact_inbox_on_decline() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE public.beacon_forward_edge
  SET contact_outcome = 2, contact_resolved_at = now()
  WHERE beacon_id = NEW.beacon_id
    AND recipient_id = NEW.user_id
    AND contact_deadline_at IS NOT NULL
    AND contact_resolved_at IS NULL;
  RETURN NULL;
END;
$$
''',
  r'''
CREATE TRIGGER contact_inbox_on_decline AFTER UPDATE OF status ON public.inbox_item FOR EACH ROW WHEN (NEW.status = 2 AND OLD.status IS DISTINCT FROM 2) EXECUTE FUNCTION public.contact_inbox_on_decline()
''',

  // Engagement (offer or forward on), before or after the sweep ignored the
  // contact: record `engaged`, retract `noisy`, outcome -> engaged.
  r'''
CREATE FUNCTION public.contact_engage(p_beacon text, p_user text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  _e record;
  _senders text[] := ARRAY[]::text[];
BEGIN
  FOR _e IN
    SELECT id, sender_id, contact_outcome
    FROM public.beacon_forward_edge
    WHERE beacon_id = p_beacon
      AND recipient_id = p_user
      AND contact_deadline_at IS NOT NULL
      AND cancelled_at IS NULL
      AND (contact_resolved_at IS NULL OR contact_outcome = 3)
    ORDER BY id
    FOR UPDATE
  LOOP
    IF _e.contact_outcome = 3 THEN
      UPDATE public.trust_evidence SET retracted_at = now()
      WHERE source_key = 'contact:' || _e.id || ':noisy' AND retracted_at IS NULL;
    END IF;
    UPDATE public.beacon_forward_edge
    SET contact_outcome = 1, contact_resolved_at = now()
    WHERE id = _e.id;
    INSERT INTO public.trust_evidence
      (id, subject_user_id, object_user_id, kind, count, source_key, beacon_id)
    VALUES
      (gen_random_uuid()::text, p_user, _e.sender_id, 6, 1,
       'contact:' || _e.id || ':engaged', p_beacon)
    ON CONFLICT (source_key) DO UPDATE SET retracted_at = NULL;
    _senders := _senders || _e.sender_id;
  END LOOP;

  PERFORM public.trust_project_pair(p_user, s)
  FROM (SELECT DISTINCT unnest(_senders) AS s) q
  ORDER BY s;
END;
$$
''',
  r'''
CREATE FUNCTION public.contact_engage_on_help_offer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM public.contact_engage(NEW.beacon_id, NEW.user_id);
  RETURN NULL;
END;
$$
''',
  r'''
CREATE TRIGGER contact_engage_on_help_offer AFTER INSERT OR UPDATE OF status ON public.beacon_help_offer FOR EACH ROW WHEN (NEW.status = 0) EXECUTE FUNCTION public.contact_engage_on_help_offer()
''',
  r'''
CREATE FUNCTION public.contact_engage_on_forward() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM public.contact_engage(NEW.beacon_id, NEW.sender_id);
  RETURN NULL;
END;
$$
''',
  r'''
CREATE TRIGGER contact_engage_on_forward AFTER INSERT ON public.beacon_forward_edge FOR EACH ROW EXECUTE FUNCTION public.contact_engage_on_forward()
''',

  // Projection: noisy-contact wall (published only with walls enabled).
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

  IF abs(_target - _prev) > _eps OR sign(_target) <> sign(_prev) THEN
    INSERT INTO public.trust_publish_queue (subject_user_id, object_user_id)
    VALUES (p_subject, p_object)
    ON CONFLICT (subject_user_id, object_user_id)
      DO UPDATE SET next_attempt_at = now();
  END IF;
END;
$$
''',
]);
