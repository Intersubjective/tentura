part of '_migrations.dart';

/// Symmetric mutual visibility (Constellation D14).
final m0161 = Migration('0161', [
  r'''
CREATE OR REPLACE FUNCTION public.person_reciprocal_explicit_trust(
  a_id text, b_id text
) RETURNS boolean LANGUAGE sql STABLE AS $$
SELECT EXISTS (
    SELECT 1 FROM public.vote_user vu
    WHERE vu.subject = a_id AND vu.object = b_id AND vu.amount > 0)
  AND EXISTS (
    SELECT 1 FROM public.vote_user vu
    WHERE vu.subject = b_id AND vu.object = a_id AND vu.amount > 0);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.person_are_mutually_visible(
  a_id text, b_id text, ctx text
) RETURNS boolean LANGUAGE sql STABLE AS $$
SELECT CASE
  WHEN nullif(trim(coalesce(a_id, '')), '') IS NULL THEN false
  WHEN nullif(trim(coalesce(b_id, '')), '') IS NULL THEN false
  WHEN a_id = b_id THEN false
  WHEN public.person_reciprocal_explicit_trust(a_id, b_id) THEN true          -- §8.4/1
  WHEN public.person_is_mutually_visible(a_id, b_id, coalesce(ctx, '')) THEN true
  ELSE public.person_is_mutually_visible(b_id, a_id, coalesce(ctx, ''))       -- D14 OR-closure
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.person_visible_peers_symmetric(
  viewer_id text, ctx text
) RETURNS TABLE (peer_id text) LANGUAGE sql STABLE AS $$
WITH n AS (
  SELECT nullif(trim(coalesce(viewer_id, '')), '') AS v_id,
         coalesce(ctx, '')                          AS v_ctx
)
SELECT c.peer_id::text
FROM n
CROSS JOIN public.person_visibility_peers(n.v_id, n.v_ctx) c
WHERE n.v_id IS NOT NULL
  AND c.peer_id::text <> n.v_id
  AND CASE
        WHEN c.is_mutually_visible THEN true                    -- forward: already in the row
        ELSE public.person_is_mutually_visible(c.peer_id::text, n.v_id, n.v_ctx)
      END;                                                      -- reverse: forward misses only
$$;
''',
]);
