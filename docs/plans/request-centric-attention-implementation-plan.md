# Request-centric attention — implementation manifest

**Authority.** This document is authoritative for **order, unit boundaries, frozen names and acceptance**.
Product intent lives in [`../features/request-attention.md`](../features/request-attention.md); the design
rationale and decisions D01–D19 live in
[`request-centric-attention-plan.md`](request-centric-attention-plan.md). Where this manifest and the design plan
disagree about *what* to build, the design plan wins; where they disagree about *how it lands*, this one does.

**Baseline.** `feb2667a9` on `feature/events_refac` (identical to local `main`). Next free migration id: **m0178**
(registry ends at `m0177`, `packages/server/lib/data/database/migration/_migrations.dart`).

**Journal.** Every unit appends to `request-centric-attention-implementation-journal.md` before the next unit
starts: unit id, what was done, files, tests actually run with their results, findings, decisions, what remains.
No unit is "complete" without a journal entry containing real command output — not a claim of it.

---

## 0. Frozen contracts

These names are fixed by this manifest. A unit may not rename them; a unit that needs a different shape stops and
amends this section first, in its own commit.

### 0.1 Storage (proposed, allocated m0178+)

| Object | Name | Notes |
|---|---|---|
| Optional-clear state | `notification_outbox.cleared_at`, `.clear_reason`, `.cleared_by_operation_id` | valid only where `requires_action = false` (CHECK) |
| `clear_reason` values | `explicit` · `request_open` · `sweep` · `legacy_seen` | no others without amending this section |
| Obligation identity | `notification_outbox.logical_task_key`, `.lifecycle_generation` | one live receipt per `(account_id, logical_task_key)` (partial UNIQUE where `requires_action AND settlement_kind IS NULL`) |
| Per-viewer Request state | `attention_request_state(account_id, beacon_id, first_entry_at, outcome_generation, decision_revision)` | stable ordering anchor + outcome identity |
| Sweep operation | `attention_clear_operation(id, account_id, surface, status, captured_at, undo_deadline, applied, skipped, failed)` | |
| Sweep membership | `attention_clear_operation_member(operation_id, receipt_id, beacon_id, outcome_generation, state)` | captured once; never extended on retry |
| Immutable receipt identity | UNIQUE `(occurrence_id, account_id)` for post-cutover receipts | see U05 |

`primary_surface` is **never** stored. `seen_at` keeps its meaning: read, not cleared.

### 0.1a Grouped-row provenance (frozen by `issue-171-card-spec.md` §4)

Each grouped `beacon:<id>` row must carry, or the For You card cannot be built:
`senders[]` → `{id, displayName, imageId, notePreview, reasonSlugs[], mr}` · `totalDistinctSenders` ·
`strongestNotePreview` (already exists and is already MR-ranked server-side — plumbing, not new ranking) ·
`beacon.{title,author,imageId,endAt}` · `allowsForward`.

Reuse the existing `inbox_provenance_data` JSON shape verbatim so `InboxProvenance.parse` / `withoutViewer` work
unchanged on the client. **Do not invent a second provenance DTO.**

### 0.2 API (additive; existing operations stay until U18)

`attentionRequest(beaconId, cursor, limit)` · `attentionRequestHistory(beaconId, cursor, limit)` ·
`attentionClear(snapshotToken, operationId)` · `attentionDismissAll(surface, operationId)` ·
`attentionUndo(operationId, undoToken)` · `attentionReconcile(operationId)` · extended surface summary.

Server: `packages/server/lib/api/controllers/graphql/{query,mutation}/`\*`_attention.dart`.
Client documents: `packages/client/lib/features/attention/data/gql/*.graphql` (ferry codegen; never hand-edit `_g/`).

### 0.3 Client domain

New entities live under `packages/client/lib/domain/attention/entity/`; the single owner of attention state
remains `AttentionCase` (`packages/client/lib/domain/attention/attention_case.dart`). **No second attention
cache** may be introduced in any feature.

### 0.4 Identifiers and copy

TestIds: `attentionDismiss(receiptId)`, `attentionDismissCard(beaconId)`, `attentionDismissAll`,
`attentionObligationCta(receiptId)`, `attentionUndo`, `attentionResetCounters`.
l10n keys: prefix `attention*`; user copy follows
[`.cursor/rules/terminology.mdc`](../../.cursor/rules/terminology.mdc) — **Request** / **Chat**, never Beacon.

---

## 1. Executor rules

1. **One unit, one focused commit** (or a short chain). Never mix schema, lifecycle and widget changes in one
   review — that boundary is the point of the split.
2. **Preserve unrelated worktree changes.** The tree carries unrelated modifications and untracked plans; touch
   nothing outside the unit's *Owns* list.
3. **Tests run through the cleanup wrapper**, always:
   ```bash
   ./scripts/run_with_test_cleanup.sh --timeout 20m -- <command>
   ```
   Bare `flutter test` / `dart test` survives session kills and leaves RAM-backed `/tmp/flutter_tools.*` tails.
4. **PG suites**: `dart test --tags pg -j 1`. A **skipped** PG suite is *blocked*, not passed — the Activity PG
   suite skips silently when its admin database is unreachable.
5. **Lints**: `./scripts/check-custom-lints.sh packages/{client,server}`. Re-read
   `scripts/custom-lint-baseline.txt` every time — the baseline drifts down and a stale copy hides regressions.
6. **Codegen** after schema/DI/GraphQL changes: `build_runner` for the client (`di.config.dart` is gitignored),
   freezed for new entities. Never edit `_g/` by hand.
7. **Goldens** are inspected, not blind-updated. `--update-goldens` without eyeballing the diff fails review.
8. **Layer rules** apply (`clean-architecture`): UI → Data → Domain → nothing; domain stays pure.
9. **Design system** for every visual change (`material-3-flutter`): no raw constants in feature UI.
10. **Report honestly.** A partially met acceptance item is written down as partially met, with what is missing.

---

## 2. Unit manifest

Dependency graph: U01 → U02 → U03 → U04 → U05 → {U06b, U07b} → U08 → U09 → U10 → {U11, U12} → U13 →
U14 → {U15, U16} → U17 → U18 → U19.

**Independent of everything:** **U06a** (retention defect). **Investigation, not implementation:** **U07a**,
which must complete before U07b and U12 are schedulable.

---

### U01 — Product contract · **COMPLETE (2026-09-18)**

Durable spec written: [`docs/features/request-attention.md`](../features/request-attention.md).
`docs/README.md` (feature + plan rows), `CONTEXT.md` (§ My desk: obligation, optional update, Dismiss all,
outcome row), `docs/features/new-stuff-indicators.md` (superseded banner), `work-activity-redesign-plan.md`
(refinement note) updated. `scripts/check-user-facing-terminology.sh` passes.

---

### U02 — Characterization tests · **COMPLETE (2026-09-18)**

**Goal.** Freeze today's behaviour in tests *before* changing it, and mark which assertions we intend to break.

**Owns.** `packages/server/test/data/repository/attention_*_pg_test.dart`,
`packages/server/test/data/repository/my_work_attention_pg_test.dart`,
`packages/client/test/features/inbox/*`, `packages/client/test/features/my_work/*`,
`packages/client/test/domain/attention/*`.

**Steps.**
1. Run the existing attention suites; record actual results in the journal (not assumed ones).
2. Add characterization tests where behaviour is currently untested but load-bearing: surface derivation on
   help-offer add/withdraw, grouping eligibility, pinned-zone membership, obligation counting, retention.
3. Tag every assertion this plan will deliberately change with `// CHANGES IN Uxx:` — at minimum the two that
   assert today's cross-surface duplicate and optional-event bumping
   (`attention_activity_stream_pg_test.dart:143,537,587,645`).

**Acceptance.** Suites green; a journal list of every intentionally-doomed assertion with its owning unit.

**Tests.** `dart test --tags pg -j 1 test/data/repository/attention_*_pg_test.dart`; client
`flutter test test/features/inbox test/features/my_work test/domain/attention`.

---

### U03 — Exhaustive classification · **COMPLETE (2026-09-18)**

**Goal.** Make classification a declared, machine-checked function of (event type × recipient role × state).

**Owns.** `packages/server/lib/domain/attention/attention_policy.dart`, `attention_models.dart`,
`docs/contracts/updates-event-contract.json`, `packages/{server,client}/test/architecture/updates_event_*_test.dart`.

**Steps.**
1. Bump the contract to a schema version carrying the §4.3 fields of the design plan, including `recoverableVia`.
2. Declare **all 29** `AttentionEventType` values — supported, deliberately silent, or retired. The contract
   currently covers 15.
3. Remove the implicit `_ => false` fallback in `_requiresAction`; an undeclared variant must fail loudly.
4. Upgrade the architecture tests: enum coverage, obligations require CTA + logical key + resolution,
   optional events may not declare a bump, hierarchy-propagated events may not declare primary attention,
   `recoverableVia: none` requires a declared retention exemption.

**Acceptance.** Adding a new enum value without a declaration fails the build. No default-optional path exists.

**Tests.** Server + client architecture suites; `attention_policy_test.dart`.

---

### U03b — Card contract fields · **depends U03**

**Goal.** Add the three fields the For You card needs to the classification contract, test-first.

**Owns.** `docs/contracts/updates-event-contract.json`, the server/client architecture contract tests, the journal.

**Steps.** Add `selfAuthored`, `headlineTreatment` (`beacon` quoted+attributed · `user` bare+avatar · `system`
bare) and `coalescible` per variant; write the failing guard first. **Deviation from the spec, deliberate:** the
spec says "under schemaVersion 3", but U03 already shipped schemaVersion 3 with a different required field set, so
adding newly-required fields bumps it to **schemaVersion 4**. Silently widening a shipped version would make the
version number meaningless.

**Acceptance.** Guard fails on a variant missing any of the three. `coalescible: false` on every note-bearing
forward variant (spec §7.3 K6) — a note exists nowhere else on the card, so coalescing destroys information.

---

### U0C — "Following" rename · **independent, land early**

**Goal.** Spec D-171-1 / §10: rename the Watching word family to «Следить / Слежу» / "Follow / Following".

**Owns.** l10n `.arb` values — **keys unchanged** — plus user-facing string *literals* hardcoded outside l10n
(`forward_messages.dart`, `inbox_messages.dart`, `help_offer_messages.dart` carry ~6 of them, e.g.
«Он во вкладке "Наблюдаю"»), plus any test expecting the old strings.

**Scope widened by the overseer after the U0C scout (2026-09-19).** "Values only" means no key renames and no
behaviour change — not "`.arb` only". Excluding the hardcoded literals would leave the rename half-done and make
this unit's own acceptance unmeetable. The scout also found three keys the spec table missed
(`beaconPeopleStatusWatching`, `beaconHudYouAskedToHelp`, `activityForwardOutcomeWatching`), and this unit
additionally lands the **§8 tombstone past-tense copy table** — those keys would otherwise be edited twice, and
the past-tense copy is the literal fix #171 reported. No version bump and no cache-buster here: this is not a
release.

**Steps.** The §10 table, verbatim, including `actionStopWatching`, which today names «Нужно мне» while the
destination tab is «Ждёт меня». One commit. Not unit-gated (E29 was dropped; Watching already has a permanent
entry), but it should land **before the next testing session**, and it should sweep sibling #142 issues quoting
the old word.

**Acceptance.** No user-visible "наблюд*" / "watch*" stems left in the attention surfaces; keys untouched so no
code churn.

---

### U04 — Additive schema

**Goal.** Land §0.1 as additive migrations with constraints, no behaviour change.

**Owns.** `packages/server/lib/data/database/migration/m0178…` + `_migrations.dart` + table mappings.

**Steps.** Columns and tables per §0.1; CHECK constraints (clear metadata only on optional receipts, settlement
metadata only on obligations); partial unique indexes (one live obligation per logical task; canonical
occurrence/recipient identity for new rows); partial indexes for active optional receipts and live obligations by
`(account_id, beacon_id)`; extend the realtime change-detection trigger to the new columns.

**Acceptance.** Migration applies to a fresh database and to a copy of the current schema; restart-safe; existing
suites unaffected.

**Tests.** Migration/schema PG tests; full server suite.

---

### U05 — Immutable dispatch identity

**Goal.** Stop rewriting receipts in place.

**Owns.** `packages/server/lib/data/repository/attention_dispatch_repository.dart`, channel-decision boundary.

**Steps.**
1. Post-cutover receipts get immutable `(occurrence_id, account_id)` identity; the in-place
   `ON CONFLICT (dedup_key) … SET … requires_action = EXCLUDED.requires_action, created_at = now()` path
   (`:126–147`) no longer governs in-app receipt identity.
2. Keep source-event replay dedup and channel aggregation — move them to the channel layer's own key.
3. Obligations gain `logical_task_key` + `lifecycle_generation`; a renewed obligation supersedes its predecessor
   transactionally, a delivery retry does neither.

**Acceptance.** Replaying a source event inserts once; two distinct occurrences keep distinct receipts; an event
arriving during a clear cannot be swallowed by it; no receipt's `created_at` moves.

**Tests.** Dispatch PG tests incl. a concurrency case; `attention_dispatch_telemetry_test.dart`.

---

**Split by the overseer after the U05 scout (2026-09-19).** The scout's brief decomposed U05 into six
commit-sized steps — beyond what one low-effort inner pass handles reliably — so U05 runs as three sequential
sandwiches:

- **U05a — receipt identity**: stop the in-place `ON CONFLICT (dedup_key)` rewrite, give in-app receipts
  immutable identity, preserve `source_event_key` replay dedup. Includes the schema change the scout found
  necessary: the existing `notification_outbox__dedup_seen` unique index forbids two unseen rows per collapse
  key and must change before plain INSERT is possible.
- **U05b — channel split**: move collapsing to the channel layer (pending-delivery dedupe, email marked by the
  channel collapse key instead of `dedup_key`) so push/email behaviour is unchanged.
- **U05c — obligation identity**: write `logical_task_key` / `lifecycle_generation`, and supersede the
  predecessor transactionally on a semantic renewal (a delivery retry must do neither).

**Accepted consequence, deliberate:** after U05a the feed carries more receipts per Request until U10's
projections absorb them. The U02 characterization tests that pin today's collapse behaviour are therefore
approved for rewrite *in these units only*, and each rewrite must be named in the journal.

### U06a — Retention defect · **COMPLETE (2026-09-18)**

**Goal.** Stop retention from deleting outstanding work.

**Owns.** `packages/server/lib/data/repository/notification_outbox_repository.dart`,
`packages/server/test/data/repository/attention_retention_pg_test.dart`.

**Steps.**
1. Write the failing test first: a receipt with `requires_action = true`, `settlement_kind IS NULL`,
   `seen_at` and `emailed_at` set, `created_at` older than the window, no pending/leased delivery. Today it is
   deleted. The existing suite has exactly one test — *"keeps pending and leased handoffs, then removes terminal
   and no-delivery receipts"* — which asserts deletion by delivery state and never looks at obligations, so the
   defect is not merely uncovered, it is covered past.
2. Exclude live obligations and uncleared optional events from `deleteSettledOlderThan` unconditionally.

**Acceptance.** New test red before, green after; the existing retention test still passes unchanged.

**Tests.** `dart test --tags pg -j 1 test/data/repository/attention_retention_pg_test.dart`.

**Review boundary.** One repository predicate plus one test. Nothing else may enter this commit.

---

### U06b — Personal Request history read

**Depends.** U04, U05.

**Owns.** attention query port/repository, `task_worker_case.dart` retention scheduling.

**Steps.** Stop age-based deletion of attention-bearing post-cutover receipts (delivery-job cleanup stays
separate); add the authorized `attentionRequestHistory` read.

**Acceptance.** Cleared and settled records remain readable per §6 of the design plan; delivery cleanup unaffected.

---

### U07a — Obligation transition audit · **investigation, no code**

**Goal.** Produce the fact base U07b and U12 need. This unit writes a document, not an implementation.

**Deliverable.** A transition matrix in the journal: for **every** obligation kind — every source transition that
should end it, whether the code actually settles it today (with `file:line`), the expiry path, and whether a
decline path exists or is forbidden by domain rule.

**Method.** Enumerate from the event enum and the settlement cases outward; for each kind, find the producing and
the terminating call sites. A plausible-looking list is a failure: every row cites code or is marked
**UNVERIFIED** explicitly.

**Known starting point.** Withdrawal updates the offer, access, Inbox state and receipts without settling the
author's help-offer obligation — one confirmed gap; the audit exists to find the rest.

**Acceptance.** Every `AttentionEventType` classified as obligation in U03 appears in the matrix with evidence or
an explicit unverified mark. No code changes in this unit.

---

### U07b — Obligation lifecycle completion

**Carried in from U05c's verify (overseer):** add the structural guard on the dispatch/supersede boundary. The
inner layer asserted no caller reaches it outside an ambient mutating transaction; the verifier found
`user_block_case.dart:211` calling `dispatch.record` bare. It is benign today only because that path emits no
obligations — the safety is a coincidence, not a guarantee. This unit already edits that boundary (it must move
`settleReviewerObligationOnPackageSend` inside the transaction, `evaluation_case.dart:1616`), so the guard
belongs here.


**Depends.** U03, U04, U05, **U07a**.

**Owns.** `help_offer_case.dart`, `coordination_case.dart`, `evaluation_case.dart`,
`attention_settlement_case.dart`, `attention_system_settlement_repository.dart`,
`attention_expiry_sweep_case.dart`.

**Steps.**
1. Close every gap the U07a matrix names, starting with withdrawal.
2. Expiry/cancellation becomes one atomic transition: settle-and-clear the original **and** emit a distinct,
   idempotent optional explanation (re-running the sweeper must not duplicate it).
3. Remove generic user settlement (owner decision C); reject the old public mutation for these kinds after
   activation. Review obligations stay non-declinable.

**Acceptance.** Every row of the U07a matrix is either implemented or explicitly deferred with a reason. No code
path settles an obligation from a UI acknowledgment.

**Tests.** Use-case PG tests per transition; `review_obligation_settlement_pg_test.dart`; an idempotency test for
the expiry explanation.

---

**Split by the overseer (2026-09-19).** U07a's matrix lists seven gaps plus U05c's structural guard — too many
for one low-effort pass, so U07b runs as two sandwiches:

- **U07b1 — settlement integrity**: close the P0/P1 *missing settlements* (withdrawal; the terminal paths
  `offerRemoved` and beacon close), move `settleReviewerObligationOnPackageSend` **inside** the attention
  transaction (`evaluation_case.dart:1616`), and add the structural guard on the dispatch/supersede boundary
  that U05c's verify showed is missing (`user_block_case.dart:211` calls `dispatch.record` bare).
- **U07b2 — lifecycle vocabulary**: reject generic user settlement for these kinds server-side (owner decision
  C), emit the optional explanation when an obligation ends by expiry or cancellation (the "never silently
  decrement" rule), and reconcile `resolutionTransitions` with what the code actually does — U07a found the
  contract both over- and under-declares.

### U08 — Clear command (single and open)

**Carried in from U04's verify (overseer):** this unit is the first writer of
`cleared_by_operation_id`, so it must also prove the `notification_outbox__cleared_by_operation_fkey` FK
rejects an unknown operation id. U04 added the FK but nothing exercises it yet.


**Goal.** Explicit clearing with an exact, race-safe boundary.

**Owns.** new clear domain case + port + repository; `mutation_attention.dart`.

**Steps.** Snapshot token bound to account and Request; `attentionClear` clears exactly the captured optional
members (never obligations, never decision-bearing rows); idempotent by `operationId`; returns the applied set;
**version/snapshot based, never wall-clock** — collapse used to move `created_at`, so "older than my tap" is not
a boundary.

**Acceptance.** An event committed after the snapshot survives the clear; a replayed operation id is a no-op; a
foreign receipt id is denied without disclosing existence.

**Tests.** New clear-operation PG suite incl. a barrier-controlled concurrent-arrival case.

---

### U09 — Outcomes, sweep, undo

**Goal.** Every dismissible row is dismissible; the sweep covers the whole surface; undo is bounded.

**Owns.** inbox outcome state, clear-operation processing, undo.

**Steps.**
1. **Outcome rows**: extend the existing `dismissTombstone` → `tombstone_dismissed_at` path to *every* outcome,
   including `helping` and `watching`, which today fall into `default: trailingAction = null`
   (`activity_forward_row.dart:55–69`). Keep `Restore` for `notInterested` as a secondary action.
2. **`attentionDismissAll`** (owner decision A): server-captured membership over the whole authorized surface
   including unloaded pages; clears **only rows carrying their own ×**; skips unanswered forwards, pending
   prompts, obligations, and Requests that gained responsibility since capture; resumable by id; returns
   applied/skipped/failed.
3. **Undo**: server-enforced short window, restores only members of that operation, checks authorization,
   outcome generation and decision revision; never reverses another device's or another person's action; partial
   undo reports explicitly.

**Acceptance.** From a realistic mixed fixture, Dismiss all leaves exactly the decision zone and the obligations —
and nothing else. No residual uncleared outcome is created by the sweep itself.

**Tests.** Sweep across ≥3 pages; every outcome kind; undo conflict cases; resume after a simulated timeout.

---

**Split and amended by the overseer after the U09 scout (2026-09-19).** The scout returned eight steps — too
many for one low-effort pass — and, more importantly, refuted two assumptions this plan carried:

1. **Tombstone dismissal is broken at the database layer, not merely unwired.** The `tombstone_dismissed_at`
   trigger admits only inbox statuses 3/4, so `helping`, `watching` and `notInterested` cannot be dismissed at
   all today. Earlier notes in this plan (and in the design plan's E2/D01) said the mechanism existed and only
   lacked a caller — that is true for `closed/deletedBeforeResponse` only. A migration is required.
2. **§0.1 cannot represent an outcome sweep member.** `attention_clear_operation_member.receipt_id` carries an
   FK to `notification_outbox`, and a tombstone is not a receipt. **§0.1 is hereby amended**: the member table
   gains a nullable beacon reference, `receipt_id` becomes nullable, and a CHECK requires exactly one of the
   two. Undo therefore stores both a receipt snapshot and an outcome snapshot per member.

U09 runs as three sandwiches:

- **U09a — dismissible foundations**: the trigger migration so every outcome kind can be dismissed; the shared
  "rows that carry their own ×" SQL predicate; and the first writer of `attention_request_state`
  (`outcome_generation`, `decision_revision`) — without which undo cannot detect a Restore or re-pin.
- **U09b — the sweep**: `attentionDismissAll` over server-captured membership including unloaded pages,
  resumable by id, reporting applied/skipped/failed, honouring owner decision A.
- **U09c — undo**: `attentionUndo`, bounded and conservative, restoring `cleared_*` and
  `tombstone_dismissed_at` — explicitly **not** reusing `markUnseen`, whose dedup-sibling refusal is the wrong
  model now that receipts are immutable.

### U10 — Primary projections and ordering

**Goal.** One representative per Request, active-only pages, ordering per D08.

**Owns.** `attention_repository.dart` projections/DTOs, My Work ordering inputs.

**Steps.** Grouping eligibility becomes *active attention* (uncleared optional + live obligations); ordering keys
separate **bumping** from **latest event** so non-bumping receipts (child-created, tombstones, timeline-only) do
not move a group; My Desk `Needs you` orders by latest live-obligation creation; stable first-entry ordering
replaces incidental `Beacon.updatedAt`; cursors are versioned when sort keys change; head refresh reconciles by
Request id.

**Acceptance.** An optional event changes dot/preview only; a new obligation promotes; summaries equal the
projections they claim to summarize.

**Tests.** Rewrite the `// CHANGES IN U10:` assertions from U02 with their new expectations; pagination
omission/duplication tests (a group moving above the cursor must not vanish).

---

**Card prerequisite (spec §4, blocking).** Extend the grouped projection with §0.1a provenance. Today forward
notes and the relay chain come only from `InboxProvenance`, parsed from the Hasura computed field
`inbox_item.inbox_provenance_data` — i.e. from the **Inbox** query — while `AttentionReceipt` carries no
provenance at all. A grouped `beacon:` row therefore cannot render the note that is the whole premise of the
card. This is server work and it gates U14 and U16.

---

**Split by the overseer after the U10 scout (2026-09-19).** Seven interlocking steps, and the scout named
**predicate drift** as the risk underneath the rest: changing `_visibleWithSurfaceCte` without
`AttentionDismissibleSql` makes the sweep and the feed disagree about what is dismissible. The scout put that
unification last; it runs **first**, so everything after has one source of truth to change.

- **U10a — one predicate source**: unify `AttentionDismissibleSql.prelude` with the repository's visible/surface
  CTE. No behaviour change; the sweep and the read path stop being two definitions of the same idea.
- **U10b — the axis move**: dots, counts, summaries and grouping eligibility move from `seen_at` to *active
  attention* (uncleared optional + live obligation); `clearedAt` / `clearReason` are exposed in the receipt
  projection (owed since U06b). This is what finally makes U08 and U09 visible. Includes **M1**: the
  default-list predicate and the indicator predicate are one function, with a test that they cannot diverge.
- **U10c — ordering**: separate the bumping key from the latest-event key so non-bumping receipts (child-created,
  tombstones, timeline-only) stop moving groups; `Needs you` orders by latest live-obligation creation; stable
  first-entry ordering replaces incidental `Beacon.updatedAt`; cursors are versioned and head refresh
  reconciles by Request id.

The `// CHANGES IN U10:` assertions from U02 belong to **U10b and U10c** — each rewrite must be named in the
journal with its old and new expectation, the standard this plan has held since U02.

**U10d added by the overseer (2026-09-19) — a concern I dropped when splitting.** The manifest put a *blocking*
card prerequisite inside U10 (§0.1a grouped-row provenance). Splitting U10 into U10a/b/c by theme — predicate,
axis, ordering — silently lost the fourth theme, and a grep for `strongestNotePreview` / `totalDistinctSenders`
confirms nothing implements it. U14 and U16 cannot build the For You card without it, so it runs as **U10d**,
together with the one untested m0187 backfill path U10c's verify found.

### U11 — Child propagation policy

**Goal.** R7 enforced at the producer.

**Owns.** `beacon_hierarchy_delivery_case.dart`, `beacon_hierarchy_outbox_repository.dart`,
`attention_intent_case.dart`, `beacon_child_create_case.dart`.

**Steps.** Keep one optional "child created" notice on the **direct** parent; classify propagated ancestor
lifecycle notices as **timeline-only** (no dot, no count, no ordering effect); keep copy generic when the source
Request is unreadable to the recipient.

**Acceptance.** Child messages/reviews/status changes leave parent attention and parent rank untouched; the
ancestor log entry still exists.

---

### U12 — Reconciliation

**Depends.** U07a (the matrix defines "correct").

**Goal.** "Reset counters" that actually repairs.

**Owns.** generalized obligation-repair case (from `review_obligation_backfill_case.dart`), authenticated endpoint.

**Steps.** Reconcile help-offer and review obligations against source state; create missing generations
idempotently; settle obsolete ones with their real reason; recompute projections/summaries; invalidate sessions.
Preserve clear state, Inbox stances and History. A correct result may still be non-zero.

**Acceptance.** Against a deliberately corrupted fixture, one invocation converges; a second changes nothing.

---

### U13 — Client data/domain integration

**Owns.** `features/attention/data/gql/*.graphql` + repository, `domain/attention/*`, `attention_case.dart`,
`feed_session_registry.dart`, ack store.

**Steps.** Typed documents for the §0.2 operations; normalized receipt/group projections so **child-level**
dismissal updates previews and counts (today ack application covers top-level items and skips unknown child ids);
optimistic apply/rollback per operation id; realtime invalidation extended to clear state, outcome generation and
ownership moves; stale page/summary responses may not overwrite a newer mutation result.

**Acceptance.** Two sessions converge; offline gestures fail visibly instead of silently queueing a
destructive-looking sweep; no second attention cache exists (architecture test).

---

**Split by the overseer after the U13 scout (2026-09-19).** Nine steps, and three findings that change the
shape of the work: the client `schema.graphql` is **behind** the server (no `clearedAt`, `listPositionAt`, none
of the new mutations); `ActivityOffersCubit` keeps a **shadow cache of hydrated offers beside `AttentionCase`**,
which is exactly what §0.3 forbids; and `markAllSeen` is still the read axis, not the clear axis. U13 runs as
three sandwiches:

- **U13a — transport**: sync the client schema, add the GraphQL documents, run codegen, and extend the domain
  entities (`clearedAt`, `clearReason`, the ordering fields, `provenanceJson`, the clear/sweep/undo result
  shapes). Mechanical, and nothing consumes it yet.
- **U13b — repository and case**: ports and repository methods for clear / sweep / undo / reconcile / history /
  snapshot, plus optimistic application with correct rollback and a mutation serial so a stale fetch cannot
  overwrite a newer mutation result. A server `partial` must not commit skipped members.
- **U13c — projections, realtime and single ownership**: normalized group/child projections so child-level
  dismissal updates previews and counts; **page-merge dedupe by Request id** (the duplicate-page property U10c
  handed to the client, which the server physically cannot test); realtime invalidation for clear state,
  outcome generation and surface moves; and an architecture test that there is exactly **one** attention owner —
  which `ActivityOffersCubit` currently violates.

### U14 — Shared event block and indicators

**Owns.** `activity_event_subcard_block.dart` → shared component, `my_work_obligation_block.dart`,
`my_work_whats_new_row.dart`, home indicator widgets/state.

**Steps.** One surface-neutral block: collapsed preview (obligations first) with reachable ×, **expand *and*
collapse**, cursor pagination past the current one-shot 100 cap, server totals not loaded-row counts, per-kind CTA,
focus/screen-reader position preserved when a row disappears. Indicators per D09 + **M1 one shared predicate**;
remove the current suppressions — the My Desk dot is gated on `surfaceNeedsYouTotal == 0` and both dots hide on
the active tab (`home_attention_state.dart:53–71`), neither of which the contract allows.

**Acceptance.** Dot and count render independently and survive tab selection; >100 active events paginate;
dismissing the last row does not shift the next × under the pointer (D32 mechanics).

**Tests.** Widget + golden tests at 360/390, light/dark, EN/RU, increased text scale.

---

**Card components (spec §5, §7).** U14 also promotes the private `_EventSubcard` into a public
`AttentionMiniCard` with a `forward` kind, and adds `TenturaRelationChip` to the **design system** (no generic
chip primitive exists today; `ForwardCapabilityChips` uses `RawChip` directly, and raw visual constants in feature
UI are lint-forbidden). Mini-card rules: one shape for every kind, quoted body left-aligned behind a rule,
capability chips attached to the forwarder inside the mini-card and never in the header, first collapsed slot
pinned to the latest note-bearing forward (D-171-5a), «ещё N» opens the Timeline and never expands in place
(D-171-5b) — which is what gives the card a hard maximum height by construction.

---

**Split by the overseer after the U14 scout (2026-09-19).** Six steps, and three live contradictions the scout
surfaced: the event subcards still call **`markSeen`** (the read axis) rather than `clearReceipt`; «ещё N»
**expands in place**, which D-171-5b forbids (it must open the Timeline, which is what gives the card a hard
height ceiling); and `home_attention_state.dart`'s suppressions — My Desk dot gated on
`surfaceNeedsYouTotal == 0`, both dots hidden on the active tab — are **encoded in existing tests**, so removing
them is a deliberate expectation rewrite. U14 runs as three sandwiches:

- **U14a — primitives**: `TenturaRelationChip` in the design system (no generic chip primitive exists; raw
  visual constants in feature UI are lint-forbidden), and `AttentionMiniCard` promoted out of the private
  `_EventSubcard` with the `forward` kind and full E32 dismiss mechanics (≥48 dp target, always-visible × on
  touch, hover toolbar and secondary tap on pointer devices, never long-press alone, layout height held until
  pointer-up, removal animated through a placeholder).
- **U14b — the active-event block**: obligations first, **expand *and* collapse**, cursor pagination past the
  one-shot 100 cap, server totals rather than loaded-row counts, `clearReceipt` replacing `markSeen`, and
  «ещё N» opening the Timeline instead of expanding in place.
- **U14c — indicators**: D09 independence (dot and count together), **M1** one shared predicate behind list and
  indicator, and removal of the two suppressions — each expectation rewrite named in the journal.

Goldens are audited inside whichever unit disturbs them, by the U0C method (RGBA pixel diff with bounding
boxes, canvas size checked), not re-recorded on faith. Every unit that changes card layout must assert the §9
height ceiling at 360 dp and 1.3× text.

### U15 — My Desk integration · U16 — For You integration

**U15 owns** `my_work_cubit.dart`, cards, section derivation: shared block replaces the obligation/what's-new
split; source actions only; stable sorting; archived attention discoverable from the dot that counts it.

**Constraint carried in from U14a's verify (overseer):** the mini-card height ceiling holds **up to three
capability chips**. A fourth long RU chip at 1.3× text measures **251 dp** against a 224 dp ceiling at 360 dp.
Spec §7.1 puts capability chips inside the forward mini-card, so U16 must **cap or coalesce** them — a forwarder
with four or more reason slugs otherwise breaks the §9 height ceiling the card's whole layout depends on.

### U15R — interim-review remediation (inserted 2026-09-19)

Astra's interim review found **nine defects on the seams between units that each passed verification in
isolation** (full text: `request-centric-attention-astra-interim-review.md`). They are fixed before U16, because
R4 blocks the card outright and R1/R2 mean owner decisions A and B are not yet delivered end to end.

- **U15R-a — server correctness**: R1 (clearing an outcome must not veto the Request's live attention; non-helping
  outcomes must lose their event counts and previews), R9 (derive `applied` from `UPDATE … RETURNING` so two
  concurrent single clears cannot both claim the same receipt), R3 (explicit clears get the same bounded undo
  metadata and per-member revision capture as sweeps), R8 (ordering anchors survive a Request losing all active
  attention).
- **U15R-b — provenance for the card**: R4 — the payload must carry an explicitly selected **latest note-bearing
  forward** with its identity and timestamp, because D-171-5a cannot be satisfied by sorting MR-ranked senders.
- **U15R-c — client correctness**: R2 (reading must stop moving clear-axis totals; optimistic `dismissAll` must
  use dismissible membership, not every cached receipt — today it violates owner decision A optimistically),
  R6 (honour `AttentionClearResult` instead of discarding it), R5 (one transition generation across **both**
  surfaces, with a test that actually observes For You), R7 (render dot **and** count together).

- **U15R-d — the indicators the contract actually specifies** (server + the client edge that reads it). U15R-c
  delivered R7's client half (dot and number render together) and stopped at the server, correctly: the numbers
  behind them do not mean what §6 says. Today `surfaceSummary` returns three fields and §6 asks for different
  ones:

  | §6 says | today's server field | why it is wrong |
  | --- | --- | --- |
  | `my desk.dot` = any owned Request has an uncleared **optional event or outcome** | `my_work_unread_total` = `activeAttention` on `surface='myWork'` | includes live obligations, so an obligation-only Request lights the optional dot; omits uncleared outcome rows |
  | `my desk.count` = sum of live obligations **on owned Requests** | `needs_you_total` = every live obligation, unscoped | not surface-scoped, so it can count what My Desk does not list |
  | `for you.dot` = any **dismissible attention, pending forward or pending prompt** | `activity_unread_total` = `activeAttention` on `surface='activity'` | counts obligations that live on the Activity surface, and misses both Set O outcome rows and the pending-forward zone |
  | `for you.count` = **never** | — | the client must be structurally unable to render one |

  The predicates all exist already — Set R, Set O and `eligible_pinned` (`status = 0`, readable, outside scope)
  are exactly "dismissible attention" and "pending forward". This unit **composes** them into per-surface totals;
  it does not invent a fourth definition. M1 binds: the same CTEs behind the lists back the indicators.

  **Pending prompts have no row at all yet** (the U09a note, restated in `dismissibleOutcomes`). They enter the
  For-you dot as a *named zero* — an explicitly written `0` with the comment saying what it is waiting for — never
  as silent absence, because silent absence is indistinguishable from a predicate someone deleted.

  Also in scope, both recorded during U15R-c rather than changed silently:
  - `RealtimeEntityKind.notification` still refreshes counters and pages in two uncoordinated steps — the R5
    defect class, on the one kind R5's brief did not name.
  - The axis contract is machine-checked **one way only**: the client test reads
    `docs/contracts/attention-active-attention-axis.json` and asserts the strings still appear in the server SQL,
    while the server PG test that produced those numbers never opens the file. Close the loop from the server side.

- **U15R-e — close the Request-less obligation gap, then finish §6's fourth rule.** U15R-d implemented three of
  §6's four indicator rules and stopped on the fourth exactly as its brief required: before scoping
  `my desk.count` to the myWork surface, prove the scoping drops nothing. It does not hold.
  `notification_outbox__beacon_policy_chk` (m0115) demands a `beacon_id` only for the `beacon_content` and
  `beacon_tombstone` access policies, so a `requires_action` row on a **profile**-policy destination stores
  cleanly with `beacon_id IS NULL`; `visibleWithSurface` then labels it `activity`, because the `scope` UNION can
  only absorb rows that name a Request. §6 has nowhere to put such a row — For You has no count, and its dot
  covers Set R, Set O and the pinned zone, none of which contains a live obligation.

  **Overseer decision: make storage agree with the producer.** This is not a product question, so it is not
  routed to the owner. `AttentionPolicy.logicalTaskKey` already throws `Live obligation requires a Request` and
  runs on every dispatched receipt: the codebase's own rule is that an obligation belongs to a Request. The
  alternative — giving §6 a term for a Request-less obligation — would invent a product concept that nothing in
  the contract, the plan or the write path asks for. So the gap closes by **constraint**, not by widening a
  predicate and not by extending §6:

  1. A migration adding `CHECK (NOT requires_action OR beacon_id IS NOT NULL)` to `notification_outbox`. It must
     **fail loudly** on a violating row rather than skip it — a silent repair here would hide precisely the
     producer bug the constraint exists to catch. Any legacy remediation belongs to U18, which already owns the
     unkeyed-obligation gate.
  2. With the shape unstorable, deliver §6's `my desk.count` as a **new** field (`myDeskCount`) scoped to
     `surface = 'myWork'`. **Not** by re-scoping `needsYouTotal`: U15R-d established that the legacy three keep
     their pre-U15R-d meaning until U18 retires them, and this unit does not get to make an exception for the
     one whose name happens to be closest. `attentionFeed`'s own `needs_you_total`
     (`attention_repository.dart:709`) is legacy for the same reason and stays as it is; if the feed needs the
     §6 count it gains its own field too.
  3. Rewrite the PG test that pinned the gap (`U15R-d contract gap — a beacon-less live obligation …`) into its
     inverse: the shape is now rejected, **by name**, the way U04 taught us to assert a constraint.

**R10 — found by the overseer while reviewing U15R-c, fixed directly.** `is_active_attention` is not one
expression: the stream union gives each `item_kind` its own, and a synthetic `requestActivity` row's is
`stats.event_unseen_count > 0`. U15R-c replaced a read-based filter with the **receipt** rule applied to all four
kinds, so a group card whose last optional child was cleared stayed on a list the server had already dropped it
from, showing `0`. Reproduced with a throwaway probe before being believed, then fixed as `isInUnreadView` — a
per-kind mirror with the server's table in its doc comment — and recorded in the shared contract under
`unreadViewMembershipByItemKind`. Same lesson as U15R-c's own findings, one layer down: a predicate that is
*correct for the common row* is still a cross-layer disagreement for every other row shape.

**R7 is an orchestrator error, recorded as such.** `docs/features/request-attention.md` §6 and design-plan D09
both say the dot and the number are independent and appear together. My U14c brief paraphrased §6 as "one badge
slot, count takes precedence", and the implementation correctly followed my brief rather than the source. Fourth
orchestrator error of the session, same mechanism as the other three: a brief assembled from prose instead of
from the authority it cites.

**U18 gains two explicit gates** from the compounding deferrals: legacy obligation identity (unkeyed rows that
reconciliation deliberately cannot repair) and historical hierarchy placement (pre-m0189 rows still counted as
primary attention). Its manifest previously described only the seen→cleared conversion.

**U16 also builds** `RequestAttentionCard` (spec §6, §9 state matrix) and `TombstoneRow` (spec §8, past-tense
copy), and retires `ActivityOfferCard`, `ActivityOfferBoundedShell`, `ActivityForwardRow` and
`inbox_forward_attribution_copy.dart` with their goldens. `InboxItemTile` / `InboxCardForwardsFold` retire in
U17 — but port `_SenderNoteBlock`'s content into the forward mini-card **before** deleting it: it is the only
place notes render today. The pinned card carries **no ×**; «Не могу помочь» lives in the overflow menu and opens
the rejection dialog, because declining is a social act and must never wear the quiet private gesture.

### U16 splits into three (inserted 2026-09-19, after U15R closed)

U16 as written is the card, the stream, the chrome and four retirements — far past what one inner run does
reliably. It runs as three sequential sandwiches, each its own unit:

- **U16a — the card itself.** `RequestAttentionCard` (spec §6 anatomy, §9 state matrix) and `TombstoneRow`
  (spec §8, past-tense copy), built against the design system, with no stream integration. Carries three
  constraints that are easy to lose: the `timeline` overflow policy; consumption of U15R-b's `latestNoteForward`
  provenance (D-171-5a cannot be satisfied by sorting MR-ranked senders); and the capability-chip **cap or
  coalesce** — the §9 height ceiling holds only to three chips, since a fourth long RU chip at 1.3× measures
  251 dp against a 224 dp ceiling at 360 dp. Also ports `_SenderNoteBlock`'s content into the forward mini-card
  — it is the only place notes render today, and U17 deletes its current home.
- **U16b — For You stream integration.** `activity_stream_view.dart`, `activity_offers_cubit.dart`,
  `inbox_cubit.dart`: one representative per Request, × on every outcome, the Watching digest duplication out of
  the primary stream while the Watching collection stays reachable from the overflow menu.
- **U16c — chrome and retirements.** Header **Dismiss all** replacing today's `markAllSeen` "Read all"
  (`inbox_screen.dart:261–283`), enabled by server eligibility; then retire `ActivityOfferCard`,
  `ActivityOfferBoundedShell`, `ActivityForwardRow` and `inbox_forward_attribution_copy.dart` with their
  goldens. The pinned card carries **no ×**; «Не могу помочь» lives in the overflow menu and opens the rejection
  dialog, because declining is a social act and must never wear the quiet private gesture.

**U16 owns** `activity_stream_view.dart`, `activity_offers_cubit.dart`, `inbox_cubit.dart`, chrome: one
representative per Request; × on every outcome; header **Dismiss all** replacing today's `markAllSeen`
"Read all" button (`inbox_screen.dart:261–283`), enabled by server eligibility; remove the Watching digest
duplication from the primary stream while keeping the Watching collection reachable from the overflow menu.

**Acceptance (both).** The `// CHANGES IN Uxx:` assertions are updated deliberately, with the new expectation
stated in the journal.

---

### U17 — Detail, History, Settings, rewards

**Owns.** `beacon_view` entry lifecycle + timeline sheet, `updates_screen.dart`, `settings_screen.dart`, l10n,
assets. Split into four commits: detail-entry · timeline/History · Settings · rewards.

**Steps.** Centralize successful-open clearing across **every** entry route (My Desk, For You, push, History,
profile, graph, deep link) — today acknowledgment fires from individual call sites, sometimes before navigation
succeeds; a forbidden or failed route clears nothing. History keeps read/unread semantics that never resurrect
primary attention. Settings gains **Reset counters** with progress, honest failure and no implementation jargon.
Cleared states per owner decision A: *nothing here* / *nothing new (decision zone may remain)* / *nothing matching
this filter*; per-operation cleared count mandatory, "cleared N today" only if its timezone and undo accounting
pass.

---

### U18 — Backfill and activation

**Owns.** restartable backfill tooling, version gate.

**Steps.** Fixed cutover boundary; existing seen optional receipts become `cleared_at` with `clear_reason =
legacy_seen`; unseen stay active; prior tombstone dismissals stay cleared; old read mutations lose the ability to
clear new attention. **No dual-behaviour window** — no users, web-only client: one release plus a
`kDefaultMinClientVersion` bump. Backfill replays no notifications and is restartable.

**Acceptance.** Backfill interrupted at an arbitrary point and re-run produces the same state.

---

### U19 — Acceptance and release

Full matrix, separately reported: focused tests · PG integration · browser journeys · release compatibility.
Browser journeys drive real controls (the ten in the design plan §7.3), not seeded end state. Version bump and
the tracked `flutter_bootstrap.js?v=` cache-buster in `packages/client/web/index.html` move together.

---

## 3. Gates

| Gate | Command |
|---|---|
| Server unit | `./scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --exclude-tags pg` |
| Server PG | `… -- dart test --tags pg -j 1` (a skip is a **block**) |
| Client | `… --timeout 45m -- flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env` |
| Lints | `./scripts/check-custom-lints.sh packages/client` and `… packages/server` (re-read the baseline file) |
| Terminology | `bash scripts/check-user-facing-terminology.sh` |
| Web e2e | `./scripts/run_client_integration_web_local.sh` |

**Release blockers.** No deletion path reaching a live obligation · no primary-surface use of `seen_at` as
cleared · no generic obligation dismissal route · every outcome kind dismissible · Dismiss all never applies a
decision · indicator and list predicates are one function.

## 4. Risks

1. **U10 is the widest blast radius** — it rewrites asserted behaviour. U02 exists so that the diff in
   expectations is explicit and reviewable rather than looking like breakage.
2. **U05 + U18 together are the only irreversible step.** Everything before is additive.
3. **Scope creep into review semantics.** Reviews are non-declinable by standing domain rule; a unit that finds
   itself changing review eligibility has left this plan.
4. **Memory pressure** — cap test parallelism (`-j 1` for PG), check `MemAvailable` before large client runs.
