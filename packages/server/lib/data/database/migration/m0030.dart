part of '_migrations.dart';

/// Beacon symbolic identity: curated icon key + palette background (ARGB int).
final m0030 = Migration('0030', [
  '''
ALTER TABLE public."beacon"
  ADD COLUMN IF NOT EXISTS icon_code TEXT NULL;
''',
  '''
ALTER TABLE public."beacon"
  ADD COLUMN IF NOT EXISTS icon_background INTEGER NULL;
''',
]);
