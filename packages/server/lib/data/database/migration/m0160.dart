part of '_migrations.dart';

/// Per-request discoverability opt-out (Constellation D4/D12).
final m0160 = Migration('0160', [
  r'''
ALTER TABLE public.beacon ADD COLUMN IF NOT EXISTS is_discoverable boolean;
''',
  r'''
UPDATE public.beacon SET is_discoverable = true WHERE is_discoverable IS NULL;   -- D12
''',
  r'''
ALTER TABLE public.beacon ALTER COLUMN is_discoverable SET DEFAULT true;
''',
  r'''
ALTER TABLE public.beacon ALTER COLUMN is_discoverable SET NOT NULL;
''',
  r'''
CREATE INDEX IF NOT EXISTS beacon_discoverable_author_idx
  ON public.beacon (user_id)
  WHERE is_discoverable AND status IN (0, 7, 8) AND published_at IS NOT NULL;
''',
]);
