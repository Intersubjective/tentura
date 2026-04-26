part of '_migrations.dart';

/// Beacon need-first fields: short canonical ask + optional success criteria.
final m0035 = Migration('0035', [
  '''
ALTER TABLE public."beacon"
  ADD COLUMN IF NOT EXISTS need_summary TEXT NULL;
''',
  '''
ALTER TABLE public."beacon"
  ADD COLUMN IF NOT EXISTS success_criteria TEXT NULL;
''',
]);
