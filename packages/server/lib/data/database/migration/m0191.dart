part of '_migrations.dart';

/// U15R-e — an obligation belongs to a Request, in storage as well as in code.
///
/// The invariant: a `requires_action` receipt always names a Request
/// (`beacon_id IS NOT NULL`). `AttentionPolicy.logicalTaskKey` already throws
/// `Live obligation requires a Request` and runs on every dispatched receipt,
/// so this is the producer's own rule; until now nothing stopped a row of the
/// forbidden shape from being written by any other path.
///
/// Why it has to be storage and not just the producer: m0115's
/// `notification_outbox__beacon_policy_chk` demands a `beacon_id` only for the
/// `beacon_content` and `beacon_tombstone` access policies, so a
/// `requires_action` row on a `profile`-policy destination stored cleanly with
/// `beacon_id IS NULL`. `AttentionDismissibleSql.visibleWithSurface` then
/// labels it `activity` — the `scope` UNION can only absorb rows that name a
/// Request — and §6 gives such a row no indicator at all: For You has no
/// count, and its dot covers dismissible attention, pending forwards and
/// pending prompts, none of which contains a live obligation. That is what
/// blocked U15R-d from scoping `my desk.count` to the myWork surface. With the
/// shape unstorable the scoping drops nothing, so §6's fourth rule can be
/// written as §6 states it.
///
/// **It fails loudly.** `ADD CONSTRAINT` without `NOT VALID` validates the
/// existing table, so a legacy violating row aborts the migration instead of
/// being skipped, repaired or dropped — a silent repair here would hide
/// exactly the producer bug the constraint exists to catch. Legacy
/// remediation belongs to U18, which already owns the unkeyed-obligation gate.
final m0191 = Migration('0191', [
  '''
ALTER TABLE public.notification_outbox
  DROP CONSTRAINT IF EXISTS notification_outbox__obligation_beacon_chk;
''',

  '''
ALTER TABLE public.notification_outbox
  ADD CONSTRAINT notification_outbox__obligation_beacon_chk
  CHECK (NOT requires_action OR beacon_id IS NOT NULL);
''',

  '''
COMMENT ON CONSTRAINT notification_outbox__obligation_beacon_chk
  ON public.notification_outbox IS
  'U15R-e: a live obligation belongs to a Request. Mirrors the producer rule AttentionPolicy.logicalTaskKey already enforces (it throws "Live obligation requires a Request"). Without it a requires_action row on a profile-policy destination stored with beacon_id IS NULL, was labelled surface=activity by visibleWithSurface, and had no indicator in request-attention.md §6 — which is why my desk.count could not be scoped to the myWork surface.';
''',
]);
