part of '_migrations.dart';

/// Realtime invalidation producers for nested-request hierarchy projections
/// (plan §6.3 / Task 14).
final m0159 = Migration('0159', [
  r'''
CREATE OR REPLACE FUNCTION public.realtime_beacon_hierarchy_recipients(
  p_projection_owner_beacon_id text
) RETURNS text[]
  LANGUAGE sql
  STABLE
  AS $$
WITH owner AS (
  SELECT b.user_id AS owner_id, b.parent_beacon_id
  FROM public.beacon b
  WHERE b.id = p_projection_owner_beacon_id
),
direct_admission AS (
  SELECT q.user_id
  FROM owner o
  CROSS JOIN LATERAL (
    SELECT o.owner_id AS user_id
    WHERE o.owner_id IS NOT NULL AND o.owner_id <> ''
    UNION ALL
    SELECT bs.user_id
    FROM public.beacon_steward bs
    WHERE bs.beacon_id = p_projection_owner_beacon_id
    UNION ALL
    SELECT bp.user_id
    FROM public.beacon_participant bp
    WHERE bp.beacon_id = p_projection_owner_beacon_id
      AND (bp.role = 1 OR bp.room_access = 3)
  ) q
  WHERE NOT public.block_hides(o.owner_id, q.user_id)
),
parent_linked AS (
  SELECT q.user_id
  FROM owner o
  JOIN public.beacon parent ON parent.id = o.parent_beacon_id
  CROSS JOIN LATERAL (
    SELECT parent.user_id AS user_id
    WHERE parent.user_id IS NOT NULL AND parent.user_id <> ''
    UNION ALL
    SELECT bs.user_id
    FROM public.beacon_steward bs
    WHERE bs.beacon_id = parent.id
    UNION ALL
    SELECT bp.user_id
    FROM public.beacon_participant bp
    WHERE bp.beacon_id = parent.id
      AND (bp.role = 1 OR bp.room_access = 3)
  ) q
  WHERE o.parent_beacon_id IS NOT NULL
    AND parent.status NOT IN (2, 3)
    AND parent.published_at IS NOT NULL
    AND NOT public.block_hides(parent.user_id, q.user_id)
    AND NOT public.block_hides(o.owner_id, q.user_id)
)
SELECT COALESCE(
  ARRAY(
    SELECT DISTINCT user_id
    FROM (
      SELECT user_id FROM direct_admission
      UNION ALL
      SELECT user_id FROM parent_linked
    ) recipients
    WHERE user_id IS NOT NULL AND user_id <> ''
    ORDER BY user_id
    LIMIT 2000
  ),
  ARRAY[]::text[]
);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.realtime_beacon_hierarchy_emit(
  p_projection_owner_beacon_id text,
  p_event text,
  p_extra_user_ids text[] DEFAULT ARRAY[]::text[]
) RETURNS void
  LANGUAGE plpgsql
  AS $$
DECLARE
  user_ids text[];
BEGIN
  IF p_projection_owner_beacon_id IS NULL OR p_projection_owner_beacon_id = '' THEN
    RETURN;
  END IF;

  user_ids := public.realtime_beacon_hierarchy_recipients(
    p_projection_owner_beacon_id
  ) || COALESCE(p_extra_user_ids, ARRAY[]::text[]);

  PERFORM public.emit_realtime_entity_change(
    'beacon_hierarchy',
    p_projection_owner_beacon_id,
    p_event,
    user_ids
  );
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_beacon_hierarchy_beacon_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  child_row record;
  parent_id text;
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

  IF parent_id IS NOT NULL AND (
    OLD.title IS DISTINCT FROM NEW.title
    OR OLD.status IS DISTINCT FROM NEW.status
    OR OLD.user_id IS DISTINCT FROM NEW.user_id
  ) THEN
    PERFORM public.realtime_beacon_hierarchy_emit(parent_id, 'update');
  END IF;

  IF OLD.status IS DISTINCT FROM NEW.status AND NEW.status IN (2, 3) THEN
    PERFORM public.realtime_beacon_hierarchy_emit(NEW.id, 'update');
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
CREATE OR REPLACE FUNCTION public.notify_beacon_hierarchy_promotion_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  child_id text;
BEGIN
  child_id := COALESCE(NEW.child_beacon_id, OLD.child_beacon_id);
  PERFORM public.realtime_beacon_hierarchy_emit(child_id, lower(TG_OP));
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'notify_beacon_hierarchy_promotion_change failed without aborting write: %',
      SQLERRM;
    RETURN NULL;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_beacon_hierarchy_admission_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  beacon_id text;
  parent_id text;
  affected_user_id text;
  extra_users text[] := ARRAY[]::text[];
BEGIN
  IF TG_TABLE_NAME = 'beacon_participant' THEN
    beacon_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    affected_user_id := COALESCE(NEW.user_id, OLD.user_id);
  ELSIF TG_TABLE_NAME = 'beacon_steward' THEN
    beacon_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
    affected_user_id := COALESCE(NEW.user_id, OLD.user_id);
  ELSIF TG_TABLE_NAME = 'user_block' THEN
    affected_user_id := COALESCE(NEW.blocked_id, OLD.blocked_id);
    extra_users := ARRAY[
      COALESCE(NEW.blocker_id, OLD.blocker_id),
      COALESCE(NEW.blocked_id, OLD.blocked_id)
    ];
    FOR beacon_id IN
      SELECT DISTINCT q.beacon_id
      FROM (
        SELECT b.id AS beacon_id
        FROM public.beacon b
        WHERE b.user_id IN (
          COALESCE(NEW.blocker_id, OLD.blocker_id),
          COALESCE(NEW.blocked_id, OLD.blocked_id)
        )
        UNION
        SELECT b.id
        FROM public.beacon b
        JOIN public.beacon parent ON parent.id = b.parent_beacon_id
        WHERE parent.user_id IN (
          COALESCE(NEW.blocker_id, OLD.blocker_id),
          COALESCE(NEW.blocked_id, OLD.blocked_id)
        )
          AND b.published_at IS NOT NULL
        UNION
        SELECT parent.id
        FROM public.beacon b
        JOIN public.beacon parent ON parent.id = b.parent_beacon_id
        WHERE b.user_id IN (
          COALESCE(NEW.blocker_id, OLD.blocker_id),
          COALESCE(NEW.blocked_id, OLD.blocked_id)
        )
          AND b.published_at IS NOT NULL
      ) q
      LIMIT 50
    LOOP
      PERFORM public.realtime_beacon_hierarchy_emit(
        beacon_id,
        lower(TG_OP),
        extra_users
      );
    END LOOP;
    RETURN NULL;
  ELSE
    RETURN NULL;
  END IF;

  IF affected_user_id IS NOT NULL AND affected_user_id <> '' THEN
    extra_users := extra_users || ARRAY[affected_user_id];
  END IF;

  PERFORM public.realtime_beacon_hierarchy_emit(
    beacon_id,
    lower(TG_OP),
    extra_users
  );

  SELECT b.parent_beacon_id
  INTO parent_id
  FROM public.beacon b
  WHERE b.id = beacon_id;

  IF parent_id IS NOT NULL AND parent_id <> '' THEN
    PERFORM public.realtime_beacon_hierarchy_emit(
      parent_id,
      lower(TG_OP),
      extra_users
    );
  END IF;

  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'notify_beacon_hierarchy_admission_change failed without aborting write: %',
      SQLERRM;
    RETURN NULL;
END;
$$;
''',
  '''
DROP TRIGGER IF EXISTS beacon_hierarchy_beacon_notify_trg ON public.beacon;
''',
  r'''
CREATE TRIGGER beacon_hierarchy_beacon_notify_trg
  AFTER INSERT OR UPDATE OR DELETE ON public.beacon
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_beacon_hierarchy_beacon_change();
''',
  '''
DROP TRIGGER IF EXISTS beacon_hierarchy_promotion_notify_trg
  ON public.beacon_promotions;
''',
  r'''
CREATE TRIGGER beacon_hierarchy_promotion_notify_trg
  AFTER INSERT OR UPDATE OR DELETE ON public.beacon_promotions
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_beacon_hierarchy_promotion_change();
''',
  '''
DROP TRIGGER IF EXISTS beacon_hierarchy_participant_notify_trg
  ON public.beacon_participant;
''',
  r'''
CREATE TRIGGER beacon_hierarchy_participant_notify_trg
  AFTER INSERT OR UPDATE OR DELETE ON public.beacon_participant
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_beacon_hierarchy_admission_change();
''',
  '''
DROP TRIGGER IF EXISTS beacon_hierarchy_steward_notify_trg
  ON public.beacon_steward;
''',
  r'''
CREATE TRIGGER beacon_hierarchy_steward_notify_trg
  AFTER INSERT OR UPDATE OR DELETE ON public.beacon_steward
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_beacon_hierarchy_admission_change();
''',
  '''
DROP TRIGGER IF EXISTS beacon_hierarchy_user_block_notify_trg
  ON public.user_block;
''',
  r'''
CREATE TRIGGER beacon_hierarchy_user_block_notify_trg
  AFTER INSERT OR DELETE ON public.user_block
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_beacon_hierarchy_admission_change();
''',
]);
