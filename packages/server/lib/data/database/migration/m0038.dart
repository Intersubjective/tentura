part of '_migrations.dart';

/// Outward public status on beacon; optional last meaningful change note.
/// `beacon_commitment` drop is deferred until forward/commit paths read
/// `beacon_participant` only (see journal).
final m0038 = Migration('0038', [
  '''
ALTER TABLE public.beacon
  ADD COLUMN IF NOT EXISTS public_status smallint NOT NULL DEFAULT 0;
''',
  '''
ALTER TABLE public.beacon
  ADD COLUMN IF NOT EXISTS last_public_meaningful_change text NULL;
''',
  '''
COMMENT ON COLUMN public.beacon.public_status IS
  '0=open,1=coordinating,2=more_help_needed,3=enough_help,4=closed';
''',
]);
