part of '_migrations.dart';

/// Capability evidence edge sweep lease columns (unit D3).
final m0147 = Migration('0147', [
  '''
ALTER TABLE public.capability_evidence_edge
  ADD COLUMN sweep_lease_owner text NULL,
  ADD COLUMN sweep_lease_until timestamptz NULL;
''',
]);
