part of '_migrations.dart';

/// U05b — supports channel-layer collapse lookups.
///
/// U05a moved in-app receipts to one immutable row per occurrence. Push and
/// email must still aggregate: a family of receipts sharing a collapse key is
/// one notification. U05b performs that aggregation at the delivery layer, by
/// looking for an existing **pending** `attention_channel_delivery` row for
/// the same `(account_id, collapse_key)` before inserting a new job.
///
/// The collapse key is not duplicated onto the delivery table — it already
/// exists on `attention_occurrence_recipient.collapse_key`, one row per
/// `(occurrence_id, account_id)`, which is exactly the grain a delivery job
/// has. The lookup therefore joins through that table, and this index is what
/// keeps the join from being a sequential scan on every dispatch.
///
/// Purely additive: one plain `CREATE INDEX IF NOT EXISTS` (never
/// `CONCURRENTLY` — migrant runs a migration in a single transaction), no
/// uniqueness, no column, no data change. Re-running it is a no-op.
final m0180 = Migration('0180', [
  '''
CREATE INDEX IF NOT EXISTS attention_occurrence_recipient__account_collapse
  ON public.attention_occurrence_recipient (account_id, collapse_key);
''',
  '''
COMMENT ON INDEX public.attention_occurrence_recipient__account_collapse IS
  'Channel-layer collapse lookup (U05b): finds the pending delivery job for an account-and-collapse-family so push/email aggregate instead of duplicating. Not unique: many occurrences share a collapse family.';
''',
]);
