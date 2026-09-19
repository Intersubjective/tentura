part of '_migrations.dart';

/// U09b — the sweep's bookkeeping columns.
///
/// `attentionDismissAll` captures membership across the whole authorized
/// surface and then applies it in bounded batches, possibly across several
/// calls. Two facts have nowhere to live in the m0178/m0183 member shape.
///
/// **1. `state = 'pending'`.** U08's single-Request clear captured and applied
/// inside one transaction, so a member was born `applied` or `skipped`. A
/// sweep is resumable by operation id: a member is captured first and decided
/// later, and "captured but not yet decided" is exactly what a resume looks
/// for. The partial index is the batch cursor — it is the only thing the
/// resume loop scans, and it must stay small as the operation finishes.
///
/// **2. Why a member was refused.** Owner decision A is a promise about rows
/// the sweep does *not* touch, and a sweep that reported "skipped" without
/// saying why would be unauditable: "the forward was answered underneath me"
/// and "you are no longer allowed to see this" are different answers to the
/// person and different bugs to us. `skip_reason` is plain text for the same
/// reason `attention_clear_operation.status` is: the vocabulary belongs to the
/// unit that issues it, not to the schema.
///
/// **3. `decision_revision`.** m0178 stored only `outcome_generation` on a
/// member, because U08 had no outcome members. U09c's undo is defined against
/// *both* counters (a Restore moves `decision_revision` without necessarily
/// moving the generation), so the sweep must snapshot both at capture or undo
/// cannot tell that somebody decided something underneath it. Nullable, so
/// U08's receipt members — which never carried one — stay valid.
///
/// Purely additive and restartable: every statement is guarded.
final m0186 = Migration('0186', [
  '''
ALTER TABLE public.attention_clear_operation_member
  ADD COLUMN IF NOT EXISTS decision_revision integer,
  ADD COLUMN IF NOT EXISTS skip_reason text;
''',
  r'''
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.attention_clear_operation_member'::regclass
       AND conname = 'attention_clear_operation_member__decision_revision_chk'
  ) THEN
    ALTER TABLE public.attention_clear_operation_member
      ADD CONSTRAINT attention_clear_operation_member__decision_revision_chk
      CHECK (decision_revision IS NULL OR decision_revision >= 0);
  END IF;
END;
$$;
''',

  // The batch cursor. A sweep claims its next batch with
  // `WHERE operation_id = … AND state = 'pending' … FOR UPDATE`, so this index
  // is scanned once per batch and shrinks to nothing as the operation
  // completes.
  '''
CREATE INDEX IF NOT EXISTS attention_clear_operation_member__pending
  ON public.attention_clear_operation_member (operation_id)
  WHERE state = 'pending';
''',

  '''
COMMENT ON COLUMN public.attention_clear_operation_member.decision_revision IS
  'The viewer decision counter snapshotted at capture, alongside outcome_generation. NULL on members captured before m0186 and on U08 single-Request receipt members. U09c refuses to undo a member whose live counters have moved.';
''',
  '''
COMMENT ON COLUMN public.attention_clear_operation_member.skip_reason IS
  'Why a captured member was refused at apply time: the sweep reports it verbatim. NULL unless state is skipped or failed. Free text; the vocabulary belongs to the issuing unit, like attention_clear_operation.status.';
''',
  '''
COMMENT ON COLUMN public.attention_clear_operation_member.state IS
  'pending | applied | skipped | failed. A sweep captures members as pending and decides each one in a later batch, which is what makes it resumable by operation id; U08s single-Request clear decides every member inside the capture transaction and never writes pending.';
''',
]);
