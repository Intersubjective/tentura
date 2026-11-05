import '../database/sql/post_unread_sql.dart';

export '../database/sql/request_unread_sql.dart' show questionsMessageCountsSql;

/// Mixed Request/Post rows are used only by pinned-item projection. Ordinary
/// Request and Post reads omit the other kind's SQL, including its subplans.
String fieldHasUnreadSql({bool includePosts = false}) => _fieldHasUnreadSql(
  includePosts
      ? 'CASE WHEN b.kind = 1 THEN ($_postUnreadSql) ELSE ($_requestUnreadSql) END'
      : _requestUnreadSql,
);

String fieldPostHasUnreadSql() => _fieldHasUnreadSql(_postUnreadSql);

String _fieldHasUnreadSql(String unreadMessages) =>
    '''
(
  NOT EXISTS (
    SELECT 1 FROM public.notification_beacon_mute mute
    WHERE mute.account_id = \$1 AND mute.beacon_id = b.id
      AND (mute.muted_until IS NULL OR mute.muted_until > now())
  )
  AND (
    (b.user_id <> \$1 AND NOT EXISTS (
      SELECT 1 FROM public.beacon_field_seen opened
      WHERE opened.user_id = \$1 AND opened.beacon_id = b.id
    ) AND NOT EXISTS (
      SELECT 1 FROM public.beacon_room_seen opened
      WHERE opened.user_id = \$1 AND opened.beacon_id = b.id
        AND (b.kind = 1 OR public.beacon_effective_admission(b.id, \$1))
    ))
    OR ($unreadMessages)
  )
)
''';

// Share the Post card's predicate without inlining its whole feed read.
final _postUnreadSql =
    '''
EXISTS (
  SELECT 1 FROM public.beacon_room_message m
  LEFT JOIN public.beacon_room_seen seen
    ON seen.beacon_id = m.beacon_id AND seen.user_id = \$1
    AND seen.thread_item_id IS NULL
  WHERE m.beacon_id = b.id AND ${postUnreadMessageSql(r'$1')}
)
''';

final _requestUnreadSql =
    '${requestUnreadMessageCountSql(viewer: r'$1', beaconId: 'b.id')} > 0';

/// The card and Field use the same cached PostgreSQL count definition.
String requestUnreadMessageCountSql({
  required String viewer,
  required String beaconId,
}) => 'public.request_unread_message_count($viewer, $beaconId)';
