part of '_migrations.dart';

/// Inbox provenance applies the block wall (#188). The Hasura computed field
/// behind `inbox_item.inbox_provenance_data` delegated to the shared
/// `attention_provenance_data` body with `p_exclude_blocked = false`, so a
/// blocked sender's name, avatar, note and MR still reached the viewer, and
/// `totalDistinctSenders` counted them. It now passes `true`, like the
/// attention read path: the blocked sender leaves `senders[]`, the count and
/// `latestNoteForward` together, because the body filters one `edges` CTE.
final m0218 = Migration('0218', [
  r'''
CREATE OR REPLACE FUNCTION public.inbox_item_inbox_provenance_data(inbox_row public.inbox_item, hasura_session json) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  viewer_id text := nullif(trim(hasura_session ->> 'x-hasura-user-id'), '');
BEGIN
  IF viewer_id IS NULL THEN
    RETURN '{"senders":[],"totalDistinctSenders":0,"strongestNotePreview":""}';
  END IF;

  RETURN public.attention_provenance_data(
    inbox_row.beacon_id,
    inbox_row.user_id,
    viewer_id,
    inbox_row.context,
    true
  )::text;
END;
$$
''',
  '''
COMMENT ON FUNCTION public.attention_provenance_data(p_beacon_id text, p_recipient_id text, p_viewer_id text, p_inbox_context text, p_exclude_blocked boolean) IS 'The one forward-provenance body (card spec §4 / plan §0.1a). Returns the `inbox_provenance_data` JSON shape — senders[] {id, displayName, imageId, notePreview, reasonSlugs[], mr}, totalDistinctSenders, strongestNotePreview — plus `latestNoteForward` {forwardId, senderId, displayName, imageId, notePreview, reasonSlugs[], forwardedAt} or null (D-171-5a). Every selection reads from one filtered `edges` CTE: p_exclude_blocked drops blocked senders from the list, the count *and* the pinned forward. Both callers pass true since m0218 (issue #188).';
''',
]);
