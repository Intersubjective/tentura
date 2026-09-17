part of '_migrations.dart';

/// Issue #153: invalidate parent hierarchy (and child preview aggregates) when
/// projected card fields or preview-profile identities change. Participant
/// admission already emits parent+child via m0159; this migration does not
/// key off involvement `beacon_help_offer`.
final m0175 = Migration('0175', [
  r'''
CREATE OR REPLACE FUNCTION public.notify_beacon_hierarchy_beacon_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  child_row record;
  parent_id text;
  projected_changed boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.published_at IS NOT NULL AND NEW.parent_beacon_id IS NOT NULL THEN
      PERFORM public.realtime_beacon_hierarchy_emit(NEW.parent_beacon_id, 'insert');
    END IF;
    RETURN NULL;
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF OLD.published_at IS NOT NULL AND OLD.parent_beacon_id IS NOT NULL THEN
      PERFORM public.realtime_beacon_hierarchy_emit(OLD.parent_beacon_id, 'delete');
      PERFORM public.realtime_beacon_hierarchy_emit(OLD.id, 'delete');
    ELSIF OLD.published_at IS NOT NULL THEN
      PERFORM public.realtime_beacon_hierarchy_emit(OLD.id, 'delete');
      FOR child_row IN
        SELECT b.id
        FROM public.beacon b
        WHERE b.parent_beacon_id = OLD.id
          AND b.published_at IS NOT NULL
      LOOP
        PERFORM public.realtime_beacon_hierarchy_emit(child_row.id, 'delete');
      END LOOP;
    END IF;
    RETURN NULL;
  END IF;

  -- Draft edits stay on the ordinary beacon channel for the owner only.
  IF NEW.published_at IS NULL THEN
    RETURN NULL;
  END IF;

  IF OLD.published_at IS NULL AND NEW.published_at IS NOT NULL
     AND NEW.parent_beacon_id IS NOT NULL THEN
    PERFORM public.realtime_beacon_hierarchy_emit(NEW.parent_beacon_id, 'update');
    RETURN NULL;
  END IF;

  parent_id := NEW.parent_beacon_id;

  projected_changed :=
    OLD.title IS DISTINCT FROM NEW.title
    OR OLD.status IS DISTINCT FROM NEW.status
    OR OLD.user_id IS DISTINCT FROM NEW.user_id
    OR OLD.description IS DISTINCT FROM NEW.description
    OR OLD.cover_source IS DISTINCT FROM NEW.cover_source
    OR OLD.cover_image_id IS DISTINCT FROM NEW.cover_image_id
    OR OLD.cover_thumb_image_id IS DISTINCT FROM NEW.cover_thumb_image_id
    OR OLD.primary_need_slug IS DISTINCT FROM NEW.primary_need_slug
    OR OLD.needs IS DISTINCT FROM NEW.needs
    OR OLD.status_changed_at IS DISTINCT FROM NEW.status_changed_at;

  IF projected_changed THEN
    -- Chat preview listens on the child aggregate id; Now list on the parent.
    PERFORM public.realtime_beacon_hierarchy_emit(NEW.id, 'update');
    IF parent_id IS NOT NULL THEN
      PERFORM public.realtime_beacon_hierarchy_emit(parent_id, 'update');
    END IF;
  END IF;

  IF OLD.status IS DISTINCT FROM NEW.status AND NEW.status IN (2, 3) THEN
    FOR child_row IN
      SELECT b.id
      FROM public.beacon b
      WHERE b.parent_beacon_id = NEW.id
        AND b.published_at IS NOT NULL
    LOOP
      PERFORM public.realtime_beacon_hierarchy_emit(child_row.id, 'update');
    END LOOP;
  END IF;

  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'notify_beacon_hierarchy_beacon_change failed without aborting write: %',
      SQLERRM;
    RETURN NULL;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_beacon_hierarchy_profile_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  beacon_id text;
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RETURN NULL;
  END IF;

  IF NOT (
    OLD.display_name IS DISTINCT FROM NEW.display_name
    OR OLD.image_id IS DISTINCT FROM NEW.image_id
  ) THEN
    RETURN NULL;
  END IF;

  -- Owned published beacons (+ their parents) and admitted-helper memberships.
  FOR beacon_id IN
    SELECT DISTINCT q.beacon_id
    FROM (
      SELECT b.id AS beacon_id
      FROM public.beacon b
      WHERE b.user_id = NEW.id
        AND b.published_at IS NOT NULL
      UNION
      SELECT b.parent_beacon_id
      FROM public.beacon b
      WHERE b.user_id = NEW.id
        AND b.published_at IS NOT NULL
        AND b.parent_beacon_id IS NOT NULL
      UNION
      SELECT bah.beacon_id
      FROM public.beacon_admitted_helper bah
      WHERE bah.user_id = NEW.id
      UNION
      SELECT b.parent_beacon_id
      FROM public.beacon_admitted_helper bah
      JOIN public.beacon b ON b.id = bah.beacon_id
      WHERE bah.user_id = NEW.id
        AND b.parent_beacon_id IS NOT NULL
    ) q
    LIMIT 50
  LOOP
    PERFORM public.realtime_beacon_hierarchy_emit(beacon_id, 'update');
  END LOOP;

  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'notify_beacon_hierarchy_profile_change failed without aborting write: %',
      SQLERRM;
    RETURN NULL;
END;
$$;
''',
  '''
DROP TRIGGER IF EXISTS beacon_hierarchy_profile_notify_trg ON public."user";
''',
  '''
CREATE TRIGGER beacon_hierarchy_profile_notify_trg
  AFTER UPDATE ON public."user"
  FOR EACH ROW
  WHEN (
    OLD.display_name IS DISTINCT FROM NEW.display_name
    OR OLD.image_id IS DISTINCT FROM NEW.image_id
  )
  EXECUTE FUNCTION public.notify_beacon_hierarchy_profile_change();
''',
]);
