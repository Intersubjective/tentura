part of '_migrations.dart';

/// U18b — one cursor per deferred gate, beside U18a's immutable instant.
///
/// The two gates are not one more phase of the `legacy_seen` backfill: they
/// touch **subsets defined by what can be proven about each row**, they stop
/// at different places, and either can be interrupted without the other. So
/// each gets its own cursor and its own completion mark, and a restart
/// resumes the phase it was in rather than re-deciding the whole table.
///
/// They go on `attention_cutover` rather than on a table of their own because
/// they are progress against **the same boundary**: both gates read
/// `cutover_at` — a row written after the cutover was never legacy and is
/// none of their business — and m0192's immutability trigger already forbids
/// moving it while these columns advance beside it.
///
/// `m0192` deliberately carried only U18a's columns: adding phase columns for
/// gates whose shape was not yet decided would have been guessing. These are
/// the ones those gates actually need.
final m0193 = Migration('0193', [
  '''
ALTER TABLE public.attention_cutover
  ADD COLUMN IF NOT EXISTS obligation_key_cursor text,
  ADD COLUMN IF NOT EXISTS obligation_key_completed_at timestamptz,
  ADD COLUMN IF NOT EXISTS placement_cursor text,
  ADD COLUMN IF NOT EXISTS placement_completed_at timestamptz;
''',

  '''
COMMENT ON COLUMN public.attention_cutover.obligation_key_cursor IS
  'U18b gate 1: last notification_outbox.id the obligation-key pass considered - keyed, or left unkeyed because its identity was not derivable. Undecidable rows are walked past on purpose: nothing about a stored row makes it derivable later, and they stay counted in unrepairableObligationCount.';
''',

  '''
COMMENT ON COLUMN public.attention_cutover.obligation_key_completed_at IS
  'When gate 1 ran out of live unkeyed obligations created before the cutover. Set once.';
''',

  '''
COMMENT ON COLUMN public.attention_cutover.placement_cursor IS
  'U18b gate 2: last notification_outbox.id the placement pass demoted. Only provably timeline-only rows are candidates, so this cursor walks the decidable subset alone; every other pre-m0189 row keeps the placement the column default gave it.';
''',

  '''
COMMENT ON COLUMN public.attention_cutover.placement_completed_at IS
  'When gate 2 ran out of demotable rows. Set once.';
''',
]);
