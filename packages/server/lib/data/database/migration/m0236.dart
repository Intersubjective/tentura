part of '_migrations.dart';

/// Tombstones for deleted pin targets (#235 U55, ARCH D15).
///
/// A hard-deleted Request or account used to cascade away every pin on it.
/// The target FKs now `SET NULL`; the revision trigger turns that update into
/// a tombstone (`tombstone_at`, target identity kept in `target_id` /
/// `target_kind`, placement and `placed_at` untouched) and advances the
/// viewer's cursor once, which fires the deferred anchor hint. Existing rows
/// are backfilled with the trigger-free statement so no revision moves.
/// Every statement is safe to replay.
final m0236 = Migration('0236', [
  '''
ALTER TABLE public.constellation_anchor
  ADD COLUMN IF NOT EXISTS target_id text,
  ADD COLUMN IF NOT EXISTS target_kind text,
  ADD COLUMN IF NOT EXISTS tombstone_at timestamp with time zone
''',

  'ALTER TABLE public.constellation_anchor DISABLE TRIGGER USER',

  '''
UPDATE public.constellation_anchor
SET target_id = coalesce(person_id, beacon_id),
    target_kind = CASE WHEN person_id IS NOT NULL THEN 'PERSON' ELSE 'BEACON' END
WHERE target_id IS NULL
''',

  'ALTER TABLE public.constellation_anchor ENABLE TRIGGER USER',

  '''
ALTER TABLE public.constellation_anchor
  ALTER COLUMN target_id SET NOT NULL,
  ALTER COLUMN target_kind SET NOT NULL
''',

  'ALTER TABLE public.constellation_anchor DROP CONSTRAINT IF EXISTS constellation_anchor__target_chk',

  '''
ALTER TABLE public.constellation_anchor
  ADD CONSTRAINT constellation_anchor__target_chk CHECK (
    (num_nonnulls(person_id, beacon_id) = 1 AND tombstone_at IS NULL)
    OR (num_nonnulls(person_id, beacon_id) = 0 AND tombstone_at IS NOT NULL)
  )
''',

  'ALTER TABLE public.constellation_anchor DROP CONSTRAINT IF EXISTS constellation_anchor_beacon_id_fkey',

  '''
ALTER TABLE public.constellation_anchor
  ADD CONSTRAINT constellation_anchor_beacon_id_fkey FOREIGN KEY (beacon_id) REFERENCES public.beacon(id) ON DELETE SET NULL
''',

  'ALTER TABLE public.constellation_anchor DROP CONSTRAINT IF EXISTS constellation_anchor_person_id_fkey',

  '''
ALTER TABLE public.constellation_anchor
  ADD CONSTRAINT constellation_anchor_person_id_fkey FOREIGN KEY (person_id) REFERENCES public."user"(id) ON DELETE SET NULL
''',

  '''
CREATE UNIQUE INDEX IF NOT EXISTS constellation_anchor__viewer_target_uq
ON public.constellation_anchor (viewer_id, target_kind, target_id)
''',

  r'''
CREATE OR REPLACE FUNCTION public.bump_constellation_anchor_revision() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _viewer_id text;
  _new_revision bigint;
  _new_placed timestamptz;
BEGIN
  IF TG_OP = 'DELETE' THEN
    UPDATE public.constellation_anchor_cursor c
       SET revision = c.revision + 1
     WHERE c.viewer_id = OLD.viewer_id;
    RETURN OLD;
  END IF;

  _viewer_id := NEW.viewer_id;

  IF TG_OP = 'INSERT' THEN
    NEW.target_id := coalesce(NEW.person_id, NEW.beacon_id);
    NEW.target_kind := CASE WHEN NEW.person_id IS NOT NULL THEN 'PERSON' ELSE 'BEACON' END;
  ELSIF NEW.tombstone_at IS NULL AND num_nonnulls(NEW.person_id, NEW.beacon_id) = 0 THEN
    -- The target was deleted (FK SET NULL): keep the placement as it is.
    UPDATE public.constellation_anchor_cursor c
       SET revision = c.revision + 1
     WHERE c.viewer_id = _viewer_id
     RETURNING c.revision INTO _new_revision;
    IF FOUND THEN
      NEW.revision := _new_revision;
    END IF;
    NEW.tombstone_at := now();
    RETURN NEW;
  END IF;

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
$$
''',

  r'''
CREATE OR REPLACE FUNCTION public.constellation_anchor_apply_ops(
    p_viewer_id text,
    p_write boolean[],
    p_delete boolean[],
    p_target_kinds text[],
    p_target_ids text[],
    p_anchor_ids text[],
    p_x double precision[],
    p_y double precision[],
    p_coordinate_space_versions integer[],
    p_client_op_ids text[],
    p_fingerprints text[],
    p_results jsonb[],
    p_revisions bigint[]
) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  _n integer := coalesce(cardinality(p_client_op_ids), 0);
  _expected bigint;
  _revision bigint;
BEGIN
  IF _n = 0 THEN
    RETURN;
  END IF;
  -- Anchor writes in input order: the revision trigger advances the locked
  -- cursor by one per row, as the caller predicted.
  FOR i IN 1.._n LOOP
    CONTINUE WHEN NOT p_write[i];
    -- Target kinds are the wire values stored in the watermark table.
    IF p_delete[i] THEN
      -- By stored target identity, so a tombstone can be unpinned too.
      DELETE FROM public.constellation_anchor
      WHERE viewer_id = p_viewer_id
        AND target_kind = p_target_kinds[i]
        AND target_id = p_target_ids[i];
    ELSIF p_target_kinds[i] = 'PERSON' THEN
      UPDATE public.constellation_anchor
      SET x_units = p_x[i],
          y_units = p_y[i],
          coordinate_space_version = p_coordinate_space_versions[i]
      WHERE viewer_id = p_viewer_id AND person_id = p_target_ids[i];
    ELSE
      UPDATE public.constellation_anchor
      SET x_units = p_x[i],
          y_units = p_y[i],
          coordinate_space_version = p_coordinate_space_versions[i]
      WHERE viewer_id = p_viewer_id AND beacon_id = p_target_ids[i];
    END IF;
    IF NOT FOUND THEN
      IF p_delete[i] THEN
        -- Deleting a missing anchor still advances the cursor.
        UPDATE public.constellation_anchor_cursor
        SET revision = revision + 1
        WHERE viewer_id = p_viewer_id;
      ELSE
        INSERT INTO public.constellation_anchor (
          id, viewer_id, person_id, beacon_id,
          x_units, y_units, coordinate_space_version, revision, placed_at
        ) VALUES (
          p_anchor_ids[i], p_viewer_id,
          CASE WHEN p_target_kinds[i] = 'PERSON' THEN p_target_ids[i] END,
          CASE WHEN p_target_kinds[i] = 'BEACON' THEN p_target_ids[i] END,
          p_x[i], p_y[i], p_coordinate_space_versions[i], 0,
          'epoch'::timestamptz
        );
      END IF;
    END IF;
  END LOOP;

  -- Every write advanced the cursor exactly once, so the final revision
  -- proves each predicted one; a mismatch aborts rather than recording it.
  _expected := p_revisions[_n];
  SELECT c.revision INTO _revision
  FROM public.constellation_anchor_cursor c
  WHERE c.viewer_id = p_viewer_id;
  IF _revision IS DISTINCT FROM _expected THEN
    RAISE EXCEPTION 'constellation anchor batch revision drift for viewer %: expected %, found %',
      p_viewer_id, _expected, _revision;
  END IF;

  INSERT INTO public.constellation_anchor_target_watermark
    (viewer_id, target_kind, target_id, revision)
  SELECT DISTINCT ON (o.kind, o.id) p_viewer_id, o.kind, o.id, o.revision
  FROM unnest(p_write, p_target_kinds, p_target_ids, p_revisions)
    AS o(write, kind, id, revision)
  WHERE o.write
  ORDER BY o.kind, o.id, o.revision DESC
  ON CONFLICT (viewer_id, target_kind, target_id)
  DO UPDATE SET revision = EXCLUDED.revision;

  INSERT INTO public.constellation_anchor_op_log
    (viewer_id, client_op_id, fingerprint, result, revision)
  SELECT p_viewer_id, o.client_op_id, decode(o.fingerprint, 'hex'), o.result,
         o.revision
  FROM unnest(p_client_op_ids, p_fingerprints, p_results, p_revisions)
    AS o(client_op_id, fingerprint, result, revision);
END;
$$
''',
]);
