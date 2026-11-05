import 'forward_candidates_sql.dart' show kMutualSinceSql;

/// Sort keys for the People tab, one row per person the viewer (`$1`) trusts.
///
/// `new_at` is the latest of the invite acceptance (the viewer's own invite),
/// the viewer's trust edge creation and the start of mutual trust, kept only
/// when it falls in the last 7 days; `new_reason` names whichever produced it
/// (invite wins a tie with mutual, and mutual wins a tie with trusted, since
/// mutual trust includes the viewer's edge). People in a block with the viewer,
/// in either direction, are not listed. `last_interaction_at` is the latest
/// active (not cancelled) forward between the two in either direction, General
/// room message by the person in a room the viewer belongs to (no system
/// lines, no Questions or other item threads), trust edge creation in either
/// direction (never `updated_at`, which trust maintenance rewrites), or invite
/// acceptance.
const kPeopleListMetaSql =
    '''
WITH keyed AS (
  SELECT
    outgoing.object AS peer_id,
    outgoing.created_at AS trusted_at,
    incoming_any.created_at AS incoming_created_at,
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
    WHERE f.cancelled_at IS NULL
      AND ((f.sender_id = $1 AND f.recipient_id = outgoing.object)
        OR (f.sender_id = outgoing.object AND f.recipient_id = $1))
  ) forwarded ON true
  LEFT JOIN LATERAL (
    SELECT max(m.created_at) AS at
    FROM public.beacon_room_message m
    WHERE m.author_id = outgoing.object
      AND m.thread_item_id IS NULL
      AND m.system_message_kind IS NULL
      AND (m.semantic_marker IS NULL OR m.semantic_marker NOT IN (1, 2, 3))
      AND EXISTS (
        SELECT 1 FROM public.beacon_member mine
        WHERE mine.beacon_id = m.beacon_id AND mine.user_id = $1
      )
  ) spoke ON true
  WHERE outgoing.subject = $1
    AND outgoing.target_w > 0
    AND outgoing.object <> $1
    AND NOT public.block_hides($1, outgoing.object)
), newest AS (
  SELECT k.*, greatest(k.invited_at, k.trusted_at, k.mutual_since) AS new_at
  FROM keyed k
)
SELECT
  n.peer_id,
  CASE WHEN n.new_at > now() - interval '7 days' THEN n.new_at END AS new_since,
  CASE WHEN n.new_at > now() - interval '7 days' THEN
    CASE n.new_at
      WHEN n.invited_at THEN 'invite'
      WHEN n.mutual_since THEN 'mutual'
      ELSE 'trusted'
    END
  END AS new_reason,
  greatest(
    n.invited_at,
    n.forwarded_at,
    n.spoke_at,
    n.trusted_at,
    n.incoming_created_at
  ) AS last_interaction_at
FROM newest n
ORDER BY n.peer_id;
''';
