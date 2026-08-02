part of '_migrations.dart';

/// User blocking enforcement: beacon visibility wall and signup inheritance.
/// See docs/plans/user-block-implementation-spec.md §3.1 and §4.
final m0136 = Migration('0136', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_can_read_content(
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
    WHEN b.user_id = p_viewer_id THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_forward_edge fe
      WHERE fe.beacon_id = p_beacon_id
        AND fe.recipient_id = p_viewer_id
        AND fe.cancelled_at IS NULL
    ) THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_participant bp
      WHERE bp.beacon_id = p_beacon_id
        AND bp.user_id = p_viewer_id
        AND (bp.role = 1 OR bp.room_access = 3)
    ) THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_help_offer ho
      WHERE ho.beacon_id = p_beacon_id
        AND ho.user_id = p_viewer_id
        AND ho.status = 0
    ) THEN true
    ELSE false
  END
  FROM public.beacon b
  WHERE b.id = p_beacon_id
), false);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.user_block_inherit_on_invite()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.descendant_user_id IS NULL OR NEW.ancestor_user_id IS NULL THEN
    RETURN NULL;
  END IF;
  INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
  SELECT ub.blocker_id, NEW.descendant_user_id, ub.origin_id
  FROM public.user_block ub
  WHERE ub.blocked_id = NEW.ancestor_user_id
    AND ub.blocker_id <> NEW.descendant_user_id
    AND EXISTS (
      SELECT 1 FROM public.user_block_intent i
      WHERE i.blocker_id = ub.blocker_id
        AND i.blocked_id = ub.origin_id
        AND i.cascade_mode > 0)
  ON CONFLICT DO NOTHING;
  RETURN NULL;
END; $$;
''',
  '''
CREATE OR REPLACE TRIGGER user_block_inherit_trg
  AFTER INSERT ON public.invite_genealogy
  FOR EACH ROW EXECUTE FUNCTION public.user_block_inherit_on_invite();
''',
]);
