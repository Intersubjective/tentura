part of '_migrations.dart';

/// U08 — correct m0178's comment on `cleared_by_operation_id`.
///
/// m0178 documented the column as "NULL for explicit, request_open and
/// legacy_seen clears". That predates D12's idempotency requirement and is now
/// the opposite of what the server does: every clear the server performs is
/// backed by an `attention_clear_operation` row, because that row is what
/// makes a replayed `operationId` a no-op and what U09's undo will unwind.
///
/// `legacy_seen` remains the one operation-free clear reason: the U18 cutover
/// backfill has no operation to point at, which is why the
/// `notification_outbox__clear_facts_chk` CHECK still leaves the column
/// nullable. Comment only — no data, no constraint changes.
final m0182 = Migration('0182', [
  '''
COMMENT ON COLUMN public.notification_outbox.cleared_by_operation_id IS
  'The clear operation that cleared this receipt. Every clear the server performs is operation-backed, whatever the reason: the operation row is what makes a replayed operationId idempotent and U09 undo possible. NULL only for the U18 legacy_seen backfill, which has no operation.';
''',
]);
