/// Activity grouped by discussion and member without advancing read cursors.
/// [beaconIdsSql] is a trusted SQL array expression, never user input.
/// Each lateral source is keyed to one requested discussion before grouping,
/// so a batch cannot turn into a scan of messages in unrelated discussions.
String participantActivitySql({required String beaconIdsSql}) =>
    '''
SELECT requested.beacon_id, activity.user_id, max(activity.at) AS active_at
FROM unnest($beaconIdsSql) AS requested(beacon_id)
CROSS JOIN LATERAL (
  SELECT s.user_id, max(s.last_seen_at) AS at
  FROM public.beacon_room_seen s
  WHERE s.beacon_id = requested.beacon_id AND s.thread_item_id IS NULL
  GROUP BY s.user_id
  UNION ALL
  SELECT e.sender_id, max(e.created_at)
  FROM public.beacon_forward_edge e
  WHERE e.beacon_id = requested.beacon_id
  GROUP BY e.sender_id
  UNION ALL
  SELECT i.user_id, max(i.created_at)
  FROM public.invitation i
  WHERE i.beacon_id = requested.beacon_id
  GROUP BY i.user_id
  UNION ALL
  SELECT m.author_id, max(m.created_at)
  FROM public.beacon_room_message m
  WHERE m.beacon_id = requested.beacon_id AND m.thread_item_id IS NULL
  GROUP BY m.author_id
) activity
GROUP BY requested.beacon_id, activity.user_id
''';
