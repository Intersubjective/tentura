part of '_migrations.dart';

/// Trusted Field readers can load Request involvement and forward it without
/// prior participation. Mirrors the discoverability branch of content access;
/// hierarchy context alone still grants no involvement access. The outer
/// content predicate retains block, draft and deleted-state restrictions.
final m0280 = Migration('0280', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_can_read_involvement(p_beacon_id text, p_viewer_id text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
SELECT public.beacon_can_read_content(p_beacon_id, p_viewer_id)
  AND (
    EXISTS (
      SELECT 1 FROM public.beacon b
      WHERE b.id = p_beacon_id AND b.user_id = p_viewer_id
    )
    OR EXISTS (
      SELECT 1 FROM public.beacon_forward_edge fe
      WHERE fe.beacon_id = p_beacon_id
        AND (fe.sender_id = p_viewer_id OR fe.recipient_id = p_viewer_id)
        AND fe.cancelled_at IS NULL
    )
    OR EXISTS (
      SELECT 1 FROM public.beacon_help_offer ho
      WHERE ho.beacon_id = p_beacon_id
        AND ho.user_id = p_viewer_id
        AND ho.status = 0
    )
    OR EXISTS (
      SELECT 1 FROM public.beacon_participant bp
      WHERE bp.beacon_id = p_beacon_id
        AND bp.user_id = p_viewer_id
        AND (bp.role = 1 OR bp.room_access = 3)
    )
    OR EXISTS (
      SELECT 1 FROM public.beacon b
      WHERE b.id = p_beacon_id
        AND b.is_discoverable
        AND b.status IN (0, 7, 8)
        AND b.published_at IS NOT NULL
        AND b.user_id IS NOT NULL
        AND public.person_are_mutually_visible_cached(p_viewer_id, b.user_id, '')
    )
    OR EXISTS (
      SELECT 1 FROM public.beacon_steward bs
      WHERE bs.beacon_id = p_beacon_id AND bs.user_id = p_viewer_id
    )
  );
$$
''',
]);
