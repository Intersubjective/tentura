part of '_migrations.dart';

final m0021 = Migration('0021', [
  '''
ALTER TABLE public.beacon_evaluation
  ADD COLUMN IF NOT EXISTS status smallint NOT NULL DEFAULT 1;
''',
  '''
COMMENT ON COLUMN public.beacon_evaluation.status IS
  '0 draft, 1 submitted (open window), 2 final (window closed), 3 responded (reserved)';
''',
]);
