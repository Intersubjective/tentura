import 'forward_candidates_sql.dart' show kMutualSinceSql;

/// Sort keys for the People tab, one row per person the viewer (`$1`) trusts.
///
/// `new_at` is the latest of the invite acceptance (the viewer's own invite),
/// the viewer's trust edge creation and the start of mutual trust, kept only
/// when it falls in the last 7 days; `new_reason` names whichever produced it
/// (mutual wins a tie with trusted, since mutual trust includes the viewer's
/// edge). `last_interaction_at` is the latest forward between the two in
/// either direction, room message by the person in a room the viewer belongs
/// to, trust edge change in either direction, or invite acceptance.
const kPeopleListMetaSql =
    '''
WITH keyed AS (
  SELECT
    outgoing.object AS peer_id,
    outgoing.created_at AS trusted_at,
    outgoing.updated_at AS outgoing_changed_at,
    incoming_any.updated_at AS incoming_changed_at,
    invited.accepted_at AS invited_at,
    '''
    '''$kMutualSinceSql'''
    r'''

 AS mutual_since,
    forwarded.at AS forwarded_at,
    spoke.at AS spoke_at
  FROM public.user_trust_edge outgoing
  LEFT JOIN public.user_trust_edge incoming
    ON incoming.subject = outgoing.object AND incoming.object = $1
    AND incoming.target_w > 0
  LEFT JOIN public.user_trust_edge incoming_any
    ON incoming_any.subject = outgoing.object AND incoming_any.object = $1
  LEFT JOIN LATERAL (
    SELECT max(i.accepted_at) AS accepted_at
    FROM public.invitation i
    WHERE i.user_id = $1 AND i.invited_id = outgoing.object
  ) invited ON true
  LEFT JOIN LATERAL (
    SELECT max(f.created_at) AS at
    FROM public.beacon_forward_edge f
    WHERE (f.sender_id = $1 AND f.recipient_id = outgoing.object)
       OR (f.sender_id = outgoing.object AND f.recipient_id = $1)
  ) forwarded ON true
  LEFT JOIN LATERAL (
    SELECT max(m.created_at) AS at
    FROM public.beacon_room_message m
    WHERE m.author_id = outgoing.object
      AND EXISTS (
        SELECT 1 FROM public.beacon_member mine
        WHERE mine.beacon_id = m.beacon_id AND mine.user_id = $1
      )
  ) spoke ON true
  WHERE outgoing.subject = $1
    AND outgoing.target_w > 0
    AND outgoing.object <> $1
), newest AS (
  SELECT k.*, greatest(k.invited_at, k.trusted_at, k.mutual_since) AS new_at
  FROM keyed k
)
SELECT
  n.peer_id,
  CASE WHEN n.new_at > now() - interval '7 days' THEN n.new_at END AS new_since,
  CASE WHEN n.new_at > now() - interval '7 days' THEN
    CASE n.new_at
      WHEN n.mutual_since THEN 'mutual'
      WHEN n.invited_at THEN 'invite'
      ELSE 'trusted'
    END
  END AS new_reason,
  greatest(
    n.invited_at,
    n.forwarded_at,
    n.spoke_at,
    n.outgoing_changed_at,
    n.incoming_changed_at
  ) AS last_interaction_at
FROM newest n
ORDER BY n.peer_id;
''';
