part of '_migrations.dart';

/// Per-helper free-text role label shown under chat avatars (People tab editable).
final m0177 = Migration('0177', [
  '''
ALTER TABLE public.beacon_help_offer
  ADD COLUMN IF NOT EXISTS role_label text;
''',
  '''
COMMENT ON COLUMN public.beacon_help_offer.role_label IS
  'Optional short in-request role label for the helper (max 32 chars, UI-edited)';
''',
]);
