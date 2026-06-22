part of '_migrations.dart';

/// Drop author timeline `beacon_update` table and its updated_at bump trigger.
final m0093 = Migration('0093', [
  '''
DROP TRIGGER IF EXISTS beacon_update_bump_beacon_updated_at ON public.beacon_update;
''',
  '''
DROP FUNCTION IF EXISTS public.notify_beacon_update_bump_beacon();
''',
  '''
DROP TABLE IF EXISTS public.beacon_update CASCADE;
''',
]);
