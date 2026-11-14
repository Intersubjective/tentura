/// Canonical Post unread predicate, shared with `post_my_posts` (m0313).
/// Fact chat lines (markers 2, 3, 10, 11, 20) never count as unread.
/// The caller supplies message `m` and the viewer's General cursor `seen`.
String postUnreadMessageSql(String viewer) =>
    'm.thread_item_id IS NULL\n'
    '            AND m.author_id <> $viewer\n'
    '            AND m.system_message_kind IS NULL\n'
    '            AND (m.semantic_marker IS NULL\n'
    '              OR m.semantic_marker NOT IN (2, 3, 10, 11, 20))\n'
    '            AND (seen.last_seen_at IS NULL OR m.created_at > seen.last_seen_at)';
