part of '_migrations.dart';

/// Indexes that back the `beaconCommitterForwardPath` recursive CTE.
///
/// The seed of the CTE filters
///   `beacon_id = $1 AND cancelled_at IS NULL AND (recipient_id = $2
///    OR recipient_id = $3 OR sender_id = $3)`
/// and the recursive step joins `id = c.parent_edge_id`. Without these
/// partial indexes the seed falls back to a sequential scan on every
/// open chain query as the table grows; the recursive join also benefits
/// from an explicit index on `parent_edge_id` (Postgres does NOT auto-
/// create indexes for FK referencing columns).
///
/// All statements use `IF NOT EXISTS` so they're safe to re-run if
/// equivalent indexes already exist on dev / staging environments.
final m0059 = Migration('0059', [
  '''
CREATE INDEX IF NOT EXISTS beacon_forward_edge__beacon_recipient_active__idx
  ON public.beacon_forward_edge (beacon_id, recipient_id)
  WHERE cancelled_at IS NULL;
''',
  '''
CREATE INDEX IF NOT EXISTS beacon_forward_edge__beacon_sender_active__idx
  ON public.beacon_forward_edge (beacon_id, sender_id)
  WHERE cancelled_at IS NULL;
''',
  '''
CREATE INDEX IF NOT EXISTS beacon_forward_edge__parent_edge_id__idx
  ON public.beacon_forward_edge (parent_edge_id)
  WHERE parent_edge_id IS NOT NULL;
''',
]);
