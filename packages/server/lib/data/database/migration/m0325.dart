part of '_migrations.dart';

/// Filter Post hierarchy invalidations while a deleted bud is still readable.
final m0325 = Migration('0325', [
  r'''
CREATE OR REPLACE FUNCTION public.notify_beacon_hierarchy_beacon_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  child_row record;
  parent_id text;
  projected_changed boolean;
  post_bud_delete boolean := false;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.published_at IS NOT NULL AND NEW.parent_beacon_id IS NOT NULL THEN
      PERFORM public.realtime_beacon_hierarchy_emit(
        NEW.parent_beacon_id, 'insert', ARRAY[]::text[], NEW.id
      );
    END IF;
    RETURN NULL;
  END IF;

  IF OLD.kind = 0 AND OLD.published_at IS NOT NULL
     AND OLD.parent_beacon_id IS NOT NULL
     AND (TG_OP = 'DELETE' OR (OLD.status <> 2 AND NEW.status = 2)) THEN
    post_bud_delete := EXISTS (
      SELECT 1 FROM public.beacon WHERE id = OLD.parent_beacon_id AND kind = 1
    );
  END IF;

  IF TG_WHEN = 'BEFORE' THEN
    IF post_bud_delete THEN
      -- The usual child read filter still sees the bud and its grants here.
      -- PostgreSQL delivers the queued hint only after the write commits.
      PERFORM public.realtime_beacon_hierarchy_emit(
        OLD.parent_beacon_id, lower(TG_OP), ARRAY[]::text[], OLD.id
      );
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF OLD.published_at IS NOT NULL AND OLD.parent_beacon_id IS NOT NULL THEN
      IF NOT post_bud_delete THEN
        PERFORM public.realtime_beacon_hierarchy_emit(
          OLD.parent_beacon_id, 'delete', ARRAY[]::text[], OLD.id
        );
      END IF;
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
    PERFORM public.realtime_beacon_hierarchy_emit(
      NEW.parent_beacon_id, 'update', ARRAY[]::text[], NEW.id
    );
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
    IF parent_id IS NOT NULL AND NOT post_bud_delete THEN
      PERFORM public.realtime_beacon_hierarchy_emit(
        parent_id, 'update', ARRAY[]::text[], NEW.id
      );
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
    IF TG_WHEN = 'BEFORE' THEN
      RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;
    RETURN NULL;
END;
$$
''',
  '''
CREATE TRIGGER beacon_hierarchy_bud_delete_notify_trg
BEFORE UPDATE OF status OR DELETE ON public.beacon
FOR EACH ROW EXECUTE FUNCTION public.notify_beacon_hierarchy_beacon_change()
''',
]);
