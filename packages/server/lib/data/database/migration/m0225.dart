part of '_migrations.dart';

/// Idempotent Request create: a repeat of `beaconCreate` with the same author
/// and client operation id returns the first beacon instead of a duplicate.
final m0225 = Migration('0225', [
  'ALTER TABLE public.beacon ADD COLUMN client_op_id text',
  '''
CREATE UNIQUE INDEX beacon_author_client_op_id_key
ON public.beacon (user_id, client_op_id)
WHERE client_op_id IS NOT NULL
''',
]);
