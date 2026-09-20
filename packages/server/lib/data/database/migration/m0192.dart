part of '_migrations.dart';

/// U18a — the cutover instant, written once and never again.
///
/// D19 gives the backfill a **fixed** boundary: "Backfill uses a fixed cutover
/// boundary and is restartable." Restartable and fixed together mean the
/// boundary cannot be `now()` evaluated per pass — a second pass would then
/// draw a different line and convert rows the first pass deliberately left
/// alone. So the instant is stored: one row, written before any receipt is
/// touched, and immutable afterwards.
///
/// **Why a trigger and not a convention.** The singleton carries mutable
/// progress next to the immutable instant (`legacy_seen_cursor`,
/// `legacy_seen_completed_at`), so every restart issues an `UPDATE` against
/// this very row. A `CHECK` cannot see the old value, and a comment cannot
/// stop a future writer from adding `cutover_at = now()` to that `SET` list —
/// which is precisely the mutation U18a's acceptance test exists to catch.
/// `attention_cutover__immutable_instant` makes it a database error instead of
/// a silently moved boundary.
///
/// **Singleton by primary key.** `id boolean PRIMARY KEY CHECK (id)` admits
/// exactly one row — `true` — so `INSERT … ON CONFLICT (id) DO NOTHING` is the
/// whole of "write it once", with no advisory lock and no read-then-write race
/// between two booting isolates.
///
/// The cursor is `text` because `notification_outbox.id` is `text`: the
/// backfill walks receipts in `id` order and stores the last id it committed.
/// It is an optimisation over the NULL guard, never a substitute for it — the
/// guard is what makes the second pass a no-op even with the cursor lost.
final m0192 = Migration('0192', [
  '''
CREATE TABLE IF NOT EXISTS public.attention_cutover (
  id boolean PRIMARY KEY DEFAULT true,
  cutover_at timestamptz NOT NULL,
  legacy_seen_cursor text,
  legacy_seen_completed_at timestamptz,
  CONSTRAINT attention_cutover__singleton_chk CHECK (id)
);
''',

  r'''
CREATE OR REPLACE FUNCTION public.attention_cutover_immutable_instant()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.cutover_at IS DISTINCT FROM OLD.cutover_at THEN
    RAISE EXCEPTION
      'attention_cutover.cutover_at is immutable (% -> %)',
      OLD.cutover_at, NEW.cutover_at
      USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END;
$$;
''',

  '''
DROP TRIGGER IF EXISTS attention_cutover__immutable_instant
  ON public.attention_cutover;
''',

  '''
CREATE TRIGGER attention_cutover__immutable_instant
  BEFORE UPDATE ON public.attention_cutover
  FOR EACH ROW
  EXECUTE FUNCTION public.attention_cutover_immutable_instant();
''',

  '''
COMMENT ON TABLE public.attention_cutover IS
  'U18a: the single row that fixes the attention cutover instant. Written once before any receipt is mutated; the backfill is restartable against it, so cutover_at is immutable and only the progress columns move.';
''',

  '''
COMMENT ON COLUMN public.attention_cutover.cutover_at IS
  'D19 fixed boundary. Set on the first backfill entry, before any row mutation, and never rewritten - a re-run that moved it would draw a different line than the pass it is resuming.';
''',

  '''
COMMENT ON COLUMN public.attention_cutover.legacy_seen_cursor IS
  'Last notification_outbox.id whose legacy_seen batch committed. A restart resumes after it. An optimisation over the NULL guard on every UPDATE, never a substitute: the guard alone makes a second pass a no-op.';
''',

  '''
COMMENT ON COLUMN public.attention_cutover.legacy_seen_completed_at IS
  'When the legacy_seen phase ran out of candidates. Set once; a later boot reads it and does no work at all.';
''',
]);
