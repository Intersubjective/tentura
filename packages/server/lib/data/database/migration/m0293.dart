part of '_migrations.dart';

/// Post admission takes the per-Post advisory lock instead of the global
/// hierarchy lock: `post_reconcile_admission` locks the Post itself and marks
/// its own participant writes, and the participant statement trigger skips the
/// hierarchy lock only for marked writes. Every other participant write still
/// serialises on the hierarchy lock. m0210 and m0193 stay as shipped.
final m0293 = Migration('0293', [
  r'''
CREATE OR REPLACE FUNCTION public.post_reconcile_admission(p_beacon text, p_user text) RETURNS void
    LANGUAGE plpgsql
    SET tentura.post_admission TO 'on'
    AS $$
DECLARE
  _role smallint;
  _access smallint;
  _active boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.beacon WHERE id = p_beacon AND kind = 1 AND user_id <> p_user) THEN
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_beacon, 4242));
  INSERT INTO public.beacon_participant (id, beacon_id, user_id, role, room_access)
  VALUES (concat('P', "substring"(replace((gen_random_uuid())::text, '-'::text, ''::text), 1, 12)), p_beacon, p_user, 6, 0)
  ON CONFLICT (beacon_id, user_id) DO NOTHING;
  SELECT role, room_access INTO _role, _access
    FROM public.beacon_participant
   WHERE beacon_id = p_beacon AND user_id = p_user
     FOR UPDATE;
  IF _role <> 6 OR _access = 5 THEN
    RETURN;
  END IF;
  _active := EXISTS (
    SELECT 1 FROM public.beacon_forward_edge
     WHERE beacon_id = p_beacon AND recipient_id = p_user AND cancelled_at IS NULL);
  IF _active AND _access <> 3 THEN
    UPDATE public.beacon_participant SET room_access = 3, updated_at = now()
     WHERE beacon_id = p_beacon AND user_id = p_user;
  ELSIF NOT _active AND _access = 3 THEN
    UPDATE public.beacon_participant SET room_access = 0, updated_at = now()
     WHERE beacon_id = p_beacon AND user_id = p_user;
  END IF;
END
$$
''',
  r'''
CREATE FUNCTION public.beacon_participant_enforce_mutation_lock_stmt() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF current_setting('tentura.post_admission', true) IS DISTINCT FROM 'on' THEN
    PERFORM public.beacon_hierarchy_acquire_mutation_lock();
  END IF;
  RETURN NULL;
END;
$$
''',
  '''
DROP TRIGGER beacon_hierarchy_participant_mutation_lock_trg ON public.beacon_participant
''',
  '''
CREATE TRIGGER beacon_hierarchy_participant_mutation_lock_trg BEFORE INSERT OR DELETE OR UPDATE ON public.beacon_participant FOR EACH STATEMENT EXECUTE FUNCTION public.beacon_participant_enforce_mutation_lock_stmt()
''',
]);
