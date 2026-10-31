part of '_migrations.dart';

/// #525 — a card's unread count counts only the message kinds its preview can
/// show: system lines (`system_message_kind` set) are skipped by both, so a
/// card never reads «2 unread» beside a preview with nothing new.
///
/// Body and function attributes copied from m0276 with the one extra
/// predicate; the return type is unchanged, so `CREATE OR REPLACE` suffices.
/// The in-room unread anchor is a separate read and is not touched.
final m0278 = Migration('0278', [
  r'''
CREATE OR REPLACE FUNCTION public.post_my_posts(p_viewer text)
RETURNS TABLE (
  id text, author_id text, author_name text, author_image_id text,
  root_excerpt text, last_message_excerpt text,
  last_message_at timestamp with time zone,
  last_activity_at timestamp with time zone,
  pinned_at timestamp with time zone, muted_until timestamp with time zone,
  unread_count integer, is_author boolean, status smallint,
  expires_at timestamp with time zone, last_message_id text
)
LANGUAGE sql STABLE AS $$
  SELECT b.id, b.user_id, u.display_name, u.image_id::text,
         left(root.body, 280), left(latest.body, 280), latest.created_at,
         b.last_activity_at, pin.pinned_at, mute.muted_until,
         (SELECT count(*)::integer FROM public.beacon_room_message m
          WHERE m.beacon_id = b.id AND m.thread_item_id IS NULL
            AND m.author_id <> p_viewer
            AND m.system_message_kind IS NULL
            AND (seen.last_seen_at IS NULL OR m.created_at > seen.last_seen_at)),
         b.user_id = p_viewer,
         b.status, b.expires_at, latest.id
  FROM public.beacon b
  JOIN public."user" u ON u.id = b.user_id
  LEFT JOIN public.beacon_room_message root
    ON root.id = b.post_root_message_id AND root.beacon_id = b.id
  LEFT JOIN LATERAL (
    SELECT m.id, m.body, m.created_at FROM public.beacon_room_message m
    WHERE m.beacon_id = b.id AND m.thread_item_id IS NULL
      AND m.system_message_kind IS NULL
    ORDER BY m.created_at DESC, m.id DESC LIMIT 1
  ) latest ON true
  LEFT JOIN public.beacon_pinned pin
    ON pin.beacon_id = b.id AND pin.user_id = p_viewer
  LEFT JOIN public.notification_beacon_mute mute
    ON mute.beacon_id = b.id AND mute.account_id = p_viewer
  LEFT JOIN public.beacon_room_seen seen
    ON seen.beacon_id = b.id AND seen.user_id = p_viewer
      AND seen.thread_item_id IS NULL
  WHERE b.kind = 1 AND b.status IN (0, 6)
    AND (b.user_id = p_viewer OR EXISTS (
      SELECT 1 FROM public.beacon_participant bp
      WHERE bp.beacon_id = b.id AND bp.user_id = p_viewer
        AND bp.role = 6 AND bp.room_access = 3
    ))
    AND public.beacon_can_read_content(b.id, p_viewer)
$$

''',
]);
