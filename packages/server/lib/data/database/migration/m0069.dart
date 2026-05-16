part of '_migrations.dart';

/// Coordination items: optional stale-at deadline for Items tab countdown.
final m0069 = Migration('0069', [
  '''
ALTER TABLE public.coordination_item
  ADD COLUMN IF NOT EXISTS stale_at TIMESTAMPTZ;
''',
  '''
COMMENT ON COLUMN public.coordination_item.stale_at IS
  'When this item becomes stale; shown as remaining time on Items tab cards';
''',
]);
