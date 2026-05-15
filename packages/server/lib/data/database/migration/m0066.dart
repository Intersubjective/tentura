part of '_migrations.dart';

/// Self-Ask: persisted origin on coordination_item.
final m0066 = Migration('0066', [
  '''
ALTER TABLE public.coordination_item
  ADD COLUMN IF NOT EXISTS source smallint NOT NULL DEFAULT 0;
''',
  '''
COMMENT ON COLUMN public.coordination_item.source IS
  '0=default, 1=self_promise';
''',
]);
