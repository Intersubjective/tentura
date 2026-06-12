part of '_migrations.dart';

/// Coordination items: remind throttle + persisted staleness window preference.
final m0086 = Migration('0086', [
  '''
ALTER TABLE public.coordination_item
  ADD COLUMN IF NOT EXISTS last_reminded_at TIMESTAMPTZ;
''',
  '''
ALTER TABLE public.coordination_item
  ADD COLUMN IF NOT EXISTS stale_after_days SMALLINT;
''',
  '''
COMMENT ON COLUMN public.coordination_item.last_reminded_at IS
  'When a stale-item remind was last sent; 24h throttle per item';
''',
  '''
COMMENT ON COLUMN public.coordination_item.stale_after_days IS
  'Chosen follow-up window in days (0 = no deadline); set at publish';
''',
]);
