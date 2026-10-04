part of '_migrations.dart';

/// Post schema (plan §4.1): `beacon.kind` (0 request, 1 post), the forward
/// policy (0 closed, 1 open; one-way on a published Post), `last_activity_at`
/// kept by AFTER INSERT triggers, the Post root message and
/// `beacon_pinned.pinned_at`.
final m0209 = Migration('0209', [
  '''
ALTER TABLE public.beacon
    ADD COLUMN kind smallint DEFAULT 0 NOT NULL,
    ADD COLUMN forward_policy smallint DEFAULT 1 NOT NULL,
    ADD COLUMN last_activity_at timestamp with time zone,
    ADD COLUMN post_root_message_id text REFERENCES public.beacon_room_message(id) ON DELETE SET NULL
''',
  '''
ALTER TABLE public.beacon
    ADD CONSTRAINT beacon_kind_range CHECK (kind IN (0, 1))
''',
  '''
ALTER TABLE public.beacon
    ADD CONSTRAINT beacon_forward_policy_ck CHECK (forward_policy IN (0, 1) AND (kind = 1 OR forward_policy = 1))
''',
  '''
ALTER TABLE public.beacon
    ADD CONSTRAINT beacon_post_shape_ck CHECK (kind = 0 OR (status IN (0, 2, 3) AND is_discoverable = false AND parent_beacon_id IS NULL AND start_at IS NULL AND end_at IS NULL AND title = '' AND description = '' AND cover_image_id IS NULL))
''',
  r'''
CREATE FUNCTION public.beacon_kind_policy_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.kind = 0 AND NEW.kind = 1 THEN
    RAISE EXCEPTION 'beacon kind cannot change from request to post' USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.forward_policy = 1 AND NEW.forward_policy = 0 AND OLD.status <> 3 THEN
    RAISE EXCEPTION 'forward policy is one-way' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END
$$
''',
  '''
CREATE TRIGGER beacon_kind_policy_guard_trg BEFORE UPDATE OF kind, forward_policy ON public.beacon FOR EACH ROW EXECUTE FUNCTION public.beacon_kind_policy_guard()
''',
  '''
ALTER TABLE public.beacon_pinned ADD COLUMN pinned_at timestamp with time zone DEFAULT now() NOT NULL
''',
  '''
UPDATE public.beacon b SET last_activity_at = coalesce((SELECT max(m.created_at) FROM public.beacon_room_message m WHERE m.beacon_id = b.id AND m.system_message_kind IS NULL), b.published_at, b.created_at)
''',
  r'''
CREATE FUNCTION public.beacon_bump_last_activity(p_beacon text, p_at timestamp with time zone) RETURNS void
    LANGUAGE sql
    AS $$
  UPDATE public.beacon SET last_activity_at = GREATEST(coalesce(last_activity_at, p_at), p_at) WHERE id = p_beacon
$$
''',
  r'''
CREATE FUNCTION public.beacon_room_message_bump_activity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.system_message_kind IS NULL THEN
    PERFORM public.beacon_bump_last_activity(NEW.beacon_id, NEW.created_at);
  END IF;
  RETURN NEW;
END
$$
''',
  '''
CREATE TRIGGER beacon_room_message_bump_activity_trg AFTER INSERT ON public.beacon_room_message FOR EACH ROW EXECUTE FUNCTION public.beacon_room_message_bump_activity()
''',
  r'''
CREATE FUNCTION public.beacon_room_message_reaction_bump_activity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_beacon text;
BEGIN
  SELECT m.beacon_id INTO v_beacon FROM public.beacon_room_message m WHERE m.id = NEW.message_id;
  IF v_beacon IS NOT NULL THEN
    PERFORM public.beacon_bump_last_activity(v_beacon, NEW.created_at);
  END IF;
  RETURN NEW;
END
$$
''',
  '''
CREATE TRIGGER beacon_room_message_reaction_bump_activity_trg AFTER INSERT ON public.beacon_room_message_reaction FOR EACH ROW EXECUTE FUNCTION public.beacon_room_message_reaction_bump_activity()
''',
  r'''
CREATE FUNCTION public.beacon_forward_edge_bump_activity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM public.beacon_bump_last_activity(NEW.beacon_id, NEW.created_at);
  RETURN NEW;
END
$$
''',
  '''
CREATE TRIGGER beacon_forward_edge_bump_activity_trg AFTER INSERT ON public.beacon_forward_edge FOR EACH ROW EXECUTE FUNCTION public.beacon_forward_edge_bump_activity()
''',
]);
