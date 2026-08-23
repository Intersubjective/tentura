/// One-statement Forward candidate context snapshot.
///
/// Candidate eligibility is the canonical mutual-visibility projection. The
/// graph is the capped MeritRank snapshot requested by the product contract.
/// Edges touching people hidden from the viewer are removed before the domain
/// receives the snapshot.
const kForwardCandidateContextSql = r'''
WITH params AS MATERIALIZED (
  SELECT
    $1::text AS viewer_id,
    $2::text AS candidate_id,
    public.cap_normalize_context($3::text) AS normalized_context
),
authorized AS MATERIALIZED (
  SELECT
    p.viewer_id,
    p.candidate_id,
    p.normalized_context,
    EXISTS (
      SELECT 1
      FROM public.person_visibility_peers(
        p.viewer_id,
        p.normalized_context
      ) peer
      INNER JOIN public."user" candidate ON candidate.id = peer.peer_id
      WHERE peer.peer_id = p.candidate_id
        AND peer.is_mutually_visible
        AND p.candidate_id <> p.viewer_id
        AND NOT public.block_hides(p.viewer_id, p.candidate_id)
    ) AS candidate_eligible
  FROM params p
),
raw_edges AS MATERIALIZED (
  SELECT g.src::text AS src, g.dst::text AS dst
  FROM authorized a
  CROSS JOIN LATERAL public.mr_graph(
    a.viewer_id,
    a.candidate_id,
    a.normalized_context,
    true,
    0,
    100
  ) g
  WHERE a.candidate_eligible
),
visible_edges AS MATERIALIZED (
  SELECT DISTINCT e.src, e.dst
  FROM raw_edges e
  CROSS JOIN authorized a
  WHERE e.src IS NOT NULL
    AND e.dst IS NOT NULL
    AND NOT public.block_hides(a.viewer_id, e.src)
    AND NOT public.block_hides(a.viewer_id, e.dst)
)
SELECT
  a.candidate_eligible,
  e.src,
  e.dst,
  su.id AS src_user_id,
  su.display_name AS src_display_name,
  si.id::text AS src_image_id,
  si.hash AS src_image_hash,
  si.height AS src_image_height,
  si.width AS src_image_width,
  si.author_id AS src_image_author_id,
  si.created_at::text AS src_image_created_at,
  du.id AS dst_user_id,
  du.display_name AS dst_display_name,
  di.id::text AS dst_image_id,
  di.hash AS dst_image_hash,
  di.height AS dst_image_height,
  di.width AS dst_image_width,
  di.author_id AS dst_image_author_id,
  di.created_at::text AS dst_image_created_at
FROM authorized a
LEFT JOIN visible_edges e ON a.candidate_eligible
LEFT JOIN public."user" su ON su.id = e.src
LEFT JOIN public.image si ON si.id = su.image_id
LEFT JOIN public."user" du ON du.id = e.dst
LEFT JOIN public.image di ON di.id = du.image_id
ORDER BY e.src, e.dst;
''';
