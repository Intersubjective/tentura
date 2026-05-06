part of '_migrations.dart';

final m0056 = Migration('0056', [
  '''
ALTER TABLE public.invitation
  ADD COLUMN IF NOT EXISTS beacon_id text REFERENCES public.beacon(id) ON DELETE SET NULL;
''',
]);
