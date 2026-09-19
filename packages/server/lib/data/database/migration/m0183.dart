part of '_migrations.dart';

/// U09a — dismissible foundations.
///
/// Two things this unit's brief calls out, in one additive, restartable
/// migration.
///
/// **1. Every outcome kind becomes dismissible.** `inbox_item_guard_tombstone`
/// (m0024) refused `tombstone_dismissed_at` unless `status IN (3, 4)`. That
/// restriction was written when the column meant "hide the *before-response
/// tombstone* card", and it is wrong under the request-centric attention model
/// (design plan D06/D07, owner decision B): `helping` (0, in responsibility
/// scope), `watching` (1) and `notInterested` (2) outcome rows all carry their
/// own `×` and must be dismissible. They were not merely unwired on the
/// client — the database refused them. Do not restore the status list: it
/// would silently re-break three of the five outcome kinds, and nothing above
/// the database would report the loss, because the client never had a control
/// to press.
///
/// What the guard still refuses is unchanged and deliberate: a tombstone row
/// may not change `status` or `rejection_message`; a row may not be inserted
/// into, or transitioned into, a tombstone status without the beacon trigger's
/// `tentura.allow_inbox_tombstone_transition` flag. Dismissal is a
/// presentation fact; stance transitions stay the beacon trigger's business.
///
/// **2. A sweep member may be an outcome instead of a receipt** (manifest §0.1
/// as amended after the U09 scout). `attention_clear_operation_member` carried
/// a NOT NULL `receipt_id` with an FK to `notification_outbox`, and an outcome
/// tombstone has no outbox row at all — U09b's sweep literally could not
/// record what it cleared. The table now takes exactly one of a `receipt_id`
/// or an `outcome_beacon_id` per member, enforced by
/// `attention_clear_operation_member__member_target_chk`.
///
/// The primary key `(operation_id, receipt_id)` cannot survive a nullable
/// `receipt_id`, so it is replaced by two partial UNIQUE indexes that keep the
/// same guarantee per member kind: membership is captured once and never
/// extended on retry.
///
/// Indexes are plain `CREATE INDEX`, never `CONCURRENTLY`: migrant applies a
/// migration inside a single transaction. Every statement is guarded so
/// re-running the whole migration is a no-op.
final m0183 = Migration('0183', [
  // 1. The guard, minus the status restriction.
  r'''
CREATE OR REPLACE FUNCTION public.inbox_item_guard_tombstone()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  allow text;
BEGIN
  allow := current_setting('tentura.allow_inbox_tombstone_transition', true);
  IF TG_OP = 'INSERT' AND NEW.status IN (3, 4) THEN
    IF allow IS DISTINCT FROM '1' THEN
      RAISE EXCEPTION 'inbox_item cannot insert tombstone status without beacon trigger';
    END IF;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF OLD.status IN (3, 4) THEN
      IF NEW.status IS DISTINCT FROM OLD.status
         OR NEW.rejection_message IS DISTINCT FROM OLD.rejection_message THEN
        RAISE EXCEPTION 'inbox_item tombstone rows cannot change status or rejection_message';
      END IF;
    END IF;
    -- m0183: `tombstone_dismissed_at` is no longer restricted to statuses
    -- 3 and 4. Every outcome kind carries its own dismiss control, so every
    -- outcome kind must be dismissable and un-dismissable (U09c undo).
    IF NEW.status IN (3, 4) AND OLD.status NOT IN (3, 4) THEN
      IF allow IS DISTINCT FROM '1' THEN
        RAISE EXCEPTION 'inbox_item cannot transition to tombstone status without beacon trigger';
      END IF;
    END IF;
    IF OLD.status IN (3, 4) AND NEW.status IN (3, 4)
       AND OLD.status IS DISTINCT FROM NEW.status THEN
      IF allow IS DISTINCT FROM '1' THEN
        RAISE EXCEPTION 'inbox_item tombstone status upgrade requires beacon trigger';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
''',

  // 2. The read index m0024 created only covers tombstone statuses. The
  // dismissible-outcome predicate (U09a step 2) scans every status of one
  // viewer, so it gets its own partial index. The old one stays: it still
  // serves the tombstone card's `before_response_terminal_at` ordering.
  '''
CREATE INDEX IF NOT EXISTS ii_user_outcome_undismissed
  ON public.inbox_item (user_id, status)
  WHERE tombstone_dismissed_at IS NULL;
''',

  '''
COMMENT ON COLUMN public.inbox_item.tombstone_dismissed_at IS
  'When set, the viewer dismissed this outcome row; it stops asking for attention and does not change stance. Valid for every status since m0183 — helping, watching and notInterested rows carry a dismiss control too. Distinct axis from notification_outbox.cleared_at, which is the receipt axis.';
''',

  // 3. The member table takes outcome members.
  '''
ALTER TABLE public.attention_clear_operation_member
  ADD COLUMN IF NOT EXISTS outcome_beacon_id text;
''',
  '''
ALTER TABLE public.attention_clear_operation_member
  DROP CONSTRAINT IF EXISTS attention_clear_operation_member_pkey;
''',
  '''
ALTER TABLE public.attention_clear_operation_member
  ALTER COLUMN receipt_id DROP NOT NULL;
''',
  '''
CREATE UNIQUE INDEX IF NOT EXISTS attention_clear_operation_member__receipt_once
  ON public.attention_clear_operation_member (operation_id, receipt_id)
  WHERE receipt_id IS NOT NULL;
''',
  '''
CREATE UNIQUE INDEX IF NOT EXISTS attention_clear_operation_member__outcome_once
  ON public.attention_clear_operation_member (operation_id, outcome_beacon_id)
  WHERE outcome_beacon_id IS NOT NULL;
''',
  r'''
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.attention_clear_operation_member'::regclass
       AND conname = 'attention_clear_operation_member__member_target_chk'
  ) THEN
    ALTER TABLE public.attention_clear_operation_member
      ADD CONSTRAINT attention_clear_operation_member__member_target_chk
      CHECK (num_nonnulls(receipt_id, outcome_beacon_id) = 1);
  END IF;
END;
$$;
''',
  '''
COMMENT ON COLUMN public.attention_clear_operation_member.outcome_beacon_id IS
  'The Request whose outcome row this member dismissed, for members that are outcomes rather than receipts. Exactly one of receipt_id and outcome_beacon_id is set (CHECK). Deliberately not a foreign key, for the same reason beacon_id is not: the operation audit and its counters must survive deletion of the Request, and undo of a member whose Request is gone has nothing to restore and is skipped.';
''',
  '''
COMMENT ON TABLE public.attention_clear_operation_member IS
  'What a clear/dismiss-all sweep captured. A member is either a receipt (receipt_id, the notification_outbox axis) or an outcome (outcome_beacon_id, the inbox_item.tombstone_dismissed_at axis) — exactly one, by CHECK. Captured once and never extended on retry: the two partial UNIQUE indexes on (operation_id, receipt_id) and (operation_id, outcome_beacon_id) are that guarantee. beacon_id stays an unreferenced snapshot so the audit survives beacon deletion.';
''',
]);
