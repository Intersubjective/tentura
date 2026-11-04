/// Membership wrap matching `mutually_visible_users` (m0142), returning
/// peer signal columns instead of `SETOF user`, followed by bond-only peers.
/// Both groups carry the start of their current mutual trust edges.
///
/// Do not alter `person_visibility_peers`. Normalize context in SQL only.
const kForwardCandidatesWrapSql = r'''
WITH visible AS (
SELECT
  u.id AS peer_id,
  p.forward_mr,
  p.reverse_mr,
  p.viewer_explicitly_trusts_subject,
  p.subject_explicitly_trusts_viewer
FROM public.person_visibility_peers($1, public.cap_normalize_context($2)) p
INNER JOIN public."user" u ON u.id = p.peer_id
WHERE nullif(btrim($1), '') IS NOT NULL
  AND public.person_are_mutually_visible(
    $1,
    u.id,
    public.cap_normalize_context($2)
  )
  AND u.id <> $1
  AND NOT public.block_hides($1, u.id)
ORDER BY p.forward_mr DESC, u.display_name, u.id
LIMIT 500
), candidates AS (
  SELECT v.*, false AS bond_only FROM visible v
  UNION ALL
  SELECT b.peer_id, 0::double precision, 0::double precision, false, false, true
  FROM public.person_bond_peers($1) b
  WHERE NOT EXISTS (SELECT 1 FROM visible v WHERE v.peer_id = b.peer_id)
)
SELECT c.*,
  CASE WHEN outgoing.subject IS NOT NULL AND incoming.subject IS NOT NULL
    THEN greatest(outgoing.created_at, incoming.created_at)
  END AS mutual_since
FROM candidates c
INNER JOIN public."user" u ON u.id = c.peer_id
LEFT JOIN public.user_trust_edge outgoing
  ON outgoing.subject = $1 AND outgoing.object = c.peer_id
  AND outgoing.target_w > 0
LEFT JOIN public.user_trust_edge incoming
  ON incoming.subject = c.peer_id AND incoming.object = $1
  AND incoming.target_w > 0
ORDER BY c.bond_only, c.forward_mr DESC, u.display_name, c.peer_id;
''';
