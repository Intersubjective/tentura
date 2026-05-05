part of '_migrations.dart';

/// Extends poll with type, anonymity, and revote settings.
/// - Adds `poll_type`, `is_anonymous`, `allow_revote` to `polling`.
/// - Adds `score` (for range voting) to `polling_act`.
final m0054 = Migration('0054', [
  '''
ALTER TABLE public.polling
  ADD COLUMN IF NOT EXISTS poll_type text NOT NULL DEFAULT 'single',
  ADD COLUMN IF NOT EXISTS is_anonymous boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS allow_revote boolean NOT NULL DEFAULT true;
''',
  '''
ALTER TABLE public.polling_act
  ADD COLUMN IF NOT EXISTS score smallint;
''',
]);
