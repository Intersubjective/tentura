part of '_migrations.dart';

final m0058 = Migration('0058', [
  '''
ALTER TABLE public.beacon_forward_edge
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS recipient_read_at timestamptz;
''',
]);
