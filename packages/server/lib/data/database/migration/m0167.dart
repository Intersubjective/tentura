part of '_migrations.dart';

/// Constellation anchor storage, cursor triggers, and readonly visibility cache (P02).
final m0167 = Migration('0167', [
  r'''
CREATE TABLE public.constellation_anchor (
  id text PRIMARY KEY,
  viewer_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  person_id text REFERENCES public."user"(id) ON DELETE CASCADE,
  beacon_id text REFERENCES public.beacon(id) ON DELETE CASCADE,
  x_units double precision NOT NULL,
  y_units double precision NOT NULL,
  coordinate_space_version integer NOT NULL,
  revision bigint NOT NULL,
  placed_at timestamptz NOT NULL,
  CONSTRAINT constellation_anchor__target_chk
    CHECK (num_nonnulls(person_id, beacon_id) = 1),
  CONSTRAINT constellation_anchor__coord_chk
    CHECK (
      coordinate_space_version = 1
      AND x_units BETWEEN -10 AND 10
      AND y_units BETWEEN -10 AND 10
    )
);
''',
  r'''
CREATE TABLE public.constellation_anchor_cursor (
  viewer_id text PRIMARY KEY REFERENCES public."user"(id) ON DELETE CASCADE,
  revision bigint NOT NULL DEFAULT 0,
  last_placed_at timestamptz
);
''',
  r'''
CREATE UNIQUE INDEX constellation_anchor__viewer_person_uq
  ON public.constellation_anchor (viewer_id, person_id)
  WHERE person_id IS NOT NULL;
''',
  r'''
CREATE UNIQUE INDEX constellation_anchor__viewer_beacon_uq
  ON public.constellation_anchor (viewer_id, beacon_id)
  WHERE beacon_id IS NOT NULL;
''',
  r'''
CREATE INDEX constellation_anchor__viewer_id_idx
  ON public.constellation_anchor (viewer_id);
''',
  r'''
CREATE INDEX constellation_anchor__person_id_idx
  ON public.constellation_anchor (person_id)
  WHERE person_id IS NOT NULL;
''',
  r'''
CREATE INDEX constellation_anchor__beacon_id_idx
  ON public.constellation_anchor (beacon_id)
  WHERE beacon_id IS NOT NULL;
''',
  r'''
CREATE OR REPLACE FUNCTION public.bump_constellation_anchor_revision()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  _viewer_id text;
  _new_revision bigint;
  _new_placed timestamptz;
BEGIN
  IF TG_OP = 'DELETE' THEN
    _viewer_id := OLD.viewer_id;
    UPDATE public.constellation_anchor_cursor c
       SET revision = c.revision + 1
     WHERE c.viewer_id = _viewer_id
     RETURNING c.revision INTO _new_revision;
    IF NOT FOUND THEN
      RETURN OLD;
    END IF;
    RETURN OLD;
  END IF;

  _viewer_id := NEW.viewer_id;

  UPDATE public.constellation_anchor_cursor c
     SET
       revision = c.revision + 1,
       last_placed_at = greatest(
         clock_timestamp(),
         COALESCE(c.last_placed_at, '-infinity'::timestamptz) + interval '1 microsecond'
       )
   WHERE c.viewer_id = _viewer_id
   RETURNING c.revision, c.last_placed_at INTO _new_revision, _new_placed;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'constellation_anchor_cursor missing for viewer %', _viewer_id;
  END IF;

  NEW.revision := _new_revision;
  NEW.placed_at := _new_placed;
  RETURN NEW;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_constellation_anchor_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  _viewer_id text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    _viewer_id := OLD.viewer_id;
    IF NOT EXISTS (
      SELECT 1 FROM public.constellation_anchor_cursor c
      WHERE c.viewer_id = _viewer_id
    ) THEN
      RETURN OLD;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public."user" u WHERE u.id = _viewer_id
    ) THEN
      RETURN OLD;
    END IF;
  ELSE
    _viewer_id := NEW.viewer_id;
  END IF;

  PERFORM public.emit_realtime_entity_change_strict(
    'constellation_anchor',
    _viewer_id,
    lower(TG_OP),
    ARRAY[_viewer_id]
  );

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;
''',
  r'''
CREATE TRIGGER constellation_anchor_revision_trg
  BEFORE INSERT OR UPDATE OR DELETE ON public.constellation_anchor
  FOR EACH ROW
  EXECUTE FUNCTION public.bump_constellation_anchor_revision();
''',
  r'''
CREATE TRIGGER constellation_anchor_notify_trg
  AFTER INSERT OR UPDATE OR DELETE ON public.constellation_anchor
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_constellation_anchor_change();
''',
  r'''
CREATE OR REPLACE FUNCTION public.person_are_mutually_visible_cached(
  a_id text, b_id text, ctx text
) RETURNS boolean LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
  _lo text := LEAST(a_id, b_id);
  _hi text := GREATEST(a_id, b_id);
  _ctx text := coalesce(ctx, '');
  _cur_epoch bigint;
  _cur_trust bigint;
  _row public.person_mutual_visibility_cache;
  _result boolean;
BEGIN
  SELECT epoch INTO _cur_epoch FROM public.mr_publish_epoch WHERE id = true;
  _cur_trust := public.direct_trust_current_version();
  SELECT * INTO _row FROM public.person_mutual_visibility_cache c
    WHERE c.person_lo = _lo AND c.person_hi = _hi AND c.ctx = _ctx
    AND c.mr_epoch = _cur_epoch AND c.trust_version = _cur_trust
    AND c.computed_at > now() - interval '60 seconds';
  IF FOUND THEN
    RETURN _row.is_mutually_visible;
  END IF;
  IF current_setting('transaction_read_only', true) = 'on' THEN
    BEGIN
      _result := public.person_are_mutually_visible(a_id, b_id, _ctx);
    EXCEPTION WHEN OTHERS THEN
      RETURN false;
    END;
    RETURN _result;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext(_lo || ':' || _hi || ':' || _ctx));
  SELECT * INTO _row FROM public.person_mutual_visibility_cache c
    WHERE c.person_lo = _lo AND c.person_hi = _hi AND c.ctx = _ctx
    AND c.mr_epoch = _cur_epoch AND c.trust_version = _cur_trust
    AND c.computed_at > now() - interval '60 seconds';
  IF FOUND THEN
    RETURN _row.is_mutually_visible;
  END IF;
  BEGIN
    _result := public.person_are_mutually_visible(a_id, b_id, _ctx);
  EXCEPTION WHEN OTHERS THEN
    RETURN false;
  END;
  INSERT INTO public.person_mutual_visibility_cache
    (person_lo, person_hi, ctx, is_mutually_visible, mr_epoch, trust_version, computed_at)
  VALUES (_lo, _hi, _ctx, _result, _cur_epoch, _cur_trust, now())
  ON CONFLICT (person_lo, person_hi, ctx) DO UPDATE SET
    is_mutually_visible = EXCLUDED.is_mutually_visible,
    mr_epoch = EXCLUDED.mr_epoch,
    trust_version = EXCLUDED.trust_version,
    computed_at = EXCLUDED.computed_at;
  RETURN _result;
END;
$$;
''',
]);
