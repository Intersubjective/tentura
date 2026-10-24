part of '_migrations.dart';

/// `person_auto_tags(viewer, peers)` (#699): the facts-derived automatic
/// people tags, one row per (peer, kind). Set-based, STABLE, no MeritRank
/// call, never a row for a peer a block hides from the viewer.
///
/// Kinds are the `PersonAutoTagKind` wire values: 0 mutual contact, 1 I trust,
/// 2 trusts me, 3 helped me, 4 I helped, 5 worked together, 6 invited,
/// 7 forwarded, 8 new on the Field. `n` is the number of Requests for
/// worked together and 1 otherwise; `direction` is set for invited only
/// (1 = they invited me, 2 = I invited them, 3 = both).
final m0263 = Migration('0263', [
  r'''
CREATE FUNCTION public.person_auto_tags(
  p_viewer text,
  p_peers text[] DEFAULT NULL
) RETURNS TABLE(peer_id text, kind smallint, n integer, direction smallint)
    LANGUAGE sql STABLE
    AS $$
WITH trust AS (
  SELECT CASE WHEN vo.subject = p_viewer THEN vo.object ELSE vo.subject END
           AS peer,
         bool_or(vo.subject = p_viewer) AS i_trust,
         bool_or(vo.object = p_viewer) AS trusts_me
    FROM public.vote_user vo
   WHERE vo.amount > 0
     AND (vo.subject = p_viewer OR vo.object = p_viewer)
     AND vo.subject <> vo.object
   GROUP BY 1
),
facts AS (
  SELECT peer, (CASE WHEN i_trust AND trusts_me THEN 0
                     WHEN i_trust THEN 1 ELSE 2 END)::smallint AS kind,
         1 AS n, 0::smallint AS direction
    FROM trust
  UNION ALL
  SELECT CASE WHEN b.user_id = p_viewer THEN bp.user_id ELSE b.user_id END,
         (CASE WHEN b.user_id = p_viewer THEN 3 ELSE 4 END)::smallint,
         1, 0::smallint
    FROM public.beacon b
    JOIN public.beacon_participant bp ON bp.beacon_id = b.id
   WHERE b.status IN (5, 6)
     AND (bp.role = 1 OR bp.room_access = 3)
     AND ((b.user_id = p_viewer AND bp.user_id <> p_viewer)
       OR (bp.user_id = p_viewer AND b.user_id <> p_viewer))
  UNION ALL
  SELECT mb.user_id, 5::smallint, count(DISTINCT mb.beacon_id)::integer,
         0::smallint
    FROM public.beacon_member me
    JOIN public.beacon_member mb
      ON mb.beacon_id = me.beacon_id AND mb.user_id <> p_viewer
    JOIN public.beacon b ON b.id = me.beacon_id AND b.kind = 0
   WHERE me.user_id = p_viewer
   GROUP BY mb.user_id
  UNION ALL
  SELECT CASE WHEN i.user_id = p_viewer THEN i.invited_id ELSE i.user_id END,
         6::smallint, 1,
         (CASE WHEN bool_or(i.user_id = p_viewer)
                    AND bool_or(i.invited_id = p_viewer) THEN 3
               WHEN bool_or(i.user_id = p_viewer) THEN 2 ELSE 1 END)::smallint
    FROM public.invitation i
   WHERE i.accepted_at IS NOT NULL
     AND i.user_id <> i.invited_id
     AND (i.user_id = p_viewer OR i.invited_id = p_viewer)
   GROUP BY 1
  UNION ALL
  SELECT DISTINCT CASE WHEN f.sender_id = p_viewer THEN f.recipient_id
                       ELSE f.sender_id END,
         7::smallint, 1, 0::smallint
    FROM public.beacon_forward_edge f
   WHERE (f.sender_id = p_viewer OR f.recipient_id = p_viewer)
     AND f.sender_id <> f.recipient_id
  UNION ALL
  SELECT fs.peer_id, 8::smallint, 1, 0::smallint
    FROM public.person_field_first_seen fs
   WHERE fs.viewer_id = p_viewer
     AND fs.first_seen_at > now() - interval '7 days'
)
SELECT f.peer, f.kind, f.n::integer, f.direction
  FROM facts f
 WHERE f.peer IS NOT NULL
   AND f.peer <> p_viewer
   AND (p_peers IS NULL OR f.peer = ANY (p_peers))
   AND NOT public.block_hides(p_viewer, f.peer)
$$
''',
]);
