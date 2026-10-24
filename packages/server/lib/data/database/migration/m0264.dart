part of '_migrations.dart';

/// `person_temporary_forward_peers(viewer)` / `person_temporary_forward_visible
/// (viewer, peer)` (#699 A7a): a forwarded Request makes its author and its
/// holder temporarily visible to each other while the holder keeps it.
///
/// R is a Request (`kind = 0`) in the open family (0, 7, 8) with a live
/// forward edge, and no block between the pair. The holder keeps R while its
/// inbox item is needs-me or watching, or it has an active help offer on R.
/// Direction 1: the viewer holds R and sees its author. Direction 2: the
/// viewer authored R and sees its holder. An author cannot see a recipient's
/// rejection today, so direction 2 ends with R, not with the rejection.
final m0264 = Migration('0264', [
  r'''
CREATE FUNCTION public.person_temporary_forward_peers(p_viewer text) RETURNS TABLE(peer_id text, beacon_id text, direction smallint)
    LANGUAGE sql STABLE
    AS $$
SELECT b.user_id::text, b.id::text, 1::smallint
FROM public.beacon_forward_edge e
JOIN public.beacon b ON b.id = e.beacon_id
WHERE e.recipient_id = p_viewer
  AND e.cancelled_at IS NULL
  AND b.kind = 0
  AND b.status IN (0, 7, 8)
  AND b.user_id <> p_viewer
  AND NOT public.block_hides(p_viewer, b.user_id)
  AND (
    EXISTS (
      SELECT 1 FROM public.inbox_item ii
      WHERE ii.user_id = p_viewer AND ii.beacon_id = b.id
        AND ii.status IN (0, 1)
    )
    OR EXISTS (
      SELECT 1 FROM public.beacon_help_offer ho
      WHERE ho.user_id = p_viewer AND ho.beacon_id = b.id AND ho.status = 0
    )
  )
UNION ALL
SELECT e.recipient_id::text, b.id::text, 2::smallint
FROM public.beacon b
JOIN public.beacon_forward_edge e ON e.beacon_id = b.id
WHERE b.user_id = p_viewer
  AND e.cancelled_at IS NULL
  AND e.recipient_id <> p_viewer
  AND b.kind = 0
  AND b.status IN (0, 7, 8)
  AND NOT public.block_hides(p_viewer, e.recipient_id)
  AND (
    EXISTS (
      SELECT 1 FROM public.inbox_item ii
      WHERE ii.user_id = e.recipient_id AND ii.beacon_id = b.id
    )
    OR EXISTS (
      SELECT 1 FROM public.beacon_help_offer ho
      WHERE ho.user_id = e.recipient_id AND ho.beacon_id = b.id
        AND ho.status = 0
    )
  );
$$
''',
  r'''
CREATE FUNCTION public.person_temporary_forward_visible(p_viewer text, p_peer text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
SELECT EXISTS (
  SELECT 1 FROM public.person_temporary_forward_peers(p_viewer) t
  WHERE t.peer_id = p_peer
);
$$
''',
]);
