part of '_migrations.dart';

/// Post admission (plan §4.2): a live forward edge to a Post admits the
/// recipient as an addressee (`role 6`, `room_access 3`); cancelling the last
/// live edge withdraws it. Addressees are not admitted helpers and Posts
/// create no person bond.
final m0210 = Migration('0210', [
  r'''
CREATE FUNCTION public.post_reconcile_admission(p_beacon text, p_user text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  _role smallint;
  _access smallint;
  _active boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.beacon WHERE id = p_beacon AND kind = 1 AND user_id <> p_user) THEN
    RETURN;
  END IF;
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
CREATE FUNCTION public.post_admission_on_forward_edge() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM public.post_reconcile_admission(NEW.beacon_id, NEW.recipient_id);
  RETURN NEW;
END
$$
''',
  '''
CREATE TRIGGER post_admission_on_forward_edge_insert_trg AFTER INSERT ON public.beacon_forward_edge FOR EACH ROW EXECUTE FUNCTION public.post_admission_on_forward_edge()
''',
  '''
CREATE TRIGGER post_admission_on_forward_edge_cancel_trg AFTER UPDATE OF cancelled_at ON public.beacon_forward_edge FOR EACH ROW EXECUTE FUNCTION public.post_admission_on_forward_edge()
''',
  r'''
CREATE OR REPLACE VIEW public.beacon_admitted_helper AS
 SELECT bp.beacon_id,
    bp.user_id
   FROM (public.beacon_participant bp
     JOIN public.beacon b ON ((b.id = bp.beacon_id)))
  WHERE ((bp.room_access = 3) AND (bp.role <> 6) AND (bp.user_id <> b.user_id) AND (NOT public.block_hides(b.user_id, bp.user_id)))
''',
  r'''
CREATE OR REPLACE FUNCTION public.person_bond(a_id text, b_id text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
SELECT nullif(btrim(coalesce(a_id, '')), '') IS NOT NULL
  AND nullif(btrim(coalesce(b_id, '')), '') IS NOT NULL
  AND a_id <> b_id
  AND NOT public.block_hides(a_id, b_id)
  AND EXISTS (
    SELECT 1
    FROM public.beacon_member ma
    JOIN public.beacon_member mb ON mb.beacon_id = ma.beacon_id
    JOIN public.beacon b ON b.id = ma.beacon_id
    WHERE ma.user_id = a_id
      AND mb.user_id = b_id
      AND b.status IN (0, 5, 7, 8)
      AND b.kind = 0
  );
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.person_bond_peers(p_viewer_id text) RETURNS TABLE(peer_id text)
    LANGUAGE sql STABLE
    AS $$
SELECT DISTINCT mb.user_id::text
FROM public.beacon_member ma
JOIN public.beacon_member mb ON mb.beacon_id = ma.beacon_id
JOIN public.beacon b ON b.id = ma.beacon_id
WHERE ma.user_id = p_viewer_id
  AND mb.user_id <> p_viewer_id
  AND b.status IN (0, 5, 7, 8)
  AND b.kind = 0
  AND NOT public.block_hides(p_viewer_id, mb.user_id);
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.person_shared_contexts(p_viewer_id text, p_peer_id text) RETURNS TABLE(beacon_id text, title text)
    LANGUAGE sql STABLE
    AS $$
SELECT DISTINCT ON (b.id) b.id::text, b.title::text
FROM public.beacon_member ma
JOIN public.beacon_member mb ON mb.beacon_id = ma.beacon_id
JOIN public.beacon b ON b.id = ma.beacon_id
WHERE ma.user_id = p_viewer_id
  AND mb.user_id = p_peer_id
  AND p_viewer_id <> p_peer_id
  AND b.status IN (0, 5, 7, 8)
  AND b.kind = 0
  AND NOT public.block_hides(p_viewer_id, p_peer_id)
ORDER BY b.id
LIMIT 20;
$$
''',
]);
