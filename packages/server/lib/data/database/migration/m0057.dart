part of '_migrations.dart';

final m0057 = Migration('0057', [
  '''
ALTER TABLE public.beacon
  ADD COLUMN IF NOT EXISTS needs text NOT NULL DEFAULT '';
''',
]);
