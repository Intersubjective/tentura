import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';

import 'questions_audience_sql.dart';

/// Shared by the Request card's discussion count and the Field unread flag.
/// The caller supplies message `m` and its viewer's General cursor `seen`.
String discussionUnreadMessageSql(String viewer) =>
    '''
m.author_id <> $viewer
AND m.system_message_kind IS NULL
AND (m.semantic_marker IS NULL OR m.semantic_marker NOT IN
  (${kBeaconRoomMembershipLineMarkers.join(', ')}))
AND (seen.last_seen_at IS NULL OR m.created_at > seen.last_seen_at)
''';

/// Questions counts after the caller has checked `questions_access_levels`.
/// Used by both the Questions read and the Field, with the same scope cursor
/// and message visibility. System lines contribute no unread messages, and
/// nothing is unread for a reader outside the Questions audience (someone who
/// only found a discoverable Request and never wrote there).
String questionsMessageCountsSql({
  required String lobbyId,
  required String viewer,
}) =>
    '''
SELECT count(*)::integer AS message_count,
  (CASE WHEN ${questionsAudienceCandidateSql(lobbyId: lobbyId, viewer: viewer)}
    THEN count(*) FILTER (WHERE m.author_id <> $viewer
      AND m.system_message_kind IS NULL
      AND (s.last_seen_at IS NULL OR m.created_at > s.last_seen_at))
    ELSE 0
  END)::integer AS unread_count
FROM public.beacon_room_message m
LEFT JOIN public.beacon_room_seen s
  ON s.thread_item_id = m.thread_item_id AND s.user_id = $viewer
  AND s.beacon_id = m.beacon_id
WHERE m.thread_item_id = $lobbyId
  AND (m.author_id IS NULL OR NOT public.block_hides(m.author_id, $viewer))
''';

/// Unread discussion messages of [beaconId], zero without room access.
String requestDiscussionUnreadCountSql({
  required String viewer,
  required String beaconId,
}) =>
    '''
CASE WHEN public.beacon_effective_admission($beaconId, $viewer) THEN (
    SELECT count(*)::integer FROM public.beacon_room_message m
    LEFT JOIN public.beacon_room_seen seen
      ON seen.beacon_id = m.beacon_id AND seen.user_id = $viewer
      AND seen.thread_item_id IS NULL
    WHERE m.beacon_id = $beaconId AND m.thread_item_id IS NULL
      AND ${discussionUnreadMessageSql(viewer)}
  ) ELSE 0 END''';

/// Unread Questions messages of [beaconId] with the Questions scope's own
/// cursor, zero without Questions access. Correlate the Questions policy to
/// `ci`, so it cannot become an outer-beacon initplan that rechecks the read
/// wall when no Questions scope exists.
String requestQuestionsUnreadCountSql({
  required String viewer,
  required String beaconId,
}) =>
    '''
COALESCE((
    SELECT q.unread_count
    FROM public.coordination_item ci
    CROSS JOIN LATERAL (
      ${questionsMessageCountsSql(lobbyId: 'ci.id', viewer: viewer)}
    ) q
    WHERE ci.beacon_id = $beaconId AND ci.kind = ${CoordinationItemKind.lobby.smallintValue}
      AND EXISTS (
        SELECT 1 FROM public.questions_access_levels(
          ci.beacon_id, ARRAY[$viewer]::text[]
        ) access WHERE access.access > 0
      )
  ), 0)''';

/// The Request card total and Field flag share both room-access decisions and
/// message rules. Each scope uses its own cursor; unreadable rooms add zero.
String requestUnreadMessageCountBodySql({
  required String viewer,
  required String beaconId,
}) =>
    '''
(
  ${requestDiscussionUnreadCountSql(viewer: viewer, beaconId: beaconId)}
  + ${requestQuestionsUnreadCountSql(viewer: viewer, beaconId: beaconId)}
)
''';
