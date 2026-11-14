part of '_migrations.dart';

/// Facts on Posts: an archived (closed or expired) Post refuses fact writes,
/// and fact chat lines (markers 2, 3, 10, 11, 20) are neither the latest
/// message nor unread in `post_my_posts`.
final m0313 = Migration('0313', [
  r'''
CREATE FUNCTION public.beacon_fact_card_post_archive_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF public.discussion_internal_fixture_allowed() THEN
    RETURN NEW;
  END IF;

  IF NOT public.beacon_post_write_allowed(NEW.beacon_id, 'no_key_update') THEN
    RAISE EXCEPTION 'post_archived' USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$
''',
  // Never list pinned_by, last_edited_by or source_message_id: ON DELETE SET
  // NULL must keep working on an archived Post.
  '''
CREATE TRIGGER beacon_fact_card_post_archive_guard
  BEFORE INSERT OR UPDATE OF beacon_id, fact_text, visibility, status,
    revision_seq, last_edited_at, other_editor_count, history_truncated
  ON public.beacon_fact_card
  FOR EACH ROW EXECUTE FUNCTION public.beacon_fact_card_post_archive_guard()
''',
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
         left(coalesce(root.body, CASE WHEN b.status = 3 THEN b.description END), 280),
         left(latest.body, 280), latest.created_at,
         b.last_activity_at, pin.pinned_at, mute.muted_until,
         CASE WHEN b.status = 3 THEN 0 ELSE
         (SELECT count(*)::integer FROM public.beacon_room_message m
          WHERE m.beacon_id = b.id AND m.thread_item_id IS NULL
            AND m.author_id <> p_viewer
            AND m.system_message_kind IS NULL
            AND (m.semantic_marker IS NULL OR m.semantic_marker NOT IN (2, 3, 10, 11, 20))
            AND (seen.last_seen_at IS NULL OR m.created_at > seen.last_seen_at)) END,
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
      AND (m.semantic_marker IS NULL OR m.semantic_marker NOT IN (2, 3, 10, 11, 20))
    ORDER BY m.created_at DESC, m.id DESC LIMIT 1
  ) latest ON true
  LEFT JOIN public.beacon_pinned pin
    ON pin.beacon_id = b.id AND pin.user_id = p_viewer
  LEFT JOIN public.notification_beacon_mute mute
    ON mute.beacon_id = b.id AND mute.account_id = p_viewer
  LEFT JOIN public.beacon_room_seen seen
    ON seen.beacon_id = b.id AND seen.user_id = p_viewer
      AND seen.thread_item_id IS NULL
  WHERE b.kind = 1
    AND (b.status IN (0, 6) OR (b.status = 3 AND b.user_id = p_viewer))
    AND (b.user_id = p_viewer OR EXISTS (
      SELECT 1 FROM public.beacon_participant bp
      WHERE bp.beacon_id = b.id AND bp.user_id = p_viewer
        AND bp.role = 6 AND bp.room_access = 3
    ))
    AND public.beacon_can_read_content(b.id, p_viewer)
$$
''',
]);
