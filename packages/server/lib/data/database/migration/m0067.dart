part of '_migrations.dart';

/// Draft Ask: owner-only unpublished coordination_item rows.
final m0067 = Migration('0067', [
  '''
ALTER TABLE public.coordination_item
  ADD COLUMN IF NOT EXISTS published boolean NOT NULL DEFAULT false;
''',
  '''
UPDATE public.coordination_item
   SET published = true;
''',
  '''
COMMENT ON COLUMN public.coordination_item.published IS
  'false = draft (owner-only), true = live coordination item';
''',
]);
