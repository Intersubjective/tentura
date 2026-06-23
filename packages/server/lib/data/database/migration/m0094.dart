part of '_migrations.dart';

/// Drop redundant outward `public_status` columns; coordination_status is the single status field.
final m0094 = Migration('0094', [
  '''
ALTER TABLE public.beacon
  DROP COLUMN IF EXISTS public_status,
  DROP COLUMN IF EXISTS last_public_meaningful_change;
''',
]);
