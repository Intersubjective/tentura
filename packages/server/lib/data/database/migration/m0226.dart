part of '_migrations.dart';

/// Set-based companion of `beacon_can_read_content` (#229).
///
/// `beacon_readable_ids(viewer, ids)` returns the subset of [ids] the viewer
/// may read, with the same verdicts as the per-row function. The viewer's
/// facts (forwards, participation, offers, stewardship, hierarchy
/// membership, mutual-visibility peers) are read once as sets instead of
/// one probe per beacon, and the author block check runs once per author.
final m0226 = Migration('0226', [
  r'''
CREATE FUNCTION public.beacon_readable_ids(p_viewer_id text, p_ids text[]) RETURNS SETOF text
    LANGUAGE sql STABLE
    AS $$
WITH cand AS (
  SELECT b.id, b.user_id, b.status, b.is_discoverable, b.published_at,
         b.parent_beacon_id
  FROM public.beacon b
  WHERE b.id = ANY(p_ids)
),
blocked_author AS (
  SELECT a.user_id, public.block_hides(a.user_id, p_viewer_id) AS hidden
  FROM (SELECT DISTINCT user_id FROM cand) a
),
fwd AS (
  SELECT fe.beacon_id FROM public.beacon_forward_edge fe
  WHERE fe.recipient_id = p_viewer_id AND fe.cancelled_at IS NULL
    AND fe.beacon_id = ANY(p_ids)
),
part AS (
  SELECT bp.beacon_id FROM public.beacon_participant bp
  WHERE bp.user_id = p_viewer_id AND (bp.role = 1 OR bp.room_access = 3)
),
offer AS (
  SELECT ho.beacon_id FROM public.beacon_help_offer ho
  WHERE ho.user_id = p_viewer_id AND ho.status = 0
    AND ho.beacon_id = ANY(p_ids)
),
stew AS (
  SELECT bs.beacon_id FROM public.beacon_steward bs
  WHERE bs.user_id = p_viewer_id
),
-- Beacons the viewer is a member of (mirrors beacon_member, see m0193).
member AS (
  SELECT mb.id
  FROM public.beacon mb
  WHERE mb.user_id = p_viewer_id
    AND mb.status NOT IN (2, 3) AND mb.published_at IS NOT NULL
  UNION
  SELECT mb.id
  FROM public.beacon mb
  WHERE mb.id IN (SELECT beacon_id FROM stew UNION SELECT beacon_id FROM part)
    AND mb.status NOT IN (2, 3) AND mb.published_at IS NOT NULL
    AND NOT public.block_hides(mb.user_id, p_viewer_id)
),
member_ancestors AS (
  SELECT DISTINCT a.ancestor_id
  FROM public.beacon_ancestor a
  WHERE a.beacon_id IN (SELECT id FROM member)
),
peers AS MATERIALIZED (
  SELECT public.person_visible_peer_ids_tx(p_viewer_id, '') AS ids
  WHERE EXISTS (SELECT 1 FROM cand WHERE is_discoverable)
),
-- Mutual visibility once per distinct discoverable author, not per beacon.
mutual AS (
  SELECT a.user_id,
         public.person_reciprocal_explicit_trust(p_viewer_id, a.user_id)
           OR a.user_id = ANY(coalesce((SELECT ids FROM peers), '{}'::text[])) AS ok
  FROM (
    SELECT DISTINCT user_id FROM cand
    WHERE is_discoverable AND status IN (0, 7, 8)
      AND published_at IS NOT NULL AND user_id IS NOT NULL
      AND user_id <> p_viewer_id
  ) a
)
SELECT c.id
FROM cand c
JOIN blocked_author ba ON ba.user_id IS NOT DISTINCT FROM c.user_id
WHERE CASE
  WHEN ba.hidden THEN false
  WHEN c.status = 3 THEN c.user_id = p_viewer_id
  WHEN c.status = 2 THEN false
  WHEN c.user_id = p_viewer_id THEN true
  WHEN c.id IN (SELECT beacon_id FROM fwd) THEN true
  WHEN c.id IN (SELECT beacon_id FROM part) THEN true
  WHEN c.id IN (SELECT beacon_id FROM offer) THEN true
  WHEN c.is_discoverable
    AND c.status IN (0, 7, 8)
    AND c.published_at IS NOT NULL
    AND c.user_id IS NOT NULL
    AND c.user_id IN (SELECT user_id FROM mutual WHERE ok)
    THEN true
  WHEN c.id IN (SELECT beacon_id FROM stew) THEN true
  WHEN c.parent_beacon_id IS NOT NULL
    AND c.published_at IS NOT NULL
    AND c.parent_beacon_id IN (SELECT id FROM member) THEN true
  WHEN c.published_at IS NOT NULL
    AND c.id IN (SELECT ancestor_id FROM member_ancestors) THEN true
  ELSE false
END;
$$
''',
]);
