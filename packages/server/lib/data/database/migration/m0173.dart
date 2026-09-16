part of '_migrations.dart';

/// Issue #146 T11: co-participant bond (shared active request membership).
///
/// D4: the bond widens person visibility for forwarding only. It never feeds
/// discovery (`person_are_mutually_visible`, `constellation_trust_edges`, and
/// the D11 `discovered` clause stay trust-only).
final m0173 = Migration('0173', [
  r'''
CREATE OR REPLACE FUNCTION public.person_bond(a_id text, b_id text)
RETURNS boolean
  LANGUAGE sql
  STABLE
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
  );
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.person_bond_peers(p_viewer_id text)
RETURNS TABLE (peer_id text)
  LANGUAGE sql
  STABLE
  AS $$
SELECT DISTINCT mb.user_id::text
FROM public.beacon_member ma
JOIN public.beacon_member mb ON mb.beacon_id = ma.beacon_id
JOIN public.beacon b ON b.id = ma.beacon_id
WHERE ma.user_id = p_viewer_id
  AND mb.user_id <> p_viewer_id
  AND b.status IN (0, 5, 7, 8)
  AND NOT public.block_hides(p_viewer_id, mb.user_id);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.person_shared_contexts(p_viewer_id text, p_peer_id text)
RETURNS TABLE (beacon_id text, title text)
  LANGUAGE sql
  STABLE
  AS $$
SELECT DISTINCT ON (b.id) b.id::text, b.title::text
FROM public.beacon_member ma
JOIN public.beacon_member mb ON mb.beacon_id = ma.beacon_id
JOIN public.beacon b ON b.id = ma.beacon_id
WHERE ma.user_id = p_viewer_id
  AND mb.user_id = p_peer_id
  AND p_viewer_id <> p_peer_id
  AND b.status IN (0, 5, 7, 8)
  AND NOT public.block_hides(p_viewer_id, p_peer_id)
ORDER BY b.id
LIMIT 20;
$$;
''',
]);
