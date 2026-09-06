part of '_migrations.dart';

/// One-edge hierarchy read predicates, effective-admission helper, and
/// mutation-lock enforcement for authorization-changing SQL paths (Task 03).
final m0155 = Migration('0155', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_effective_admission(
  p_beacon_id text,
  p_viewer_id text
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT COALESCE((
  SELECT CASE
    WHEN public.block_hides(b.user_id, p_viewer_id) THEN false
    WHEN b.user_id = p_viewer_id THEN true
    WHEN EXISTS (
      SELECT 1
      FROM public.beacon_steward bs
      WHERE bs.beacon_id = p_beacon_id
        AND bs.user_id = p_viewer_id
    ) THEN true
    WHEN EXISTS (
      SELECT 1
      FROM public.beacon_participant bp
      WHERE bp.beacon_id = p_beacon_id
        AND bp.user_id = p_viewer_id
        AND (bp.role = 1 OR bp.room_access = 3)
    ) THEN true
    ELSE false
  END
  FROM public.beacon b
  WHERE b.id = p_beacon_id
), false);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_can_read_linked_detail(
  p_beacon_id text,
  p_viewer_id text
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT COALESCE((
  SELECT CASE
    WHEN public.block_hides(b.user_id, p_viewer_id) THEN false
    WHEN b.status = 3 THEN b.user_id = p_viewer_id
    WHEN b.status = 2 THEN false
    WHEN public.beacon_can_read_content(p_beacon_id, p_viewer_id) THEN true
    WHEN b.parent_beacon_id IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.beacon parent
        WHERE parent.id = b.parent_beacon_id
          AND parent.status NOT IN (2, 3)
          AND parent.published_at IS NOT NULL
          AND NOT public.block_hides(parent.user_id, p_viewer_id)
          AND public.beacon_effective_admission(parent.id, p_viewer_id)
      ) THEN true
    WHEN EXISTS (
      SELECT 1
      FROM public.beacon child
      WHERE child.parent_beacon_id = b.id
        AND child.status NOT IN (2, 3)
        AND child.published_at IS NOT NULL
        AND NOT public.block_hides(child.user_id, p_viewer_id)
        AND public.beacon_effective_admission(child.id, p_viewer_id)
    ) THEN true
    ELSE false
  END
  FROM public.beacon b
  WHERE b.id = p_beacon_id
), false);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_get_can_read_linked_detail(
  beacon_row public.beacon,
  hasura_session json
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT public.beacon_can_read_linked_detail(
  beacon_row.id,
  (hasura_session ->> 'x-hasura-user-id')::text
);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_get_effective_admission(
  beacon_row public.beacon,
  hasura_session json
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT public.beacon_effective_admission(
  beacon_row.id,
  (hasura_session ->> 'x-hasura-user-id')::text
);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_hierarchy_acquire_mutation_lock()
RETURNS void
  LANGUAGE plpgsql
  AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0));
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_hierarchy_enforce_mutation_lock_stmt()
RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  PERFORM public.beacon_hierarchy_acquire_mutation_lock();
  RETURN NULL;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_hierarchy_enforce_mutation_lock_row()
RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  PERFORM public.beacon_hierarchy_acquire_mutation_lock();
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;
''',
  '''
DROP TRIGGER IF EXISTS beacon_hierarchy_participant_mutation_lock_trg
  ON public.beacon_participant;
''',
  '''
CREATE TRIGGER beacon_hierarchy_participant_mutation_lock_trg
  BEFORE INSERT OR UPDATE OR DELETE ON public.beacon_participant
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.beacon_hierarchy_enforce_mutation_lock_stmt();
''',
  '''
DROP TRIGGER IF EXISTS beacon_hierarchy_steward_mutation_lock_trg
  ON public.beacon_steward;
''',
  '''
CREATE TRIGGER beacon_hierarchy_steward_mutation_lock_trg
  BEFORE INSERT OR UPDATE OR DELETE ON public.beacon_steward
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.beacon_hierarchy_enforce_mutation_lock_stmt();
''',
  '''
DROP TRIGGER IF EXISTS beacon_hierarchy_user_block_mutation_lock_trg
  ON public.user_block;
''',
  '''
CREATE TRIGGER beacon_hierarchy_user_block_mutation_lock_trg
  BEFORE INSERT OR UPDATE OR DELETE ON public.user_block
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.beacon_hierarchy_enforce_mutation_lock_stmt();
''',
  '''
DROP TRIGGER IF EXISTS beacon_hierarchy_beacon_status_mutation_lock_trg
  ON public.beacon;
''',
  '''
CREATE TRIGGER beacon_hierarchy_beacon_status_mutation_lock_trg
  BEFORE UPDATE OF status, user_id ON public.beacon
  FOR EACH ROW
  WHEN (
    OLD.status IS DISTINCT FROM NEW.status
    OR OLD.user_id IS DISTINCT FROM NEW.user_id
  )
  EXECUTE FUNCTION public.beacon_hierarchy_enforce_mutation_lock_row();
''',
  '''
DROP TRIGGER IF EXISTS beacon_hierarchy_room_message_delete_mutation_lock_trg
  ON public.beacon_room_message;
''',
  '''
CREATE TRIGGER beacon_hierarchy_room_message_delete_mutation_lock_trg
  BEFORE DELETE ON public.beacon_room_message
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.beacon_hierarchy_enforce_mutation_lock_stmt();
''',
  r'''
REVOKE ALL ON TABLE public.beacon_child_commands FROM PUBLIC;
''',
  r'''
REVOKE ALL ON TABLE public.beacon_promotions FROM PUBLIC;
''',
  r'''
REVOKE ALL ON TABLE public.beacon_hierarchy_events FROM PUBLIC;
''',
  r'''
REVOKE ALL ON TABLE public.beacon_hierarchy_deliveries FROM PUBLIC;
''',
]);
