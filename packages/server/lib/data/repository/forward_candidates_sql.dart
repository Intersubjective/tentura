/// Membership wrap matching `mutually_visible_users` (m0142), returning
/// peer signal columns instead of `SETOF user`.
///
/// Do not alter `person_visibility_peers`. Normalize context in SQL only.
const kForwardCandidatesWrapSql = r'''
SELECT
  u.id AS peer_id,
  p.forward_mr,
  p.reverse_mr,
  p.viewer_explicitly_trusts_subject,
  p.subject_explicitly_trusts_viewer
FROM public.person_visibility_peers($1, public.cap_normalize_context($2)) p
INNER JOIN public."user" u ON u.id = p.peer_id
WHERE nullif(btrim($1), '') IS NOT NULL
  AND p.is_mutually_visible
  AND u.id <> $1
  AND NOT public.block_hides($1, u.id)
ORDER BY p.forward_mr DESC, u.display_name, u.id
LIMIT 500;
''';
