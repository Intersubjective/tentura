part of '_migrations.dart';

// Drop legacy beacon.enabled: lifecycle is beacon.state only.
final m0016 = Migration('0016', [
  '''
DROP TRIGGER IF EXISTS beacon_set_enabled_from_state ON public.beacon;
''',
  '''
DROP FUNCTION IF EXISTS public.beacon_sync_enabled_from_state();
''',
  '''
ALTER TABLE public.beacon DROP COLUMN IF EXISTS enabled;
''',
]);
