part of '_migrations.dart';

final m0008 = Migration(
  '0008',
  [
    // Tables
    //
    '''
ALTER TABLE IF EXISTS public.beacon
  ADD COLUMN IF NOT EXISTS tags text NOT NULL DEFAULT '';
''',
  ],
);
