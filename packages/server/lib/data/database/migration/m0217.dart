part of '_migrations.dart';

/// Dismiss notes belong to the recipient, never to the forward edge (#137).
/// Historical rejection messages cannot be attributed to either dialog and
/// remain unchanged. Only new dismissals use this private column.
final m0217 = Migration('0217', [
  r'''
ALTER TABLE public.inbox_item
  ADD COLUMN private_note text NOT NULL DEFAULT '',
  ADD CONSTRAINT inbox_item_private_note_length
    CHECK (char_length(private_note) <= 200);
''',
  r'''
COMMENT ON COLUMN public.inbox_item.private_note IS
  'Owner-only Activity dismiss note; never propagated to beacon_forward_edge';
''',
]);
