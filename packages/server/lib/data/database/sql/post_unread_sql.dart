/// Canonical Post unread predicate, shared with `post_my_posts` (m0278).
/// The caller supplies message `m` and the viewer's General cursor `seen`.
String postUnreadMessageSql(String viewer) =>
    'm.thread_item_id IS NULL\n'
    '            AND m.author_id <> $viewer\n'
    '            AND m.system_message_kind IS NULL\n'
    '            AND (seen.last_seen_at IS NULL OR m.created_at > seen.last_seen_at)';
