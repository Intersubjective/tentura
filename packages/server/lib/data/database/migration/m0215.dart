part of '_migrations.dart';

/// S15: open Post conversations, with viewer metadata and General unread count.
final m0215 = Migration('0215', [
  r'''
CREATE FUNCTION public.post_my_posts(p_viewer text)
RETURNS TABLE (
  id text, author_id text, author_name text, author_image_id text,
  root_excerpt text, last_message_excerpt text,
  last_message_at timestamp with time zone,
  last_activity_at timestamp with time zone,
  pinned_at timestamp with time zone, muted_until timestamp with time zone,
  unread_count integer, is_author boolean
)
LANGUAGE sql STABLE AS $$
  SELECT b.id, b.user_id, u.display_name, u.image_id::text,
         left(root.body, 280), left(latest.body, 280), latest.created_at,
         b.last_activity_at, pin.pinned_at, mute.muted_until,
         (SELECT count(*)::integer FROM public.beacon_room_message m
          WHERE m.beacon_id = b.id AND m.thread_item_id IS NULL
            AND m.author_id <> p_viewer
            AND (seen.last_seen_at IS NULL OR m.created_at > seen.last_seen_at)),
         b.user_id = p_viewer
  FROM public.beacon b
  JOIN public."user" u ON u.id = b.user_id
  LEFT JOIN public.beacon_room_message root
    ON root.id = b.post_root_message_id AND root.beacon_id = b.id
  LEFT JOIN LATERAL (
    SELECT m.body, m.created_at FROM public.beacon_room_message m
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
  WHERE b.kind = 1 AND b.status = 0
    AND (b.user_id = p_viewer OR EXISTS (
      SELECT 1 FROM public.beacon_participant bp
      WHERE bp.beacon_id = b.id AND bp.user_id = p_viewer
        AND bp.role = 6 AND bp.room_access = 3
    ))
    AND public.beacon_can_read_content(b.id, p_viewer)
$$
''',
]);
