# Request-centric attention — implementation journal

Append-only. One entry per unit, written **before** the next unit starts.
Manifest: [`request-centric-attention-implementation-plan.md`](request-centric-attention-implementation-plan.md).

Entry format: `UNIT` · `STATUS` · `WHAT` · `FILES` · `TESTS` (commands + real results) · `FINDINGS` ·
`DECISIONS` · `REMAINING`.

---

## UNIT 01 — Product contract · ACCEPTED (2026-09-18)

**WHAT.** Wrote the durable product contract and wired it into the documentation index and glossary, so the
attention rules stop being re-derived from plan documents.

**FILES.** `docs/features/request-attention.md` (new, 244 lines); `docs/README.md` (feature row + active-plan
row, `new-stuff-indicators` row re-labelled as superseded); `CONTEXT.md` (§ My desk: obligation, optional update,
Dismiss all, outcome row — each with `_Avoid_`; responsibility-split entry now points at the contract);
`docs/features/new-stuff-indicators.md` (superseded banner); `docs/plans/work-activity-redesign-plan.md`
(refinement note naming what D1/D5/D7/D10 become).

**TESTS.** `bash scripts/check-user-facing-terminology.sh` → `check-user-facing-terminology: ok`. Relative links
from the new document resolved by hand: all five targets exist. No code touched, so no suite was run.

**FINDINGS.**
- `NewStuffCubit` no longer exists in the client, so `features/new-stuff-indicators.md` documented a retired
  mechanism — including "the active tab hides its navigation dot", which the new contract reverses. Banner added
  rather than deletion, to keep the history.
- The contract had to state its own status carefully: it describes both shipped and unshipped behaviour, so it
  says explicitly that a disagreement with code means either a defect or an unshipped feature, and the plan
  decides which.

**DECISIONS.** Recorded today's missing `×` on `helping` / `watching` outcome rows inside the contract as a known
defect rather than writing the rule as if it already held.

**REMAINING.** None for U01. Next: U02 characterization tests.

---

## Overseer session 1 — opened 2026-09-18

**Objective.** Units **U06a → U02 → U03** of
[`request-centric-attention-implementation-plan.md`](request-centric-attention-implementation-plan.md), then stop.
U04 and beyond are deliberately withheld until U02 reports the factual behaviour of the current projections.

**Repository.** `/home/vader/MY_SRC/tentura`, branch `feature/events_refac`, starting HEAD `d79ace257`
("docs: request-centric attention contract, plan and manifest").

**Baseline verified by the overseer before any worker started** (not a worker claim):
`dart test --tags pg -j 1 attention_activity_stream_pg_test.dart attention_surface_pg_test.dart
my_work_attention_pg_test.dart attention_retention_pg_test.dart` → **35 passed, 0 skipped, exit 0**, through
`scripts/run_with_test_cleanup.sh`. Postgres containers up and healthy, so PG targets are genuinely reachable —
any later "skipped" PG result is a **block**, never a pass.

**Pre-existing worktree state (must survive untouched).**
Modified: `.serena/project.yml`, `docs/plans/constellation-pin-badge-zoom-lod-implementation-journal.md`,
`packages/force_directed_graphview/analysis_options.yaml`, `packages/force_directed_graphview/pubspec.lock`.
Untracked: ~40 files including many `docs/plans/*.md`, `CLAUDE.local.md`, `product_testing_*.md`, and the
secrets `key.fb`, `leo.key`, `out.key`, `dart-defines` — **no commit may contain these**.

**Environment.** `cursor-agent` 2026.09.15 with `composer-2.5` available (non-fast). MemAvailable 23.8 GB at start.

**Unit checklist for this session.**

| Unit | Status |
|---|---|
| U06a retention defect | worker 1 dispatched |
| U02 characterization tests | pending |
| U03 exhaustive classification | pending |

**Unresolved decisions/blockers.** None at open.

---

## UNIT U06a — Retention defect · COMPLETE (2026-09-18)

**WHAT.** `deleteSettledOlderThan` no longer deletes live obligations (`requires_action = true`,
`settlement_kind IS NULL`) that are merely old, seen, and emailed. Added a PG test that reproduces the defect.

**FILES.**
- `packages/server/lib/data/repository/notification_outbox_repository.dart` — exclude live obligations in the
  retention DELETE predicate.
- `packages/server/test/data/repository/attention_retention_pg_test.dart` — new test
  *retains live obligations even when seen, emailed, and older than the retention window*.

**TESTS.**

Red before fix (new test only; repository unchanged):

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --tags pg -j 1 \
  test/data/repository/attention_retention_pg_test.dart
```

→ `00:01 +1 -1` — *retains live obligations…* failed: `Expected: <0> Actual: <1>` on `deleted` (row was
deleted). Prior test passed. Exit 1.

After fix — retention file:

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --tags pg -j 1 \
  test/data/repository/attention_retention_pg_test.dart
```

→ `00:02 +2: All tests passed!` Exit 0.

Attention regression:

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --tags pg -j 1 \
  test/data/repository/attention_activity_stream_pg_test.dart \
  test/data/repository/attention_surface_pg_test.dart \
  test/data/repository/my_work_attention_pg_test.dart \
  test/data/repository/attention_retention_pg_test.dart
```

→ `00:12 +36: All tests passed!` (35 prior + 1 new). 0 skipped. Exit 0.

Lints:

```bash
./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server
```

→ `tentura_lints: packages/server total: 0 (baseline: 0)` · `check-custom-lints: packages/server OK`. Exit 0.

**FINDINGS.**
- `notification_outbox.cleared_at` does not exist in the current schema (planned in U04). An “uncleared optional”
  sibling case cannot be expressed yet; retention still deletes old optional receipts that are seen and emailed.

**DECISIONS.** Guard retention with `NOT (requires_action = true AND settlement_kind IS NULL)` only; defer
optional-clear retention exemption until `cleared_at` lands in U04.

**REMAINING.** U04 should extend `deleteSettledOlderThan` to keep uncleared optional receipts
(`requires_action = false` and `cleared_at IS NULL` once the column exists).

---

### Manager verdict — U06a · **ACCEPTED**

Independently re-verified, not taken from the worker's report:

- `dart test --tags pg -j 1` over the four attention suites, run by the overseer after the worker exited →
  **36 passed, 0 skipped, exit 0**, including the new
  *"retains live obligations even when seen, emailed, and older than the retention window"*. The pre-worker
  baseline was 35/0/0, so the delta is exactly the one new test.
- Commit `3df3d8eee` contains exactly three files (repository, test, journal); `git diff --check` clean; no
  migration, no schema change, no generated file, no secret.
- Worktree audit: all 4 pre-existing modified files and ~40 untracked files (including `key.fb`, `leo.key`,
  `out.key`, `dart-defines`) are byte-identical to the pre-worker snapshot.
- The fix is total, not merely sufficient: `requires_action` is `boolean NOT NULL DEFAULT false` (m0118:9), so
  `NOT (requires_action = true AND settlement_kind IS NULL)` has no NULL-semantics hole.
- Leaked process check: one `worker-server` node process from this run survived the agent's exit and was killed.
  The user's own Cursor IDE worker (a different install, version 2026.09.10) was left alone.

Reviewer notes carried forward, neither blocking:
1. The new test asserts `deleted == 0` for the whole retention run rather than asserting only its own row
   survived. It passes today because no other fixture in the group is deletable at that point, but it couples the
   test to its neighbours. If that group grows, tighten it to a per-row assertion.
2. `requires_action = true` could be plain `requires_action`; cosmetic only.

**Accepted scope boundary.** Retention still deletes old seen+emailed *optional* receipts, because `cleared_at`
does not exist until U04. The worker correctly refused to invent the column and recorded the follow-up predicate
instead. U04 must carry it.

| Unit | Status |
|---|---|
| U06a retention defect | **accepted** (`3df3d8eee`) |
| U02 characterization tests | worker 2 dispatched |
| U03 exhaustive classification | pending |

---

## UNIT U02 — Characterization tests · COMPLETE (2026-09-18)

**WHAT.** Ran the full attention PG and client suites; tagged assertions the manifest will deliberately break;
added PG characterization tests for surface transitions, Activity grouping eligibility, pinned-zone membership,
and receipt-based obligation counting. No production code.

**FILES.**
- `packages/server/test/data/repository/attention_activity_stream_pg_test.dart` — `// CHANGES IN Uxx:` tags + 5
  new grouping/pinned tests.
- `packages/server/test/data/repository/attention_surface_pg_test.dart` — help-offer transition + `needsYouTotal`
  characterization tests.
- `packages/client/test/features/my_work/my_work_obligation_subcards_test.dart` — U07b tags on generic Done.
- `packages/client/test/features/my_work/my_work_attention_state_test.dart` — U07b tags on `settleObligation`.

**TESTS.**

Baseline (before edits):

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --tags pg -j 1 \
  test/data/repository/attention_activity_stream_pg_test.dart \
  test/data/repository/attention_surface_pg_test.dart \
  test/data/repository/my_work_attention_pg_test.dart \
  test/data/repository/attention_retention_pg_test.dart \
  test/data/repository/attention_live_obligations_pg_test.dart \
  test/data/repository/attention_mark_seen_for_beacon_pg_test.dart \
  test/data/repository/attention_repository_pg_test.dart
```

→ `00:20 +62: All tests passed!` 0 skipped. Exit 0.

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 45m -- flutter test \
  --dart-define=ENV=test --dart-define-from-file=env/test.env \
  test/domain/attention test/features/inbox test/features/my_work test/features/home
```

→ `00:19 +407: All tests passed!` Exit 0. MemAvailable 23200388 kB at client suite start.

After all U02 commits (same server command as baseline):

→ `00:21 +70: All tests passed!` 0 skipped. Exit 0 (+8 characterization tests vs 62 baseline).

Touched client files:

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  --dart-define=ENV=test --dart-define-from-file=env/test.env \
  test/features/my_work/my_work_obligation_subcards_test.dart \
  test/features/my_work/my_work_attention_state_test.dart
```

→ `00:00 +13: All tests passed!` Exit 0.

**Intentionally doomed assertions (`// CHANGES IN Uxx:`)**

| File | Test / assertion | Unit | Expected after change |
|---|---|---|---|
| `attention_activity_stream_pg_test.dart` | `active help offer produces helping forward outcome` (test + `forwardOutcome == helping`) | U09/U10 | No cross-surface duplicate: live attention stays My Work-only; helping row in Activity becomes dismiss tombstone only or leaves Activity per D01/D08. |
| `attention_activity_stream_pg_test.dart` | `helping forward has zero Activity event children` (`eventTotal == 0`, empty preview) | U09/U10 | Active-only grouping may attach uncleared optional children to the outcome row or suppress differently once eligibility tightens. |
| `attention_activity_stream_pg_test.dart` | `status event merges into forward and bumps created_at` (`createdAt` equals latest status time) | U10 | Optional status events update preview/dot only; forward sort key stays anchored; obligation creation promotes. |
| `attention_activity_stream_pg_test.dart` | `activityOffers orders by effectiveActivityAt not latest_forward_at` (beacon order + status bump) | U10 | Optional events must not reorder pinned Requests; stable first-entry / obligation-driven ordering replaces `effectiveActivityAt` bumping. |
| `my_work_obligation_subcards_test.dart` | `Respond and Done are independent hit targets` (`Done` semantics id present) | U07b | Generic Done removed for non-review obligations; resolution only via source actions/sheets (owner decision C). |
| `my_work_attention_state_test.dart` | `settleObligation removes receipt and calls settle` (`settleCalls` records generic settle) | U07b | Cubit must not call generic settlement for help-offer obligations; server rejects bare acknowledge settlement. |

**FINDINGS.**
- Surface derivation for forward-only foreign receipts is visible on the **unfiltered** feed (`surface: null`);
  `surface: activity` page stream can be empty while the receipt is still classified `activity` (pinned/coalescing).
  Transition characterization uses the unfiltered feed for before/after surface checks.
- `liveObligationBeacons` deduplicates beacon ids, but `surfaceSummary.needsYouTotal` counts **receipts** (two live
  obligations on one owned Request → `2`). Characterized explicitly; not a defect.
- Retention live-obligation guard from U06a left unchanged; no duplicate retention tests added here.

**DECISIONS.** Did not tag `two status events without inbox coalesce to requestActivity` — coalescing structure
survives U10; only optional-event **ordering/bumping** tags were required. Client doom tags limited to generic
Done/settle paths slated for U07b.

**REMAINING.** None for U02. U10 should rewrite tagged server assertions; U07b should rewrite tagged client
obligation settlement tests; U09 extends outcome dismiss to helping/watching rows.

| Unit | Status |
|---|---|
| U06a retention defect | **accepted** (`3df3d8eee`) |
| U02 characterization tests | **complete** (`dc235c284`, `c51daa172`, `2aef2d9ae`) |
| U03 exhaustive classification | pending |

---

### Manager verdict — U02 · **ACCEPTED**

Independently re-verified by the overseer after the worker exited:

- Server, 7 attention PG files → **70 passed, 0 skipped** (62 before this unit + 8 new).
- Client, `domain/attention` + `features/{inbox,my_work,home}` → **407 passed, 0 skipped** (unchanged, as
  expected: this unit added no client tests, only annotations).
- `packages/*/lib` diff across the whole unit: **0 files**. The no-production-code rule held.
- Commits are properly split: `dc235c284` annotations · `c51daa172` tests · `2aef2d9ae`/`45efdd878` journal.
- Worktree audit: pre-existing modified and untracked files, including the secrets, untouched.
- Leaked `worker-server` process killed; the user's own Cursor IDE worker (2026.09.10 install) left alone.

**Quality above brief.** The instruction named four line numbers in one server file. The worker placed 12 tags
across three files and, unprompted, found the **client-side** assertions that owner decision C will invalidate —
`my_work_obligation_subcards_test.dart` and `my_work_attention_state_test.dart` both assert that a help-offer
obligation settles through generic Done. Without those tags, removing the Done control in U07b would have looked
like two broken client tests instead of an intended consequence.

**Two findings worth carrying into U10** (both now pinned by tests):
1. A forward receipt reports `surface: activity` on the unfiltered feed while the Activity *page* stream can be
   empty, because of pinning and coalescing. "Which surface the receipt claims" and "what the tab renders" are
   not the same question, and a projection rewrite can satisfy one while breaking the other.
2. `needsYouTotal` counts obligation **receipts** (two obligations on one Request → 2) while
   `liveObligationBeacons` dedupes by Request. Swapping one for the other during the rewrite would silently
   desynchronise the badge from the section header.

**Reviewer note, non-blocking.** `45efdd878` exists only to correct a commit hash the worker had written into its
own journal status table. Harmless, but the status table should be written after the commit it references.

| Unit | Status |
|---|---|
| U06a retention defect | **accepted** (`3df3d8eee`) |
| U02 characterization tests | **accepted** (`dc235c284`, `c51daa172`) |
| U03 exhaustive classification | worker 3 dispatched |

---

## UNIT U03 — Exhaustive classification · COMPLETE (2026-09-18)

**WHAT.** Bumped `updates-event-contract.json` to schema 3 with `eventClassifications` for all 29
`AttentionEventType` values (33 recipient-specific variants). Removed the `_requiresAction` default-optional
fallback; added compile-time/runtime declaration guard on `AttentionPolicy.project`. Upgraded server/client
architecture tests for exhaustive enum coverage, obligation field obligations, optional non-bump ordering,
hierarchy `timeline_only` placement, and `recoverableVia: none` retention exemption (soft-reported `unverified`
gaps until U19).

**FILES.**
- `docs/contracts/updates-event-contract.json`
- `packages/server/lib/domain/attention/attention_models.dart`
- `packages/server/lib/domain/attention/attention_policy.dart`
- `packages/server/test/architecture/updates_event_contract_test.dart`
- `packages/client/test/architecture/updates_event_contract_test.dart`

**TESTS.**

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --exclude-tags pg \
  test/architecture test/domain/attention
```

→ `00:03 +88: All tests passed!` Exit 0.

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --tags pg -j 1 \
  test/data/repository/attention_activity_stream_pg_test.dart \
  test/data/repository/attention_surface_pg_test.dart \
  test/data/repository/my_work_attention_pg_test.dart \
  test/data/repository/attention_retention_pg_test.dart \
  test/data/repository/attention_live_obligations_pg_test.dart \
  test/data/repository/attention_mark_seen_for_beacon_pg_test.dart \
  test/data/repository/attention_repository_pg_test.dart
```

→ `00:19 +70: All tests passed!` 0 skipped. Exit 0. (First run after parallel suites hit a RAM tmpfs kernel
race at `+44 -3`; `./scripts/run_with_test_cleanup.sh --sweep-only` then rerun succeeded.)

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- flutter test \
  --dart-define=ENV=test --dart-define-from-file=env/test.env test/architecture
```

→ `00:01 +16: All tests passed!` Exit 0.

```bash
./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server
```

→ `check-custom-lints: packages/server OK` (tentura_lints total 0). Exit 0.

**Classification inventory (today's `AttentionPolicy` behaviour).**

| Event type | Obligation (`requires_action`) | Suppression / preference highlights | Notes |
|---|---|---|---|
| `helpOfferSubmitted` | author only | author mandatory, steward standard | `attention_policy.dart` `_requiresAction`, `_suppression` |
| `reviewOpened` | all recipients | mandatory | only other obligation type today |
| All other 27 types | false | per-type switches in `_suppression`, `_category`, `_accessPolicy`, `_destination` | previously fell through `_ => false` in `_requiresAction` |

**Declared variants:** 33 across 29 event types. **`unverified` fields (10 unique paths, 12 variant-field entries):**
`beaconHierarchyStatusChanged.producerTests` (×2 variants), `staleReminder.recipientPredicate`,
`staleReminder.recoverableVia`, `commitmentResolved.recipientPredicate`, `commitmentResolved.recoverableVia`,
`deadlineChanged.recipientPredicate`, `deadlineChanged.recoverableVia`, `deadlineChanged.producerTests`,
`deadlineReminder.recipientPredicate`, `deadlineReminder.recoverableVia`, `deadlineReminder.producerTests`.

**FINDINGS.**
- Mandatory suppression (`needsMe`, `deadlineReminder`, …) does not imply obligation — only
  `helpOfferSubmitted` (author) and `reviewOpened` set `requires_action` today.
- Contract declares `orderingEffect: stable` for optional types and `timeline_only` for
  `beaconHierarchyStatusChanged`, while Activity SQL still bumps optional children and still surfaces propagated
  hierarchy receipts on primary Activity — left unchanged per safety property; U10/U11 close the gap.
- `reviewOpened` resolution in contract cites `EvaluationCase.submitReviewPackage` from settlement paths; exact
  transition naming may need tightening in U07b when lifecycle audit completes.

**DECISIONS.** Legacy six-field `eventTypes` producer rows kept for the original 15 producers; exhaustive
semantics live in `eventClassifications`. Architecture tests report `unverified` gaps without failing (U19 gate).
`AttentionEventTypeCatalog.assertDeclared` uses an exhaustive switch so a new enum value fails analysis until both
the switch and contract row land.

**REMAINING.** U19: drive `unverified` count to zero; U07b: align obligation `resolutionTransitions` with audited
settlement code; U10/U11: make SQL/grouping match declared `orderingEffect` and hierarchy `placement`.

| Unit | Status |
|---|---|
| U03 exhaustive classification | **complete** (`b954d26c7`, `1c4f9c4ef`, `dcaf6edce`) |

---

### Manager verdict — U03 · **ACCEPTED**

Independently re-verified by the overseer after the worker exited:

- Server non-PG (`test/architecture` + `test/domain/attention`) → **88 passed**.
- Server PG, 7 attention files → **70 passed, 0 skipped** — *identical to the pre-unit count*. This is the
  evidence that matters for this unit: the classification refactor changed declarations, not behaviour.
- Client `test/architecture` → **16 passed**.
- `check-custom-lints.sh packages/server` → `total: 0 (baseline: 0) OK`.

**Design of the change, reviewed and endorsed.**
- The contract gained a new top-level `eventClassifications` block with **29 entries — one per runtime
  `AttentionEventType`** — while the legacy `eventTypes` (15) was left untouched. Additive, so existing consumers
  and their tests are undisturbed.
- Classification is expressed as `variants[]` keyed by `recipientPredicate`, not one value per type. This was the
  non-negotiable shape: `helpOfferSubmitted` is an obligation for `reason:authorOfBeacon` and an optional update
  for every other recipient, and a flat per-type field could not have expressed it.
- `_requiresAction` now enumerates all 29 values instead of falling through `_ => false`, and each retains
  today's outcome (obligations remain exactly `reviewOpened` and author-facing `helpOfferSubmitted`).
  `AttentionEventTypeCatalog.assertDeclared` at the policy entry point makes an undeclared type fail loudly
  instead of defaulting to silently optional.

**Honest gaps, accepted as designed.** Five variants carry `recoverableVia: unverified` —
`beaconHierarchyStatusChanged`, `staleReminder`, `commitmentResolved`, `deadlineChanged`, `deadlineReminder`.
These are exactly the types whose surviving content cannot be established from code in one pass. The brief
permitted `unverified` and forbade guessing; the worker used the permission rather than inventing a claim.
**U19 must drive this count to zero** — it is the release gate for the dismissible-implies-derivable rule.

**Carried forward to U07a — do not lose this.** The author-obligation variant declares
`HelpOfferCase.withdrawHelpOffer` among its `resolutionTransitions`. The declaration states what *should* settle
the obligation; the independent Astra review of this plan established that withdrawal today updates the offer,
access, Inbox state and receipts **without** settling the author's obligation. So the contract now encodes an
intent the code does not yet honour. That is the correct direction, but it means U07a's audit must treat this row
as a known open gap, and U07b must close it.

**Discipline.** The tests U02 wrote and tagged were not modified (verified by file list). Commits are split into
three reviewable subjects — contract data `b954d26c7`, policy `1c4f9c4ef`, enforcement `dcaf6edce` — plus journal.
No migrations, no SQL, no UI, no generated files. Pre-existing worktree changes and secrets untouched.

---

## Overseer session 1 — CLOSED

Scope was U06a → U02 → U03, and all three are accepted. U04 and beyond were deliberately withheld pending U02's
findings, which have now arrived (see the two carried-forward facts in the U02 verdict and the withdrawal gap
above). The recommended next step is **U07a**, the obligation-transition audit — an investigation unit producing
a transition matrix, not an implementation — because both U07b and U12 are unschedulable without it, and because
U04's table shapes should be designed against the projections U02 has now pinned rather than against plan prose.

| Unit | Status | Commits |
|---|---|---|
| U01 product contract | accepted | `d79ace257` |
| U06a retention defect | accepted | `3df3d8eee` |
| U02 characterization tests | accepted | `dc235c284`, `c51daa172` |
| U03 exhaustive classification | accepted | `b954d26c7`, `1c4f9c4ef`, `dcaf6edce` |

Independent verification totals at close: server PG 70/0 skipped · server non-PG 88 · client attention+features
407 · client architecture 16 · server lints at baseline.

### Overseer fixup after session close

`a-posteriori` worktree audit found one line of U02's tagging pass left uncommitted:
the second `// CHANGES IN U07b:` marker in
`packages/client/test/features/my_work/my_work_attention_state_test.dart`. Committed by the overseer as a
separate focused commit. Cause: the U02 acceptance checked that `packages/*/lib` was untouched but did not
re-diff the worktree against the pre-worker snapshot, which the U06a acceptance did. Both checks belong in every
acceptance from now on.

Worktree integrity re-confirmed at close: 38 untracked files (44 at session open minus the 6 documentation files
the overseer committed) and the 4 pre-existing modified files, with `key.fb`, `leo.key`, `out.key` and
`dart-defines` present and unmodified.

## Overseer-sandwich session 2 — opened 2026-09-19 00:15

**Objective.** Implement the remaining manifest autonomously: U0C, U03b, U07a, U04–U19.
**Repository.** `feature/events_refac`, starting HEAD `8bc8114f6`.
**Pre-existing worktree (must survive).** 4 modified (`.serena/project.yml`, constellation journal,
`force_directed_graphview` ×2) and 37 untracked, including `key.fb`, `leo.key`, `out.key`, `dart-defines`.

**Layers verified at open.** `cursor-agent` 2026.09.15 with non-fast `composer-2.5`; `claude` 2.1.277 probed —
`init` reported `"model":"claude-opus-5"`, effort low, exit 0; `codex-cli` 0.154.0 installed.
**Escalation path at open: SUBSTITUTE ONLY.** Astra returns at 04:00 local; until then any escalation runs
`run_opus_worker.sh --effort high`. Owner's budget for Astra: 3–4 small parts *or* one whole-implementation
review. Reserved for **one final review** unless a hard defect survives a remediation sandwich.
MemAvailable at open: 45.6 GB.

**Unit order and risk tags.**

| # | Unit | Tag |
|---|---|---|
| 1 | U0C Following rename | routine |
| 2 | U03b card contract fields | routine |
| 3 | U07a obligation transition audit | investigation — read-only Composer, no sandwich |
| 4 | U04 additive schema | hard (migration safety) |
| 5 | U05 immutable dispatch identity | hard (identity, dedup, concurrency) |
| 6 | U06b retention + history read | routine |
| 7 | U07b obligation lifecycle | hard (transaction boundaries) |
| 8 | U08 clear command | hard (races) |
| 9 | U09 outcomes, sweep, undo | hard (concurrency, social side effects) |
| 10 | U10 primary projections and ordering | hard (widest blast radius) |
| 11 | U11 child propagation policy | routine |
| 12 | U12 reconciliation | routine |
| 13 | U13 client data/domain integration | hard (multi-device convergence) |
| 14 | U14 shared event block + indicators | routine |
| 15 | U15 My Desk integration | routine |
| 16 | U16 For You integration + card | routine |
| 17 | U17 detail, History, Settings, rewards | routine |
| 18 | U18 backfill and activation | hard (cutover) |
| 19 | U19 acceptance and release | final verification |

**Blockers at open.** None.

---

## UNIT U0C — "Following" rename · SCOUT BRIEF (2026-09-19)

**Scout:** read-only pass on `feature/events_refac` at `UNIT_BASE` `0c691d132`. No code touched.

### l10n format and paths

- **Source (git-tracked):** `packages/client/l10n/app_en.arb`, `packages/client/l10n/app_ru.arb` — JSON ARB, `@@locale` + `@key` metadata blocks.
- **Config:** `packages/client/l10n.yaml` — `arb-dir: l10n`, `template-arb-file: app_en.arb`, `output-class: L10n`, `output-dir: lib/ui/l10n`, `output-localization-file: l10n.dart`.
- **Locales:** EN + RU only (two ARB files).
- **Generated (gitignored:** `packages/client/.gitignore` → `/lib/ui/l10n/*`): run `cd packages/client && flutter gen-l10n` after ARB edits; tests/CI load generated `L10n` / `L10nEn` / `L10nRu`.

### §10 table — key existence, live values, UI fit

All §10 keys **exist** in both ARBs today. Current values match spec “RU now / EN now” columns.

| Key | Live RU | Live EN | Where used (live) | Spec new value vs UI |
|---|---|---|---|---|
| `beaconHeaderWatch` | Наблюдать | Watch | `beacon_operational_header_card.dart`, `activity_offer_card.dart` — primary **button** | **Follow / Следить** — short verb fits button. |
| `beaconHeaderStopWatching` | Не наблюдать | Stop watching | Same header — **button** when `inboxStatus == watching` | **Unfollow / Не следить** — fits. |
| `inboxWatching` | Наблюдаю | Watching | `inbox_watching_screen.dart` AppBar title; `inbox_screen.dart` overflow `'${l10n.inboxWatching} ($count)'` | **Following / Слежу** — first-person label; overflow becomes `Following (2)` (see `inbox_watching_route_test.dart`). |
| `inboxTabWatching` | Наблюдаю | Watching | **No `l10n.inboxTabWatching` reference in `lib/`** (dead key today; still update for parity). | **Following / Слежу** — tab label when wired. |
| `inboxWatchingEmptyCalm` | Нечего отслеживать. | Nothing to watch. | `inbox_watching_screen.dart` empty state **sentence** | **Nothing to follow yet. / Пока не за чем следить.** — calm empty copy fits. |
| `inboxTabWatchingEmpty` | Нет запросов в наблюдении | No requests on your watch list | **Unused in `lib/`** (screen uses `inboxWatchingEmptyCalm` instead). | **You are not following anything / Вы ни за чем не следите** — second-person sentence OK per §8a for system copy. |
| `actionWatch` | Переместить в «Наблюдение» | Move to Watching | `beacon_overflow_menu.dart` overflow **menu row** | **Follow this request / Следить за запросом** — action phrase fits menu (longer than chip). |
| `actionStopWatching` | Вернуть в «**Нужно мне**» | Return to Needs me | `beacon_overflow_menu.dart`, `inbox_item_tile.dart` overflow when watching | RU fix **Вернуть в «Ждёт меня»** matches live destination label `inboxNeedsMe` = **«Ждёт меня»** / EN **Needs me** (unchanged EN per §10). **Confirmed:** `inboxNeedsMe` is in ARB but **not referenced in `lib/` for display**; it is the canonical tab name for the return target per product docs. |
| `beaconHudYouWatching` | Наблюдаете | Watching | `beacon_hud_derivation.dart` — HUD **chip** | **Following / Слежу** — fixes register (§8a: first-person chip, not «Вы …»). |
| `beaconPeopleRoleWatcher` | Наблюдатель | Watcher | `beacon_people_labels.dart` — people tab **role** label | **Follower / Следит за запросом** — longer role string; verify layout in people tab. |
| `forwardWatching` | Наблюдение | Watching | `forward_recipient_row_host.dart` — recipient involvement **badge** | **Following / Слежу** — chip-like; spec uses same as tab (first person). |
| `forwardReactionWatching` | Наблюдает | Watching | `unified_forward_row.dart`, `profile_shared_beacons_sliver.dart` — **chip** on forward row | **Following / Следит** — third-person «Следит» for someone else’s reaction fits chip on another user’s forward. |
| `activityWatchingDigest` | …за которыми вы наблюдаете (ICU plural) | …you watch (ICU plural) | `activity_watching_digest_row.dart` — full **summary sentence** | **…you follow / …за которыми вы следите** — second-person system sentence OK. |
| `activityForwardOutcomeWatching` | Вы наблюдаете | You're watching | `activity_forward_outcome_copy.dart` → `activity_forward_row.dart` **outcome line** (not §10 literal row; §10 points to §8) | §8 tombstone: **You started following / Вы начали следить** — past-tense **event sentence**, not chip register; fixes #171 «Вы наблюдаете» complaint. |

**Not in §10 but same word family (ARB):**

| Key | Live RU | Live EN | Used? |
|---|---|---|---|
| `beaconPeopleStatusWatching` | Наблюдает | Watching | `beacon_people_labels.dart` status line — **missed by §10**; align with `forwardReactionWatching` (**Following / Следит**). |
| `beaconHudYouAskedToHelp` | …ответьте или **наблюдайте** | …respond or **watch** | `beacon_hud_derivation.dart` — **missed**; needs follow-family wording (e.g. «следите» / “follow”) if acceptance is “no watch/наблюд stems on attention surfaces”. |

### Hardcoded user copy outside ARB (same word family)

These are **not** l10n keys; **values-only U0C cannot satisfy manifest acceptance** without editing Dart (report as RISK, not a silent step):

| File | Strings |
|---|---|
| `packages/client/lib/features/forward/ui/message/forward_messages.dart` | `Request forwarded. It's in Watching.`; RU «…«Наблюдаю»»; `Open in Watching` / «Открыть в «Наблюдаю»» |
| `packages/client/lib/features/inbox/ui/message/inbox_messages.dart` | `Request moved to Watching`; RU «…«Наблюдаю»» |
| `packages/client/lib/features/beacon_view/ui/message/help_offer_messages.dart` | EN `…in Watching (not in Needs me).`; RU «…в «Наблюдении», не в «Нужно мне»» (also wrong Needs-me name vs «Ждёт меня») |

`scripts/check-user-facing-terminology.sh` does **not** scan for watch/наблюд — only beacon/room/inbox banned terms in ARB + selected message paths for beacon.

### Tests that hardcode old strings (will go red)

| Test file | What breaks |
|---|---|
| `test/features/inbox/activity_live_motion_test.dart` | `find.text('Наблюдать')`; `expect(find.text('Вы наблюдаете'), …)` |
| `test/features/inbox/inbox_watching_route_test.dart` | `find.text('Watching (2)')` (default EN locale) |
| `test/features/forward/forward_messages_test.dart` | Full `ForwardLocationMessage` EN/RU + label strings |
| `test/features/forward/forward_delivery_result_test.dart` | `'Request forwarded. It\'s in Watching.'` |
| `test/features/forward/forward_cubit_live_sync_test.dart` | same snackbar EN string |

**Not product l10n (optional / out of unit unless acceptance expanded):** `test/design_system/tentura_top_bar_test.dart` hardcodes `Tab(text: 'Watching')` for DS golden fixture; `coordination_target_candidates_test.dart` uses `userTitle: 'Watching'` as fixture data.

`test/l10n/request_terminology_contract_test.dart` — **does not** assert watch-family strings.

### Goldens

- `test/features/inbox/activity_forward_row_golden_test.dart` renders all `AttentionForwardOutcome` values including **watching** via live l10n → **`activity_forward_row_watching_{light,dark}_{en,ru}.png`** will drift when `activityForwardOutcomeWatching` changes (PNG files not present in workspace listing — may be local/CI artifacts; still run with `--update-goldens` only after visual review).
- `inbox_item_tile_golden_test.dart` / `activity_offer_card_golden_test.dart` — use EN l10n but default tiles **without** watch CTAs in fixtures; **unlikely** to change unless overflow/watch actions added to golden setup.

### Register rule (§8a / P7)

Chip/HUD/tab labels → first person (**Слежу / Following**). System sentences (empty states, digest, tombstone outcomes) → second person or past-tense event (**Вы начали следить**, **Вы ни за чем не следите**). Do not use «Вы наблюдаете»-style present state on outcome rows.

### Versioning

User-visible copy change → **patch bump** `packages/client/pubspec.yaml` + sync `web/index.html` `flutter_bootstrap.js?v=` per `AGENTS.md` / `versioning.mdc`.

---

STATUS: complete

BRIEF: After ARB value renames + `flutter gen-l10n`, every surface that today shows the Watching/наблюд-* family uses Follow/Following/Следить/Слежу per issue-171 §10 (plus missed ARB keys and §8 outcome for `activityForwardOutcomeWatching`); overflow menu shows `Following (N)`; stop-watching menu cites «Ждёт меня» in RU; no Dart key or call-site renames. **Partial acceptance risk:** hardcoded snackbar/message classes still expose Watching/Наблюдаю until a follow-up Dart copy edit (blocked for strict values-only unit).

STEPS:
1. Edit `packages/client/l10n/app_en.arb` + `app_ru.arb` — all §10 keys + `activityForwardOutcomeWatching` (§8) + missed `beaconPeopleStatusWatching`, `beaconHudYouAskedToHelp` — **red:** no (strings not asserted until gen-l10n).
2. `cd packages/client && flutter gen-l10n` — **red:** no (generated output gitignored).
3. Patch `packages/client/pubspec.yaml` (+ `web/index.html` cache-buster if version changes) — **red:** no.
4. Update tests: `forward_messages_test.dart`, `forward_delivery_result_test.dart`, `forward_cubit_live_sync_test.dart`, `inbox_watching_route_test.dart`, `activity_live_motion_test.dart` — **red:** yes (meaningful).
5. If forward-row goldens exist locally: `flutter test --update-goldens test/features/inbox/activity_forward_row_golden_test.dart` after visual check — **red:** golden diff only.
6. **Escalation (not values-only):** align `forward_messages.dart`, `inbox_messages.dart`, `help_offer_messages.dart` with new tab names — **red:** forward message tests; **requires Dart edits** — treat as RISK/decision unless manifest amends U0C scope.

TEST_CMD:
```bash
bash scripts/check-user-facing-terminology.sh
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  test/l10n/request_terminology_contract_test.dart \
  test/features/forward/forward_messages_test.dart \
  test/features/forward/forward_delivery_result_test.dart \
  test/features/forward/forward_cubit_live_sync_test.dart \
  test/features/inbox/inbox_watching_route_test.dart \
  test/features/inbox/activity_live_motion_test.dart
```

UNTOUCHABLE: `key.fb`, `leo.key`, `out.key`, `dart-defines`, `.serena/project.yml`, `packages/force_directed_graphview/**`, `docs/plans/constellation-*`, all generated artifacts (`*.g.dart`, `*.freezed.dart`, `_g/`, `packages/client/lib/ui/l10n/*` — regenerate only).

RISKS:
- **Scope vs acceptance:** Manifest U0C acceptance says no user-visible watch/наблюд on attention surfaces; **~6 hardcoded strings in three `*messages.dart` files** remain if only ARB is edited — values-only unit cannot fully meet acceptance without Dart changes (or manifest must narrow acceptance to ARB-only).
- **`activityForwardOutcomeWatching`:** §10 delegates to §8 tombstone copy (past tense), not a simple synonym swap — still ARB-only but changes semantics/tests/goldens; other `activityForwardOutcome*` keys are **out of §10 watch rename** (broader §8 tombstone work lands in later units unless bundled here intentionally).
- **`beaconPeopleRoleWatcher` → «Следит за запросом»:** long string in people tab — layout overflow on compact width.
- **`inboxTabWatching` / `inboxTabWatchingEmpty`:** unused in UI today; updating still correct for future tab wiring.
- **`actionStopWatching` EN** stays “Needs me” while RU moves to «Ждёт меня» — intentional per §10; EN tab label `inboxNeedsMe` is still “Needs me” (not “Waiting for me”).
- **`help_offer_messages.dart` RU** cites «Нужно мне» and «Наблюдении» — doubly stale vs `inboxNeedsMe` / rename; needs Dart edit outside strict U0C.
- **Goldens:** `activity_forward_row_*_watching_*.png` not in repo tree from scout glob — CI/local may fail until updated.

---

## UNIT U0C — "Following" rename · INNER (2026-09-19)

**Inner:** Claude Opus 5, `feature/events_refac`, base `0c691d132`. Four commits, all green.

### Commits

| # | Hash | Subject |
|---|---|---|
| 1 | `5d2776dea` | `copy(l10n)`: §10 rename + §8 tombstone table, 20 keys per locale |
| 2 | `bf87bb87b` | `copy(messages)`: 6 hardcoded literals in three `*_messages.dart` |
| 3 | `f83222d58` | `test`: expectation updates in 5 files |
| 4 | `9d66fca8a` | `test(goldens)`: 28 re-recorded inbox goldens |

### Test evidence

Focused set **RED** after commit 1 (copy landed, expectations not yet):

```
00:14 +34 -4: Some tests failed.
Failing tests:
  activity_live_motion_test.dart: reduced motion completes demotion without animation frames
  activity_live_motion_test.dart: watch demotion shows forward row with watching outcome (ru)
  activity_live_motion_test.dart: Показать on moved snackbar scrolls to demoted forward row
  inbox_watching_route_test.dart: overflow opens Watching and shows the count
```

Focused set **GREEN** after commit 3: `00:03 +38: All tests passed!`

Wide subset after commit 4 —
`flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env test/features/inbox test/features/my_work`:
`00:12 +261: All tests passed!` (was `+233 -28`, all 28 golden diffs).

**Full client suite** (not required, run to catch unanticipated assertions):
`02:20 +3655 ~29: All tests passed!`

Gates: `check-user-facing-terminology: ok` · `check-custom-lints: packages/client OK` (`total: 30 (baseline: 30)`,
unchanged). `MemAvailable: 44704732 kB` before the wide runs.

### Scope as executed

All four overseer overrides applied: hardcoded Dart literals included (override 1), §8 tombstone table landed
(override 2), **no version bump and `web/index.html` untouched** (override 3), the three missed keys included
(override 4).

Re-grepping the "наблюд" / "watch" / "Watching" stems across `packages/client/lib` and both ARBs myself
(override 4) turned up **no further user-visible hits** beyond the scout's list. Every remaining match is an
internal identifier and was deliberately left alone: `kPathInboxWatching`, the `'watching'` wire value in
`attention_receipt.dart`, `watchingDigestWire`, `InboxWatchingRoute`, `TestIds.activityWatchingDigest`, the
`inboxWatchingOpenCount` state fields, and GraphQL `watchingIds`. Keys are untouched, so no call site moved.

### Goldens (override 5 — inspected, not blind-updated)

All 28 diffs were opened before regenerating. Every one is confined to the text run that changed:

- `activity_forward_row` (19) — only the second line moves, e.g. RU master `[Вы][наблюдаете]` → test
  `[Вы][начали][следить]`; avatar, header line and trailing action pixel-identical.
- `activity_offer_card` (9) — only the Watch button label.

No layout shift and no overflow, including the 1.3x text-scale cases, which still soft-wrap inside the existing
height bound.

---

## UNIT U0C — "Following" rename · VERIFY (2026-09-19)

**Verifier:** read-only pass on `0c691d132..HEAD` (`2e0eaa8c7`) plus worktree spot-check. Judged against overseer overrides (widened Dart literals, §8 tombstones, no version bump, golden inspection).

### Commits vs steps

Five commits on branch; four implementation + one docs (`2e0eaa8c7` journal). Implementation chain matches focused steps: l10n → messages → tests → goldens. No `pubspec.yaml` / `web/index.html` diff in range. No edits to `.serena/project.yml`, `packages/force_directed_graphview/**`, or `docs/plans/constellation-*` in `0c691d132..HEAD` (worktree still shows pre-existing local mods on those paths — not introduced by U0C).

### TEST_OUTPUT (re-run by verifier)

| Command | Result |
|---|---|
| `bash scripts/check-user-facing-terminology.sh` | exit 0 — `check-user-facing-terminology: ok` |
| Focused client list (terminology + forward + inbox motion/watching) | **38 passed**, 0 failed (~9s) |
| `flutter test … test/features/inbox test/features/my_work` | **261 passed**, 0 failed (~18s) |

No deleted tests, no `@Skip`, no loosened matchers in U0C test diffs — assertion string updates only.

### Golden audit (28 PNGs, commit `9d66fca8a`)

**Method:** For every PNG in the golden commit, `git show 9d66fca8a^:path` vs working tree; PIL RGBA per-pixel compare; record canvas size and diff bounding box. **Sample of 7** named files cross-checked manually (watching/helping/closed/deleted/offer rows, EN/RU, 1.3x helping).

**Findings:** `dim_mismatch: 0` across all 28. Canvas sizes unchanged (e.g. forward row 360×82, offer card 360×156). Pixel diffs confined to single horizontal text bands (e.g. watching EN outcome line y=54–66 on h=82; offer card Follow button y=123–139 on h=156). Max changed-pixel ratio ~4.85% on forward-row watching EN — still only the second-line tombstone string (§8), not header/avatar/actions. All 28 forward-row outcome variants shifted because **all five** `activityForwardOutcome*` tombstone strings changed, not only watching — expected per override 2. **No GAP** for layout/overflow from golden analysis.

### Stem grep (user-visible)

**ARB values:** No «наблюд*»; no user-facing `Watching` / `Watcher` / bare `watch` in EN/RU values (uses Following/Follow/Unfollow/follow/след*). `@forwardReactionWatching` **description** still says “watching the beacon” — developer metadata only, not shipped copy.

**Dart user strings (`toEn`/`toRu`, l10n-backed UI):** Product copy uses Following/Слежу/follow family; hardcoded snackbars updated in three message files. **No remaining user-visible Watching/наблюд** in those paths.

**Internal identifiers left (expected):** `InboxWatchingRoute`, `kPathInboxWatching`, `moveToWatching`, `involvementWatchingIds`, `AttentionForwardOutcome.watching` / wire `'watching'`, `TestIds.activityWatchingDigest`, `stop_watch` menu id, code comments, generated `l10n.dart` **key names** (`inboxWatching`, etc.).

### Register §8a spot-check

| Surface | New copy | Register |
|---|---|---|
| HUD/tab chips (`beaconHudYouWatching`, `inboxWatching`, `forwardWatching`) | Following / Слежу | First-person chip — met |
| Forward reaction chip (`forwardReactionWatching`) | Following / Следит | Third-person on others’ row — met (spec) |
| Tombstone outcomes (`activityForwardOutcome*`) | e.g. You started following / Вы начали следить | Past-tense event to viewer — met |
| Empty/digest (`inboxTabWatchingEmpty`, `activityWatchingDigest`) | Second-person system sentences | met |
| `beaconHudYouAskedToHelp` | respond or follow / следите | met |

**Verifier STATUS:** pass

---

### Findings

1. **`beaconPeopleRoleWatcher` did not overflow** (override 6), so the spec value «Следит за запросом» was kept
   and the shorter fallback «Следит» was **not** needed. The only render site,
   `help_offer_tile.dart:158`, is an unconstrained soft-wrapping `Text` in a vertical `Column`, so a longer role
   label wraps rather than overflows. The full suite confirms no overflow anywhere.
   *But* that site prints `'<role> · <status>'`, which now reads **«Следит за запросом · Следит»**. It is not a
   regression — it read «Наблюдатель · Наблюдает» before — but it is redundant, and a future unit touching the
   people tab should probably shorten the role to «Следит» there. Flagged, not fixed: changing it now would
   contradict the §10 table this unit exists to land.
2. **`activityForwardOutcomeNotInterested`'s EN goldens did not change.** "Not interested" and "You declined"
   lay out identically in the test font; both `..._not_interested_{dark,light}_en.png` are byte-identical to
   `0c691d132`. Only the two RU variants moved. Verified rather than assumed.
3. **`dart format` is not clean on the message files at base.** Running it on `forward_messages.dart` and
   `inbox_messages.dart` reflowed ~30 unrelated lines (old-style switch-expression indentation). That noise was
   reverted and the copy edits re-applied in place, so commit 2 is 8 lines — pure copy. Anyone formatting these
   files later will produce a large unrelated diff.
4. **Two §10 keys are dead code today**: `inboxTabWatching` and `inboxTabWatchingEmpty` have no reference in
   `lib/` (the screen uses `inboxWatchingEmptyCalm`). Updated anyway for parity, as the scout recommended.
5. `actionStopWatching` EN is unchanged at "Return to Needs me" per the §10 table; only the RU value moved off
   the wrong destination name to «Вернуть в «Ждёт меня»». `help_offer_messages.dart` RU carried the same
   «Нужно мне» bug and was fixed with it.
6. Left alone as fixture data, not product copy: `tentura_top_bar_test.dart`'s `Tab(text: 'Watching')` design
   system fixture, `coordination_target_candidates_test.dart`'s `userTitle: 'Watching'`, and
   `forward_repository_involvement_test.dart`'s `'Watching note'`.

**Acceptance.** No user-visible "наблюд*" / "watch*" stem remains on the attention surfaces; every l10n key is
unchanged, so there is no code churn.

### Manager verdict — U0C · **ACCEPTED** (sandwich: scout ✓ / inner Opus-low ✓ / verify pass, no finisher)

Overseer's own checks, independent of both workers:
- `flutter test test/features/inbox test/features/my_work test/l10n` → **273 passed**; terminology gate ok.
- **Keys provably unchanged**: in the `.arb` diff every touched key appears exactly twice (once removed, once
  added), so no key was renamed or dropped — checked mechanically, not by eye.
- **Tests replaced 1:1, not weakened**: 10 assertions removed, 10 added, all literal string swaps
  (`find.text('Наблюдать')` → `'Следить'`, `'Вы наблюдаете'` → `'Вы начали следить'`); zero `skip:` /
  `isNotNull` / `isNotEmpty` additions.
- Leaked `worker-server` killed after the inner layer.

**The sandwich earned its cost here.** The scout found the spec's §10 table was incomplete (three missed keys)
and that the unit as written was unmeetable because ~6 user-facing strings are hardcoded outside l10n — which is
why the overseer widened the scope before the inner layer ran, instead of discovering it after. The inner layer
then found one more the scout missed (a bare `find.text('Watch')`), reverted `dart format` noise to keep the copy
commit at 8 lines, and verified golden byte-identity instead of assuming it. The verifier audited the 28
regenerated goldens with an RGBA pixel diff — 0/28 canvas-size changes, all deltas confined to the outcome text
line and the button label — which is the check that would have caught a layout regression hiding inside a
"just text" regeneration.

**Carried forward, not fixed (correctly):** the People tab now reads «Следит за запросом · Следит» — redundant,
but shortening it would contradict the §10 table this unit exists to land. Fix it when the People row is next
touched.

Commits: `5d2776dea` arb · `bf87bb87b` hardcoded snackbars · `f83222d58` tests · `9d66fca8a` goldens ·
`2e0eaa8c7` journal.

---

## UNIT U03b — Card contract fields · SCOUT BRIEF (2026-09-19)

**Scout:** read-only on `feature/events_refac` at `UNIT_BASE` `7b3771de6`. No production code, no tests, no commits.

### Live contract shape (extend, do not reinvent)

**File:** `docs/contracts/updates-event-contract.json` — top-level keys frozen by tests:
`schemaVersion`, `pendingProducerEventTypes`, `eventTypes`, `producers`, `eventClassifications`.

**`eventClassifications`:** exactly **29** rows (one per `AttentionEventType`), **33** `variants[]` total.
Each row: `{ eventType, status, variants }` where `status` is `supported` (all live today; no `deliberatelySilent` rows).

**Per-variant fields today** (allow-list in architecture tests — extras fail, omissions do not):

| Field | Notes |
|---|---|
| `recipientPredicate` | `reason:…` wire names; some `unverified` |
| `scope` | `beacon` (31 variants) or `account` (2) |
| `attentionClass` | `optional` \| `obligation` |
| `placement` | `primary` \| `timeline_only` (`beaconHierarchyStatusChanged` only) |
| `groupKey` | `beaconId` or `accountId` (tracks `scope`) |
| `orderingEffect` | `stable` \| `promote_on_obligation` \| `bump` (none today) |
| `accessPolicy` | e.g. `beacon_content`, `profile`, `history_only` |
| `recoverableVia` | includes `unverified` on 5 variants (U19 gate) |
| `clearPolicy` | `explicit_or_request_open` \| `forbidden` (obligations) |
| `producerTests`, `transitionTests` | path strings; may contain `unverified` |
| Obligation-only | `actionDescriptor`, `logicalTaskKey`, `resolutionTransitions` |
| `recoverableVia: none` only | `retentionExemption` (none today) |

**There is no `objectKeyKind` in the live contract** (only in `issue-171-activity-label-comprehension-analysis.md`).
Derive `headlineTreatment` from **`scope` + `groupKey` + event-type producer semantics**; cross-check
`destinationFamily` on the legacy 15-row `eventTypes` block where the event appears there.

### Guard tests (where to add U03b enforcement)

| File | Loads contract | Classification test | `schemaVersion` check |
|---|---|---|---|
| `packages/server/test/architecture/updates_event_contract_test.dart` | `_contractFile()` → `docs/contracts/updates-event-contract.json` | `event classifications cover every AttentionEventType` | `AttentionEventTypeCatalog.contractSchemaVersion` (currently **3** in `attention_models.dart`) |
| `packages/client/test/architecture/updates_event_contract_test.dart` | same path resolution | `event classifications cover every runtime AttentionEventType` (duplicated enum list) | local `_contractSchemaVersion = 3` |

**Why missing fields do not fail today:** the loop only asserts `variant.keys` ⊆ `allowedKeys` (no unknown keys).
It does **not** require the U03 §4.3 keys. Adding the three names to `_classificationVariantKeys` alone stays green.

**RED-first hook:** in both files, inside the per-variant loop, `expect(variant.keys, containsAll({'selfAuthored', 'headlineTreatment', 'coalescible'}))` plus typed value checks (`selfAuthored` bool; `headlineTreatment` ∈ `{beacon,user,system}`; `coalescible` bool). Add a dedicated rule: `relayReceived` + `reason:forwardRecipient` ⇒ `coalescible == false` (K6). Bump expected `schemaVersion` to **4** and `AttentionEventTypeCatalog.contractSchemaVersion` in the same commit as the guard (otherwise the first test fails on version alone).

`packages/server/test/architecture/updates_event_coverage_test.dart` — producers inventory only; **no** classification variant shape. Do not modify U02 PG/client characterization tests.

### `schemaVersion` bump to 4 — blast radius

Grep (updates contract only): readers are the two `updates_event_contract_test.dart` files and
`AttentionEventTypeCatalog.contractSchemaVersion`. No runtime Dart reads the JSON `schemaVersion` for dispatch.
`issue-171-card-spec.md` D-171-3 still says “schemaVersion 3”; manifest U03b explicitly overrides to **4**.

### Proposed `headlineTreatment` (33 variants)

**Derivation rule (live fields):**

| Rule | `headlineTreatment` | Variants |
|---|---|---|
| `scope == account` && `groupKey == accountId` | **`user`** | `mutualConnectionFormed` · `inviteAccepted` (1 each) |
| `scope == beacon` && event type uses **system-generated** attention copy (no person as headline actor) | **`system`** | `deadlineReminder` (1); `staleReminder` (1); `beaconHierarchyStatusChanged` (2) — `deadlineReminder` uses `actorUserId: ''`; hierarchy uses `BeaconHierarchyNoticeCopy.*` |
| All other `scope == beacon` && `groupKey == beaconId` | **`beacon`** | remaining **28** variants across 24 event types |

**Cannot derive from `scope`/`groupKey` alone** (need event-type / producer): which beacon-scoped types are `system` vs `beacon` — only the three types above. `trustGivenChanged` has `accessPolicy: profile` but stays **`beacon`** (grouped under request, header is still quoted request title per §6.1). `roomMessagePosted` has a user actor but card header remains request identity ⇒ **`beacon`**.

### Proposed `selfAuthored` (actor == recipient)

Contract field is **boolean** per variant (manifest / user brief), not the analysis doc’s `suppress`/`obligation` enum.

**Resolver default:** `BeaconNotificationRecipientResolver` skips `userId == actor` (`beacon_notification_recipient_resolver.dart:33–34`).

| Variant | `selfAuthored` | Evidence |
|---|---|---|
| **`reviewAllPackagesIn` · `reason:authorOfBeacon`** | **`true`** | `fromBeaconNotification` special-case: sole recipient is `notification.actorUserId` (author) (`attention_intent_case.dart:921–928`, `reviewAllPackagesIn` sets `actorUserId: authorUserId`) |
| **All other 32 variants** | **`false`** | Actor excluded from recipients or recipient is a different party (forwards, offers, coordination, invites, trust, etc.) |

**Viewer-relative copy** (tombstones, confirmations) is **out of scope** for this unit — those are outcome rows / l10n, not these 29 dispatch event types.

### Proposed `coalescible`

| Rule | Value |
|---|---|
| **`relayReceived` · `reason:forwardRecipient`** | **`false`** — forward note is only on the mini-card (§7.3 K6); note-less forwards coalesce at **UI** by filtering empty `notePreview`, not by setting this variant `true`. |
| **All other 32 variants** | **`true`** — including `roomMessagePosted` (same-kind «3 новых сообщения»), `helpOfferSubmitted` (offer message is not a forward note), obligations |

Optional future guard: if `recoverableVia == 'none'` and content is not derivable, coalescing may be unsafe (U19 / dismissible-implies-derivable) — not asserted in U03b unless manifest adds it.

### Multi-variant events (unchanged predicates; new fields usually constant per type)

| Event type | # variants | Notes for implementer |
|---|---|---|
| `helpOfferSubmitted` | 2 | obligation vs optional — same headline/coalescible; both `selfAuthored: false` |
| `requestStatusChanged`, `beaconHierarchyStatusChanged`, `blockerOpened` | 2 each | hierarchy: `timeline_only`; same `headlineTreatment` within type |
| All others | 1 | |

### Implementation steps (test-first)

1. **Guard + schema 4 (RED)** — `packages/server/test/architecture/updates_event_contract_test.dart`, `packages/client/test/architecture/updates_event_contract_test.dart`, `packages/server/lib/domain/attention/attention_models.dart` (`contractSchemaVersion = 4`). Run server + client architecture tests → fail on missing fields / version.
2. **Fill contract (GREEN)** — `docs/contracts/updates-event-contract.json`: `"schemaVersion": 4`; add three fields to all **33** variants per tables above.
3. **Journal + verify** — record command output; re-run architecture suites.

**Do not touch:** `_requiresAction` / `attention_policy.dart` obligation outcomes; U02-tagged tests; `updates_event_coverage_test` unless producer inventory changes (it should not).

### TEST_CMD (paths verified)

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --exclude-tags pg test/architecture
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env test/architecture
```

Optional narrow loop while iterating:

```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- dart test test/architecture/updates_event_contract_test.dart
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env test/architecture/updates_event_contract_test.dart
```

### Risks / contradictions

- **`objectKeyKind` absent** — headline mapping is by manifest + §6.1/§8 prose, proxied through `scope`/`groupKey`/producer; document in commit message if D-171-3 “by objectKeyKind” wording is stale.
- **`promiseWithdrawn` variant `reason:targetOfAsk`** vs **help withdrawal** notifying author/stewards (`commitmentEvent` resolver) — classification predicate may not match live recipients; U03 accepted; do not “fix” in U03b.
- **`staleReminder` / `deadlineChanged` / `commitmentResolved`** still carry `unverified` predicates — new fields should still be filled with best-effort booleans/enums.
- Adding keys only to the allow-list without `containsAll` **does not go red** — easy to ship a no-op guard.

---

## UNIT U03b — Card contract fields · INNER (2026-09-19)

**Inner:** Claude Code Opus 5 on `feature/events_refac`, base `7b3771de6`. Three commits, test-first.

### Step 1 — the guard, proven red (`11e0a5a2e`)

The scout's key finding held: `variant.keys, everyElement(isIn(allowedKeys))` only rejects *unknown* keys, so
adding the three names to `_classificationVariantKeys` alone is a no-op guard. The guard therefore asserts the
fields as **mandatory** (`containsAll(_mandatoryCardContractKeys)`), with value types (`selfAuthored` /
`coalescible` bool, `headlineTreatment` ∈ `{beacon,user,system}`) and two rules:

- `relayReceived` · `reason:forwardRecipient` ⇒ `coalescible == false` (§7.3 K6), keyed on the
  `(eventType, recipientPredicate)` pair so a future note-bearing forward variant must be added to the set
  explicitly rather than inheriting a default;
- `scope == 'account'` ⇒ `headlineTreatment != 'beacon'` — the account-scoped rows are headlined by a person,
  and this catches a copy-paste of the beacon default onto them.

Both readers of `schemaVersion` went to **4** in this same commit
(`AttentionEventTypeCatalog.contractSchemaVersion`, client `_contractSchemaVersion`), so the version test is red
in the same run.

Real red output — server:

```
$ cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --exclude-tags pg test/architecture
00:00 +9 -2: test/architecture/updates_event_contract_test.dart: event classifications cover every AttentionEventType [E]
  Expected: contains all of Set:['selfAuthored', 'headlineTreatment', 'coalescible']
    Actual: _CompactKeysIterable<String>:[
              'recipientPredicate', 'scope', 'attentionClass', 'placement', 'groupKey',
              'orderingEffect', 'accessPolicy', 'recoverableVia', 'clearPolicy',
              'producerTests', 'transitionTests'
            ]
     Which: has no match for 'selfAuthored' at index 0 along with 2 other unmatched
  relayReceived variant is missing card contract fields
00:00 +18 -2: Some tests failed.

Failing tests:
  test/architecture/updates_event_contract_test.dart: Updates contract has the exact revision 4 semantic coverage
  test/architecture/updates_event_contract_test.dart: event classifications cover every AttentionEventType
```

Client, same two failures:

```
$ cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env test/architecture
00:00 +0 -2: .../updates_event_contract_test.dart: event classifications cover every runtime AttentionEventType [E]
     Which: has no match for 'selfAuthored' at index 0 along with 2 other unmatched
  relayReceived variant is missing card contract fields
00:01 +14 -2: Some tests failed.
```

**Red counts: server 18 passed / 2 failed; client 14 passed / 2 failed.**

### Step 2 — contract data (`4634dc85b`)

`docs/contracts/updates-event-contract.json`: `schemaVersion` 3 → 4 and the three fields on all **33** variants.
The diff is 100 insertions / 1 deletion — purely additive plus the version line; no existing field moved.

Green:

```
$ cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --exclude-tags pg test/architecture
00:00 +20: All tests passed!

$ cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env test/architecture
00:01 +16: All tests passed!
```

Distribution: `headlineTreatment` = `beacon` 29 · `user` 2 · `system` 2; `coalescible: false` on exactly one
variant; `selfAuthored: true` on none.

### Reasoning for the judgment calls

**`headlineTreatment` is derived from `scope` + `groupKey` + producer, not from `objectKeyKind`** — that field
does not exist in the live contract; the manifest's wording is loose and D-171-3's "schemaVersion 3" is stale.
Rule applied: `scope == account` (⇒ `groupKey == accountId`) ⇒ `user`; actor-less system notice ⇒ `system`;
otherwise ⇒ `beacon`.

- **`deadlineReminder` ⇒ `system`.** `AttentionIntentCase.deadlineReminder` passes `actorUserId: ''` and
  `_deadlineIntent` then sets `actorUserId: null` on the dispatch intent
  (`attention_intent_case.dart:256–302`). There is no person to attribute the line to, so a bare system label is
  the only truthful rendering. Its sibling `deadlineChanged` keeps a real actor and stays `beacon`.
- **`staleReminder` ⇒ `system`.** It has **no producer at all** — the enum value appears only in
  `attention_models.dart` and `attention_policy.dart`, never in `attention_intent_case.dart` — which is also why
  its `recipientPredicate` is still `unverified`. An event nobody produces has no actor; `system` is the value
  that will be correct when a producer is written, and a `beacon` value would have to be revisited then anyway.
- **Both `beaconHierarchyStatusChanged` variants ⇒ `beacon`, diverging from the scout's `system`.** The scout's
  argument was that the copy comes from `BeaconHierarchyNoticeCopy.*`, i.e. system-worded. But
  `headlineTreatment` governs the **card header** (§6.1: "title … rendered per `headlineTreatment`"), not the
  mini-card event line. These rows are `scope: beacon`, `groupKey: beaconId`, and `placement: timeline_only` —
  they live *inside* a request card whose header is the quoted request title, and the producer does pass a real
  `actorUserId` (`attention_intent_case.dart:838, 848`). Rendering that card's header as a bare system label
  would be wrong; the system-ness is in the body copy, which this field does not control. Recorded as a
  deliberate divergence in case the card work (U04+) shows otherwise.
- `trustGivenChanged` stays `beacon` despite `accessPolicy: profile` — it groups under the request and §6.1 keeps
  the quoted request title. `roomMessagePosted` likewise: a human actor on the mini-card, request identity in the
  header.

**`selfAuthored` is `false` on all 33, and that is a finding, not a default.** The overseer asked for a named
producer call site per `true`; there is none, and the honest answer is that **no current event type is
self-authored**. `BeaconNotificationRecipientResolver.resolveRecipients`'s inner `add()` returns early on
`userId == actor` (`beacon_notification_recipient_resolver.dart:32–34`), so the actor is structurally excluded
from recipients on every resolver-routed event.

The one apparent exception is the scout's `reviewAllPackagesIn` · `reason:authorOfBeacon`, and it was checked
rather than accepted. `AttentionIntentCase.fromBeaconNotification` does special-case it to a single recipient
equal to `notification.actorUserId` (`attention_intent_case.dart:918–928`), and `reviewAllPackagesIn` sets
`actorUserId: authorUserId` (`:343–360`). So recipient == "actor" *as a field value*. But the author **performed
no act**: the producer is `EvaluationCase`'s `!wasCloseableBefore && isCloseableNow` edge
(`evaluation_case.dart:1595–1611`) — the system observing that every package is in. `actorUserId` there is an
addressing carrier that reuses the author slot, not an authorship claim. Per the field's governing semantics
(analysis doc §9 / P3: "an event whose actor is the viewer produces a confirmation, not a row"), marking it
`true` would suppress a row the author actually needs. Hence `false`, with the reasoning recorded here so nobody
re-derives the scout's conclusion from the call site alone.

The field is therefore **forward-looking**: its `true` consumers are the synthetic tombstone / confirmation rows
of §8 and the analysis doc's confirmation table, which are not `AttentionEventType`s and do not appear in this
contract.

**`coalescible: false` on `relayReceived` · `reason:forwardRecipient` only**, asserted by rule and not merely
present as data. Note-less forwards still collapse into «ещё N переслали», but that happens in the UI by
filtering on an empty `notePreview` — it is not this variant flipping to `true`.

### Not touched, deliberately

`_requiresAction` / `attention_policy.dart` obligation outcomes; the U02 characterization tests;
`updates_event_coverage_test.dart` (producer inventory unchanged); the five `unverified` `recoverableVia` values
(U19 gate) — those five variants got the three new fields like everyone else, since the fields are independent of
the recoverability question.

**Inner STATUS:** complete.

---

## UNIT U03b — Card contract fields · VERIFY (2026-09-19)

**Verifier:** read-only; `7b3771de6..HEAD` (`11e0a5a2e`, `4634dc85b`, `0b6b86897`). No code edits.

### Deliberate divergences from scout brief — judged

1. **`selfAuthored` all `false` (not `true` on `reviewAllPackagesIn`).** **Accept inner reasoning.** The firing
   edge is `EvaluationCase.submitReviewPackage` when `!wasCloseableBefore && isCloseableNow`
   (`evaluation_case.dart:1594–1610`); the acting user in that transaction is the **reviewer** (`userId` at
   `:1540`), not the beacon author. `reviewAllPackagesIn` sets `actorUserId: authorUserId` only to route the
   informational copy to the author (`attention_intent_case.dart:343–360`, special recipient at `:921–928`). That
   is addressing, not “the viewer caused this.” `selfAuthored: true` would mean P3-style suppression/confirmation
   semantics — wrong for a row the author must see. Scout conflated recipient slot with causal actor.

2. **`beaconHierarchyStatusChanged` → `headlineTreatment: beacon` (not `system`).** **Accept inner reading of
   §6.1.** The field governs the **card header title** (quoted request title + attribution), not the mini-card
   event line. Both hierarchy variants are `scope: beacon`, `groupKey: beaconId`, `placement: timeline_only`, and
   the producer supplies `actorUserId` when known (`attention_intent_case.dart:838–849`). System wording lives in
   `BeaconHierarchyNoticeCopy` body/title for the event row, not the header identity slot.

### Guard failure — independently proven (no test env override)

`_contractFile()` only checks fixed relative paths; **no** `UPDATES_EVENT_CONTRACT` override. Method: backup
tracked JSON → temporarily replace with `/tmp` mutants → run
`dart test test/architecture/updates_event_contract_test.dart` → restore backup (`diff -q` clean).

| Mutation | Failure |
|---|---|
| Delete `coalescible` on `relayReceived` variant | `containsAll` — `has no match for 'coalescible'` / *missing card contract fields* |
| `headlineTreatment: invalid_enum` on same variant | `headlineTreatment must be one of {beacon, user, system}` |
| `coalescible: true` on `relayReceived` / `forwardRecipient` | *carries a personal note; coalescing it destroys information (spec §7.3 K6)* |

K6 is keyed on `_nonCoalescibleVariants` tuple `('relayReceived', 'reason:forwardRecipient')` — not merely key presence.

### `headlineTreatment` vs `scope`/`groupKey` (33 variants)

| Rule | Count | Event types |
|---|---|---|
| `scope: account` → `user` | 2 | `mutualConnectionFormed`, `inviteAccepted` |
| Actor-less / system copy → `system` | 2 | `staleReminder`, `deadlineReminder` |
| `scope: beacon`, `groupKey: beaconId` → `beacon` | 29 | all others (incl. both `beaconHierarchyStatusChanged` variants) |

**Deviations from scout’s “actor-less system ⇒ system” shortcut:** only the two hierarchy variants (they have
optional real `actorUserId` and §6.1 header semantics — inner choice documented above). Automated script over
live JSON: **0** internal inconsistencies (account/user, K6, schema 4).

### TEST_OUTPUT (re-run by verifier)

```
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --exclude-tags pg test/architecture
→ 00:00 +20: All tests passed! exit 0

cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env test/architecture
→ 00:01 +16: All tests passed! exit 0
```

### Scope / hygiene

- `attention_policy.dart` / `_requiresAction`: **no diff** in `7b3771de6..HEAD`.
- U02 characterization paths: **no diff** in commits.
- Five `unverified` recoverability fields: **unchanged** (same paths as U03 journal).
- `updates_event_coverage_test.dart`: **untouched**.
- Commits: **3** focused (guard+schema → contract fill → journal).
- Pre-existing worktree dirt (`.serena`, constellation journal, `force_directed_graphview` ×2, secrets) **not**
  in U03b commits; secrets remain untracked.

**VERIFY STATUS:** pass

---

### Manager verdict — U03b · **ACCEPTED** (scout ✓ / inner Opus-low ✓ / verify pass, no finisher)

Overseer's own checks: server `test/architecture` **20 passed**, client `test/architecture` **16 passed**.
Contract audited mechanically, not by eye: `schemaVersion 4`, 29 types / **33 variants**, zero variants missing
any of the three new fields, `coalescible: false` on exactly `relayReceived`, `selfAuthored` empty, three legal
`headlineTreatment` values.

**The guard is real, and that was proven three ways.** The scout warned that today's contract tests validate a
*subset*, so adding allow-list keys would never go red. The verifier then proved failure capability on a
throwaway copy of the contract (restored immediately): a missing `coalescible` trips `containsAll`, an invalid
`headlineTreatment` trips the enum check, and `coalescible: true` on a note-bearing forward trips the specific
K6 assertion. Without that step this unit could have shipped an enforcement layer that cannot fail.

**Two judgment calls, both resolved against the scout and in favour of the inner layer:**
1. `selfAuthored` is `false` on all 33. The scout proposed `true` for the `reviewAllPackagesIn` author variant;
   the inner layer read the call site and refused — the recipient equals `actorUserId`, but the author performed
   no act (the producer fires on `!wasCloseableBefore && isCloseableNow`), so `actorUserId` is routing, not
   authorship, and a `true` would suppress a row the author needs. The verifier confirmed at
   `evaluation_case.dart:1594–1610`. The field is forward-looking for the §8 tombstone rows, which are not event
   types — an honest empty set beats a plausible-looking `true`.
2. `beaconHierarchyStatusChanged` is `beacon`, not `system`: `headlineTreatment` governs the card *header*, and
   those rows are `scope: beacon` / `groupKey: beaconId` with a real actor. The system-ness lives in body copy,
   which this field does not control.

**Finding worth keeping:** `staleReminder` has **no producer at all** — the enum value never appears in
`attention_intent_case.dart`. That is why its recipient predicate was `unverified` in U03. It is a dead branch,
and U19 should either wire it or retire it rather than leave a classified event nothing can emit.

Commits: `11e0a5a2e` guard · `4634dc85b` data · `0b6b86897` journal.

---

## UNIT U07a — Obligation transition audit · COMPLETE (2026-09-19)

**WHAT.** Read-only audit at `UNIT_BASE` `d7a220a86`. Deliverable:
[`request-centric-attention-obligation-transition-matrix.md`](request-centric-attention-obligation-transition-matrix.md)
— two obligation variants, settlement chains with `file:line`, gaps, unemittable types, extra settle paths.

**FINDINGS (carry to U07b).**
- Confirmed U03 gap: `HelpOfferCase.withdraw` (`help_offer_case.dart:262–330`) does not call
  `settleAuthorHelpOfferSubmitted`; accept/decline do (`coordination_case.dart:356–360`, `422–426`).
- Contract symbols `withdrawHelpOffer` / `submitReviewPackage` map to `withdraw` and `evaluationFinalize`.
- `reviewOpened` also settles via window close, reopen supersede, and backfill — not in contract
  `resolutionTransitions`.
- Generic `attentionSettle` still settles help-offer obligations (not review); client Done for non-review groups.
- `staleReminder` and coordination-item event types remain without live producers (`coordination_item/` absent).

**TESTS.** n/a — investigation only; no production or test edits.

**STATUS:** complete

---

### Manager verdict — U07a · **ACCEPTED** (investigation, read-only Composer, no sandwich)

Deliverable: `request-centric-attention-obligation-transition-matrix.md` (134 lines, commit `cfd3968fb`).

**Scoping fact that shrinks U07b:** the contract declares only **two** obligation variants — `helpOfferSubmitted`
for the author and `reviewOpened` for reviewers. U07b is therefore a narrow unit, not the sprawling lifecycle
sweep the plan's prose implied.

Seven gaps, ranked. The audit found six beyond the one it was given, which is the whole point of running it:

| # | Gap | Note |
|---|---|---|
| P0 | `HelpOfferCase.withdraw` leaves the author's `helpOfferSubmitted` live | the known one, confirmed |
| P1 | generic `attentionSettle` / My Desk **Done** still resolves help-offer obligations | contradicts owner decision C |
| P1 | terminal paths (`offerRemoved`, beacon close) never settle the author obligation | **new**; not even declared in the contract |
| P2 | `reviewOpened` is settled by window close, reopen-supersede and backfill — **none of which the contract lists** | found by comparing code→contract as well as contract→code |
| P2 | `settleReviewerObligationOnPackageSend` runs **outside** the attention transaction | **verified personally**: `evaluation_case.dart:1616`, after the transaction block closes, with a comment about retry idempotency — the author knew |
| P3 | no optional explanation emitted after a review obligation settles as `expired` | this is the D-plan's "never silently decrement" rule, still unimplemented |
| P3 | contract transition names (`withdrawHelpOffer`, `submitReviewPackage`) do not match live method names | cosmetic but it breaks grep-based tracing |

Also confirmed: review obligations are blocked from user settlement at three layers (use case, SQL, client), not
one — so owner decision C's review exemption is already enforced in depth. `staleReminder` and the
coordination-item types remain unemittable.

**Consequence for U07b:** its brief must carry the P2 transaction-boundary defect explicitly, because D04 requires
the source mutation and the settlement to commit together, and today's code deliberately does not.

---

## UNIT U04 — Additive schema · SCOUT BRIEF (2026-09-19)

**Scout:** read-only on `feature/events_refac` at `UNIT_BASE` `9b0dddf04` (`HEAD` matches). No production code, no
tests, no commits beyond this journal entry.

### Migration registry (verified live)

| Fact | Live source |
|---|---|
| **Next id** | **`m0178`** — registry ends at `m0177` (`_migrations.dart:186–187`, `_allMigrations` … `m0177,` at `:369`). |
| **Registration ritual** | 1) Add `part 'm0178.dart';` with the other `part` lines. 2) Create `m0178.dart` with `part of '_migrations.dart';` and `final m0178 = Migration('0178', [ … ]);`. 3) Append `m0178,` after `m0177` in `_allMigrations`. Version string is **four digits** (`'0178'`), matching neighbours (`m0177.dart` uses `'0177'`). |
| **Apply entrypoint** | `migrateDbSchema(connection)` → `_upgradeLocked` → migrant `Database.upgrade` with advisory lock `tentura_schema_upgrade` (`_migrations.dart:415–416`, `:375–376`). |
| **Partial apply (tests)** | `migrateDbSchemaThrough(connection, '0177')` then `migrateDbSchemaThrough(connection, '0178')` once `m0178` exists (`:425–443`). |
| **“Table mappings”** | Manifest lists them, but **`notification_outbox` and all attention topology tables are not in `@DriftDatabase`** (`tentura_db.dart:92–150` — no outbox/occurrence tables). Attention persistence is **raw SQL** in repositories. **No server `build_runner` step** for this unit — only `_migrations.dart` + new part file. **Hasura** does not track `attention_occurrence` today; new §0.1 tables are server-internal until a later API unit exposes them. |
| **Generated files** | Untouched (`*.g.dart` etc.). |

Optional split: one migration file can hold multiple SQL strings (see `m0118`); a separate **`m0179`** only if review wants trigger isolation — not required by live convention.

### §0.1 objects vs live schema

#### Already exists (do not duplicate)

| §0.1 concept | Live equivalent | Notes |
|---|---|---|
| Occurrence topology | **`m0121`** | `attention_occurrence`, `attention_occurrence_recipient` **PK `(occurrence_id, account_id)`**, `notification_outbox.occurrence_id` **nullable** `text` FK → `attention_occurrence`, index `notification_outbox__occurrence` **partial** `WHERE occurrence_id IS NOT NULL`. **`attention_channel_delivery` UNIQUE `(occurrence_id, account_id)`**. This is **not** receipt identity on `notification_outbox` — do not re-create m0121 tables. |
| Obligation vs optional axis | **`m0118`** | `requires_action boolean NOT NULL DEFAULT false`; live obligation = **`requires_action AND settlement_kind IS NULL`** (partial indexes `notification_outbox__live_obligation*`). |
| Settlement axis | **`m0118` + `m0166`** | `settlement_kind`, `settled_at`, `settled_by_user_id`, `settled_by_occurrence_id`; **`notification_outbox__settlement_obligation_chk`**: `settlement_kind IS NULL OR requires_action`; **`notification_outbox__settlement_facts_chk`**: settlement columns all-null or all-set together. Kinds include `'expired'` after m0166. |
| Thread-scoped obligation key (legacy) | **`attention_thread_key`** | Required when `requires_action` (`notification_outbox__thread_key_chk`). **Not** the same column as frozen **`logical_task_key`** — add new columns; do not rename thread key in U04. |
| Dedup / mutable receipt path | **`m0120` + dispatch** | Unique **`notification_outbox__dedup`** on `(dedup_key) WHERE seen_at IS NULL`. Dispatch **`ON CONFLICT (dedup_key) WHERE seen_at IS NULL DO UPDATE SET … occurrence_id = EXCLUDED.occurrence_id, created_at = now()`** (`attention_dispatch_repository.dart:125–147`). **U05** replaces this for identity; U04 must not change dispatch. |

#### Missing (U04 adds)

**`notification_outbox` columns** (match neighbours: `text` ids, `timestamptz` timestamps, nullable unless noted):

| Column | Type / nullability | Neighbour pattern |
|---|---|---|
| `cleared_at` | `timestamptz` NULL, no default | Like `seen_at` / `settled_at` (`m0115` / `m0118`) |
| `clear_reason` | `text` NULL | Like `settlement_kind` + CHECK enum |
| `cleared_by_operation_id` | `text` NULL, FK → `attention_clear_operation(id)` after table exists | Like optional FK columns |
| `logical_task_key` | `text` NULL | Like `attention_thread_key` |
| `lifecycle_generation` | **`integer` NULL** (no default on existing rows) | Prefer nullable until U05 writes generations; obligation-only CHECK below |

**New tables** (§0.1 names exact):

1. **`attention_request_state`** — columns per manifest: `account_id`, `beacon_id`, `first_entry_at`, `outcome_generation`, `decision_revision`. **PK `(account_id, beacon_id)`** (infer from “per-viewer Request state”; FK `account_id` → `"user"`, `beacon_id` → `beacon`, **`ON DELETE CASCADE`** on account side to mirror outbox). Types: `first_entry_at timestamptz NOT NULL`; **`outcome_generation` / `decision_revision` `integer NOT NULL`** with **no backfill in U04** — table starts empty; first writer is later units.

2. **`attention_clear_operation`** — `id text PRIMARY KEY` (client operation id, no default), `account_id text NOT NULL` → `"user"`, `surface text NOT NULL`, `status text NOT NULL`, `captured_at timestamptz NOT NULL DEFAULT now()`, `undo_deadline timestamptz`, **`applied` / `skipped` / `failed` `integer NOT NULL DEFAULT 0`**, CHECK on `surface` / `status` if manifest enums are fixed (else minimal `text` + document in migration COMMENT).

3. **`attention_clear_operation_member`** — `operation_id` → `attention_clear_operation`, `receipt_id` → `notification_outbox`, `beacon_id`, `outcome_generation integer NOT NULL`, `state text NOT NULL`; **UNIQUE `(operation_id, receipt_id)`** for membership idempotency (plan §4.1 “operation membership uniqueness”).

**Order inside migration:** create `attention_clear_operation` before adding `cleared_by_operation_id` FK on outbox.

#### UNIQUE `(occurrence_id, account_id)` on receipts (dangerous)

- **Not present today** on `notification_outbox` (only nullable `occurrence_id` + non-unique index).
- **Legacy rows:** pre-dispatch receipts may have **`occurrence_id IS NULL`** — a **full** UNIQUE on `(occurrence_id, account_id)` would treat NULLs as distinct in PostgreSQL (multiple NULLs allowed) but is the wrong contract for “post-cutover receipts”.
- **Required shape for additive land:** **`CREATE UNIQUE INDEX notification_outbox__occurrence_account ON public.notification_outbox (occurrence_id, account_id) WHERE occurrence_id IS NOT NULL`** (partial unique). Aligns with manifest U05 note and avoids rejecting NULL legacy rows.
- **Dispatch interaction (pre-U05):** in-place upsert **updates** `occurrence_id` on one row — compatible with partial unique (one row per pair). **Risk:** if production already has **two rows** with the same non-null `(occurrence_id, account_id)` (bad data or test artifacts), **index creation fails**. Preflight: `SELECT occurrence_id, account_id, count(*) FROM notification_outbox WHERE occurrence_id IS NOT NULL GROUP BY 1,2 HAVING count(*) > 1` — should be empty; otherwise migration is **blocked** until data repair.
- **U05** stops dedup-key rewrite from governing identity; U04 only installs the constraint so later code can rely on it.

### CHECK constraints and partial indexes (SQL vocabulary)

**Optional vs obligation in SQL today:**

| Concept | Expression |
|---|---|
| **Optional receipt** | `requires_action = false` |
| **Obligation receipt** | `requires_action = true` |
| **Live obligation** | `requires_action = true AND settlement_kind IS NULL` |
| **Settled obligation** | `requires_action = true AND settlement_kind IS NOT NULL` (with settlement facts CHECK) |

**Clear metadata (new)** — mirror `notification_outbox__settlement_facts_chk` / optional-only settlement:

- **`notification_outbox__clear_optional_only_chk`:** `(requires_action = false) OR (cleared_at IS NULL AND clear_reason IS NULL AND cleared_by_operation_id IS NULL)`.
- **`notification_outbox__clear_facts_chk`:** all clear fields NULL **OR** (`NOT requires_action AND cleared_at IS NOT NULL AND clear_reason IS NOT NULL`) — allow **`cleared_by_operation_id` NULL** for `legacy_seen` (U18 backfill).
- **`notification_outbox__clear_reason_chk`:** `clear_reason IS NULL OR clear_reason IN ('explicit','request_open','sweep','legacy_seen')`.

**Settlement metadata (existing — do not weaken):** `notification_outbox__settlement_obligation_chk` already enforces settlement only on obligations.

**Logical task columns (new CHECKs, additive):**

- When `NOT requires_action`: `logical_task_key IS NULL AND lifecycle_generation IS NULL`.
- When `requires_action`: allow NULL `logical_task_key` / `lifecycle_generation` on all **existing** rows until U05 populates (do not copy `attention_thread_key` NOT NULL requirement onto `logical_task_key` in U04).

**Partial UNIQUE — one live obligation per logical task:**

```sql
CREATE UNIQUE INDEX notification_outbox__live_logical_task
  ON public.notification_outbox (account_id, logical_task_key)
  WHERE requires_action AND settlement_kind IS NULL AND logical_task_key IS NOT NULL;
```

**Partial indexes — `(account_id, beacon_id)`** (manifest U04 steps; not all exist today):

- Active optional: `WHERE NOT requires_action AND cleared_at IS NULL` (and optionally `beacon_id IS NOT NULL`).
- Live obligation: `WHERE requires_action AND settlement_kind IS NULL AND beacon_id IS NOT NULL` (complements m0118 time-ordered indexes).

### Realtime trigger (`notify_notification_outbox_update`)

- **Live definition:** `m0164.dart` replaces the function; compares a fixed **`ROW(...)`** tuple of outbox columns and emits `emit_realtime_entity_change('notification', account_id, 'update', …)` on change.
- **Already in tuple:** settlement columns (`settlement_kind`, `settled_at`, `settled_by_user_id`, `settled_by_occurrence_id`) — this is why `settlement_notify_pg_test.dart` passes.
- **Still omitted from tuple (pre-U04 gap):** `requires_action`, `attention_thread_key`, `occurrence_id` — changing only those **does not** emit realtime today. U04 manifest asks only for **new** clear/identity columns; implementer should **`CREATE OR REPLACE FUNCTION`** adding at minimum: **`cleared_at`, `clear_reason`, `cleared_by_operation_id`, `logical_task_key`, `lifecycle_generation`** to both OLD and NEW sides of the `ROW(...)` compare (same pattern as m0164 lines 19–75).
- **If forgotten:** writes to clear state or logical-task columns succeed in DB but **no `entity_changes` notification** → clients keep stale Activity/My Desk indicators until reconnect or explicit refetch (same failure mode as pre-m0164 settlement blindness; covered by `settlement_notify_pg_test.dart` pattern — add parallel test for clear columns in U04).
- **Trigger attachment:** unchanged since `m0116` — `notification_outbox_update_notify` AFTER UPDATE, transition tables `old_rows` / `new_rows`.

### U18 backfill / cutover interaction (U04 must enable restart)

- U18 sets **`cleared_at`** from **`seen_at`** for legacy **optional** rows with reason **`legacy_seen`** (manifest §0.1, U18 steps).
- U04 must leave **`cleared_at` / `clear_reason` NULL** on all rows at migration end (no data migration in U04).
- Backfill predicate will be restartable if it only updates rows matching  
  `requires_action = false AND seen_at IS NOT NULL AND cleared_at IS NULL` (and sets `clear_reason = 'legacy_seen'`, leaves `cleared_by_operation_id` NULL) — compatible with CHECK above.
- **`seen_at` meaning unchanged** (read axis); do not default `cleared_at` from `seen_at` in U04.

### U06a retention note (do not fix in U04)

`deleteSettledOlderThan` still deletes old **seen + emailed** rows without live obligations (`notification_outbox_repository.dart:121–131`); **`cleared_at` is not referenced** (journal U06a: uncleared optional exemption waits for U04 column, but **repository change is out of scope** for this storage-only unit). Schema add alone does not change retention behaviour.

### Behaviour boundary (UNTOUCHABLE for implementer)

No reads/writes in `attention_repository.dart`, `attention_dispatch_repository.dart`, GraphQL, or Hasura. Storage + constraints + trigger only.

---

STATUS: complete

BRIEF: **Acceptance:** After `m0178`, a fresh disposable DB and a DB upgraded from `0177→0178` both have §0.1 columns/tables, CHECK/partial indexes, partial UNIQUE on `(occurrence_id, account_id)` where `occurrence_id IS NOT NULL`, partial UNIQUE on live `(account_id, logical_task_key)`, and an updated `notify_notification_outbox_update` that treats clear/logical-task column changes like settlement changes — with **zero** change to application SQL paths until later units. **Approach:** Single additive migration `m0178` (+ registry), optional dedicated PG test file mirroring `settlement_kind_constraint_pg_test.dart` / `settlement_notify_pg_test.dart`; preflight duplicate `(occurrence_id, account_id)` before creating partial unique index.

STEPS:

| # | Step | Files | Red meaningful? |
|---|---|---|---|
| 1 | Add `m0178.dart`: create `attention_clear_operation`, `attention_clear_operation_member`, `attention_request_state`; add outbox columns + CHECKs + partial indexes + partial uniques; extend notify function | `packages/server/lib/data/database/migration/m0178.dart`, `_migrations.dart` | no (schema-only until tests) |
| 2 | PG tests: fresh `migrateDbSchema`; upgrade path `0177`→`0178`; constraint rejects clear metadata on obligations / settlement on optionals (existing); accepts optional clear shape; notify on `cleared_at` update; optional duplicate-key preflight helper | `packages/server/test/data/database/*_pg_test.dart` (new or extend) | **yes** — add failing assertions before migration lands, or test file in same commit as migration |
| 3 | Journal inner with **real** `./scripts/run_with_test_cleanup.sh` output | this journal | n/a |

TEST_CMD:

```bash
# Fresh database — full chain including m0178 (after step 1)
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --tags pg -j 1 test/data/database/settlement_kind_constraint_pg_test.dart

cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --tags pg -j 1 test/data/database/settlement_notify_pg_test.dart

# After adding U04-specific file (e.g. attention_additive_schema_pg_test.dart):
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --tags pg -j 1 test/data/database/<u04_migration_test>.dart

# Upgrade path from current production-shaped tip (0177 → 0178) — pattern from settlement_kind_constraint_pg_test.dart:50-62:
# migrateDbSchemaThrough(writer, '0177'); migrateDbSchemaThrough(writer, '0178');

# Regression smoke (uses migrateDbSchema on disposable DB — must stay green):
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --tags pg -j 1 test/data/repository/attention_repository_pg_test.dart
```

(Wrapper script verified at `scripts/run_with_test_cleanup.sh`. PG tests skip when admin Postgres unreachable — treat skip as **blocked**, per manifest §1.)

UNTOUCHABLE: `key.fb`, `leo.key`, `out.key`, `dart-defines`, `.serena/project.yml`, `packages/force_directed_graphview/**`, `docs/plans/constellation-*`, generated `*.g.dart` / client `_g/`; **`packages/server/lib/data/repository/attention_repository.dart`**, **`attention_dispatch_repository.dart`**, **`notification_outbox_repository.dart`** (behaviour unchanged in U04); secrets; unrelated worktree dirt.

RISKS:

| Hazard | Detail |
|---|---|
| **Partial UNIQUE `(occurrence_id, account_id)`** | Index build scans live rows; **fails** if duplicates exist; **must be partial** `WHERE occurrence_id IS NOT NULL` so NULL legacy rows and current dedup upsert path remain valid until U05. |
| **Partial UNIQUE `(account_id, logical_task_key)`** | If multiple **live** obligations already share the same key with `logical_task_key` NULL, index is harmless; once U05 writes keys, duplicates become impossible — pre-U05 duplicates with non-null keys would block index creation. |
| **CHECK vs legacy data** | All existing rows have clear columns NULL → safe. Obligations with settlement remain valid. Optional rows with `seen_at` set stay **uncleared** until U18 — intentional. |
| **Locking** | Standard `ALTER TABLE` / `CREATE INDEX` (not `CONCURRENTLY`) — brief write lock per statement; acceptable for dev/staging pattern used in other migrations; large prod deploy should follow existing migration ops practice. |
| **Restart** | Migrant records version `0178` once all statements in the migration succeed; re-run is idempotent at version level. Avoid non-idempotent DDL inside one version. |
| **Trigger incomplete** | Missing new columns in `ROW(...)` → silent realtime staleness on clear/logical-task updates. |
| **Manifest vs live “table mappings”** | No Drift mapping to update; do not invent Hasura metadata in U04. |
| **Retention** | Without repository change, old seen optionals still deleted — not a migration failure but product gap until a later unit extends `deleteSettledOlderThan` (journal U06a follow-up). |

---

## UNIT U04 — Additive schema · INNER (2026-09-19)

**Inner:** Claude Code Opus 5 on `feature/events_refac`, `UNIT_BASE` `9b0dddf04`. Followed the scout brief's STEPS
and TEST_CMD plus the five overseer additions. No repository, read path or write path touched:
`attention_repository.dart`, `attention_dispatch_repository.dart` and `notification_outbox_repository.dart` are
byte-identical to `UNIT_BASE`.

### Commits

| Hash | Subject |
|---|---|
| `4a321f0b6` | `schema(attention): additive m0178 for clear state and obligation identity` |
| `bfa45cf70` | `test(attention): prove the m0178 constraints reject offending writes` |

### What landed

`packages/server/lib/data/database/migration/m0178.dart` (new) + registry lines in `_migrations.dart`
(`part 'm0178.dart';`, `m0178,` after `m0177`). No Drift mapping, no `build_runner`, no Hasura metadata — the
scout's finding that these tables live outside `@DriftDatabase` held.

- **Columns** on `notification_outbox`: `cleared_at timestamptz`, `clear_reason text`,
  `cleared_by_operation_id text`, `logical_task_key text`, `lifecycle_generation integer` — all nullable, no
  defaults, NULL on every existing row at migration end. `seen_at` untouched.
- **CHECKs**: `notification_outbox__clear_optional_only_chk`, `…__clear_facts_chk`, `…__clear_reason_chk`,
  `…__logical_task_chk`; FK `…__cleared_by_operation_fkey` → `attention_clear_operation(id) ON DELETE SET NULL`.
- **Partial UNIQUE**: `notification_outbox__occurrence_account` (`WHERE occurrence_id IS NOT NULL`) and
  `notification_outbox__live_logical_task`.
- **Partial indexes**: `…__active_optional_beacon`, `…__live_obligation_beacon`, `…__cleared_by_operation`,
  plus `attention_clear_operation__account`, `attention_clear_operation_member__receipt`.
- **Tables**: `attention_clear_operation`, `attention_clear_operation_member`, `attention_request_state` — all
  created empty, all with `COMMENT ON TABLE`.
- **Trigger**: `CREATE OR REPLACE FUNCTION public.notify_notification_outbox_update()` re-issued from m0164 with
  the five new columns added to both sides of the `ROW(...)` compare.

### Overseer additions — how each was satisfied

1. **Preflight.** Statement 1 of the migration is a `DO` block that aggregates duplicate non-null
   `(occurrence_id, account_id)` pairs and, if any exist, `RAISE EXCEPTION … USING ERRCODE = 'unique_violation'`
   with the offending pairs interpolated into the message. Proven by *"m0178 preflight aborts by naming duplicate
   occurrence/account pairs"*, which seeds two receipts on one occurrence at `0177`, asserts the thrown
   `ServerException.message` contains `m0178 preflight failed`, `occurrence_id=OCu04dup` and `account_id=Uu04`,
   and then asserts `schema_version` is still `0177` — the failed version does not record.
2. **Restartable.** Every statement carries `IF NOT EXISTS`; `ALTER TABLE … ADD CONSTRAINT` has no such form in
   PostgreSQL 17, so the four CHECKs and the FK are added inside a `DO` block guarded by `pg_constraint` lookups.
   Verified two ways. (a) *Structural:* `migrant_db_postgresql` 0.3.0 applies **all** statements of one migration
   inside a single `runTx`, so an interruption rolls the whole version back — there is no half-applied state to
   re-enter. (b) *Empirical:* the test *"re-applying every m0178 statement is a no-op"* pulls `m0178.statements`
   out of `migrationsForTesting` and executes the entire list **twice** against the already-upgraded database,
   then asserts no statement raised and that each new constraint appears exactly once and all five columns still
   exist. Since migrant would never re-run a recorded version, replaying the statements is the only honest way to
   exercise this.
3. **Plain `CREATE INDEX`.** No `CONCURRENTLY` anywhere; the reasoning (single transaction per migration, single
   release, no live users) is in the migration's doc comment so a future reader does not "fix" it.
4. **Constraints proven to reject, by name.** `_expectConstraintViolation` asserts on
   `ServerException.constraintName`, not on `information_schema`. Covered: clear metadata on an obligation →
   `clear_optional_only_chk`; `cleared_at` with no reason and reason with no `cleared_at` →
   `clear_facts_chk`; `clear_reason = 'because'` → `clear_reason_chk`; `logical_task_key` on an optional receipt
   and `lifecycle_generation = -1` → `logical_task_chk`; a second receipt on one `(occurrence_id, account_id)` →
   `notification_outbox__occurrence_account`; a second live obligation on one logical task →
   `notification_outbox__live_logical_task`; duplicate sweep membership → `attention_clear_operation_member_pkey`;
   negative sweep counter → `attention_clear_operation__counters_chk`; duplicate Request state and a negative
   generation → `attention_request_state_pkey` / `attention_request_state__generations_chk`.
5. **Both paths.** Group *"m0178 on a fresh database"* runs the full chain via `migrateDbSchema`. Group
   *"m0178 upgrade path from 0177"* seeds production-shaped rows **at `0177`** — a legacy receipt with
   `occurrence_id IS NULL` **and** `seen_at` set, a receipt carrying an occurrence, a live obligation and a
   settled obligation — then `migrateDbSchemaThrough(writer, '0178')` and asserts all four rows survive with every
   new column NULL.
6. **U18 compatibility.** `clear_facts_chk` permits `cleared_by_operation_id IS NULL` on a cleared optional
   receipt; the test runs the actual U18 predicate
   (`NOT requires_action AND seen_at IS NOT NULL AND cleared_at IS NULL` → `clear_reason = 'legacy_seen'`) on both
   the fresh and the upgraded database and it is accepted.
7. **Trigger.** *"emits a realtime update when clear state changes"* clears a receipt and asserts exactly the
   `{'event':'update','entity':'notification','id':'Uu04','user_ids':['Uu04']}` payload arrives on
   `LISTEN entity_changes`, then repeats for a `logical_task_key` + `lifecycle_generation` update.
8. **No behaviour change.** `git diff 9b0dddf04..HEAD --stat` touches only the migration, the registry, the new
   test file and one line of an existing test.

### Test evidence

**RED** — same test file, with `m0178,` commented out of `_allMigrations` (registry restored immediately after):

```
$ cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
    dart test --tags pg -j 1 test/data/database/attention_additive_schema_pg_test.dart
00:05 +1 -22: Some tests failed.
```

22 failures, 1 pass. The single pass is *"still allows many receipts with no occurrence"*, which is true before
the migration too — kept as the NULL-tolerance guard for the partial unique.

**GREEN** — registry restored:

```
$ cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
    dart test --tags pg -j 1 test/data/database/attention_additive_schema_pg_test.dart
00:06 +25: All tests passed!
```

**Regression** (scout's TEST_CMD trio):

```
$ cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
    dart test --tags pg -j 1 test/data/database/settlement_kind_constraint_pg_test.dart \
    test/data/database/settlement_notify_pg_test.dart \
    test/data/repository/attention_repository_pg_test.dart
00:08 +21: All tests passed!
```

No suite skipped: Postgres 17.9 reachable at `127.0.0.1:5432` (container `postgres`).

### Findings

- **Constraint ordering forced a design correction.** The first draft of `clear_facts_chk` carried
  `NOT requires_action` in its satisfied branch, duplicating the optional-only rule. Clearing an obligation then
  tripped `clear_facts_chk` instead of `clear_optional_only_chk` — both reject, but the error names the wrong
  rule, which is exactly the diagnostic confusion the constraints exist to prevent. Split so each constraint owns
  one responsibility: `clear_optional_only_chk` decides *whether* a receipt may be cleared,
  `clear_facts_chk` only the internal coherence of the clear fields. Caught by the test asserting on
  `constraintName`; a test asserting only "throws" would have shipped it.
- **An additive FK broke an existing test.** `attention_clear_operation_member.receipt_id` references
  `notification_outbox`, so the ad-hoc `TRUNCATE public.attention_channel_delivery, public.notification_outbox, …`
  at `attention_repository_pg_test.dart:810` started failing with `0A000 cannot truncate a table referenced in a
  foreign key constraint`. Fixed by adding `CASCADE`, matching that file's own `setUp` block at `:112`. This is
  the only edit to pre-existing code in the unit. All other attention PG suites already use `CASCADE`.
- **`surface` and `status` on `attention_clear_operation` are plain `text`, deliberately.** The manifest freezes
  `clear_reason`'s vocabulary but not these two; inventing an enum here would bind a later unit to names this
  unit made up. Documented in `COMMENT ON TABLE`. The counters, which *are* knowable, carry a CHECK.
- **`attention_clear_operation_member.beacon_id` has no FK** (unlike `attention_request_state.beacon_id`, which
  cascades from `beacon` per the `m0019` convention): membership is an audit snapshot of what a sweep touched and
  must survive the deletion of the Request it referred to.
- **Pre-U04 trigger gap left alone.** The scout noted `requires_action`, `attention_thread_key` and
  `occurrence_id` are *still* absent from the change-detection tuple, so changing only those emits nothing. That
  predates U04 and the manifest asks only for the new columns; widening the tuple is a behaviour change and
  belongs with U05, which is the unit that starts writing those columns. **Carried forward.**
- **Retention unchanged, as scoped.** `deleteSettledOlderThan` still ignores `cleared_at`; the column now exists
  for the later unit that fixes it.

**Full server PG sweep:**

```
$ cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 45m -- \
    dart test --tags pg -j 1
11:31 +807 ~24: All tests passed!
```

The 24 skips are **not** unreachable-Postgres skips. All 24 come from the three suites carrying the
unconditional constant `_skipHistoricalMigrationCoverage` — *"Disabled for the planned schema squash cutover;
this only covers upgrades from retired schemas"* (`realtime_notification_migration_test.dart:22`,
`beacon_cover_migration_test.dart:13`, `m0149_resolution_removal_migration_test.dart:13`). They are skipped at
`UNIT_BASE` for the same reason and are unrelated to `m0178`.

`git diff 9b0dddf04..HEAD --stat`: `_migrations.dart` (+2), `m0178.dart` (+388),
`attention_additive_schema_pg_test.dart` (+708), `attention_repository_pg_test.dart` (1 line).

### Remaining

None for U04. Carried forward to their own units, not left undone here:

- **U05** widens the change-detection tuple to `requires_action` / `attention_thread_key` / `occurrence_id`
  (a pre-existing gap, and a behaviour change) and stops the `ON CONFLICT (dedup_key)` rewrite from governing
  receipt identity; it is also the first writer of `logical_task_key` / `lifecycle_generation`.
- **U18** runs the `legacy_seen` backfill the CHECKs were shaped to admit.
- A later unit freezes the `surface` / `status` vocabularies on `attention_clear_operation` and extends
  `deleteSettledOlderThan` to respect `cleared_at`.

---

## UNIT U04 — Additive schema · VERIFY (2026-09-19)

**Verify:** read-only on `feature/events_refac`, range `9b0dddf04..HEAD` (`f46648709` journal · `bfa45cf70` tests ·
`4a321f0b6` schema). Re-ran scout TEST_CMD; independently checked migrant source and git scope.

### Inner claims — confirmed or refuted

1. **`clear_facts_chk` / `clear_optional_only_chk` split** — **Confirmed.** Live DDL (`m0178.dart:145–175`) matches:
   `clear_optional_only_chk` owns `requires_action OR all clear fields NULL`; `clear_facts_chk` only
   `(all NULL) OR (cleared_at AND clear_reason NOT NULL)` with optional `cleared_by_operation_id`. Re-ran
   `attention_additive_schema_pg_test.dart`: obligation clear → `notification_outbox__clear_optional_only_chk`;
   optional `cleared_at` without reason → `clear_facts_chk`; optional reason without timestamp →
   `clear_facts_chk`; bad enum → `clear_reason_chk`; partial uniques → index names
   `notification_outbox__occurrence_account`, `notification_outbox__live_logical_task`; table CHECKs/PKs as
   listed in inner journal. **Not exercised in suite:** invalid `cleared_by_operation_id` FK (would raise FK
   name, not a CHECK).
2. **Restartability** — **Confirmed (framework + replay).** `migrant_db_postgresql` 0.3.0 `_apply` wraps
   `INSERT schema_version` + every statement in one `_db.runTx` (`…/migrant_db_postgresql.dart:43–64`); failure
   rolls back version row and DDL together. Test *"re-applying every m0178 statement is a no-op"* executed all
   `m0178.statements` twice after full migrate; **+25 suite green**.
3. **Trigger** — **Confirmed by runtime, not DDL review.** Upgrade-path test `LISTEN entity_changes`, `UPDATE`
   `cleared_at`/`clear_reason` on `Nu04modern` → payload
   `{event: update, entity: notification, id: Uu04, user_ids: [Uu04]}`; second update on
   `logical_task_key`/`lifecycle_generation` → one update notification. (Settlement-only path still covered by
   `settlement_notify_pg_test.dart`.)
4. **`attention_repository_pg_test.dart:810` CASCADE** — **Confirmed necessary and minimal.** Only change in range:
   append ` CASCADE` to existing multi-table `TRUNCATE` (FK from `attention_clear_operation_member.receipt_id` →
   `notification_outbox`). No other pre-existing file in `9b0dddf04..HEAD`.

### Scope / process

- **Repositories:** `git diff 9b0dddf04..HEAD` empty for `attention_repository.dart`,
  `attention_dispatch_repository.dart`, `notification_outbox_repository.dart`.
- **Commits:** three focused (`4a321f0b6`, `bfa45cf70`, `f46648709`); no loosened/deleted tests in diff.
- **Worktree:** pre-existing dirt on `.serena/project.yml`, `force_directed_graphview/**` — **not** introduced by
  U04 commits; secrets still untracked.

### TEST_CMD re-run (verify agent, 2026-09-19)

| Command | Result |
|---|---|
| `settlement_kind_constraint_pg_test.dart` | **+2**, 0 skip |
| `settlement_notify_pg_test.dart` | **+2**, 0 skip |
| `attention_additive_schema_pg_test.dart` | **+25**, 0 skip |
| `attention_repository_pg_test.dart` | **+17**, 0 skip |

Postgres reachable at `127.0.0.1:5432`; no unreachable-Postgres skips in this set. (Full-server **~24 skips** from
`_skipHistoricalMigrationCoverage` in three historical migration suites — pre-existing at `UNIT_BASE`, commit
`5fb343ec5`; not run as part of scout TEST_CMD.)

**Migration paths in U04 suite:** fresh DB via `setUpDisposablePgWriter` (full chain); `0177 → 0178` with
`Nu04legacy` (`occurrence_id NULL`, `seen_at` set) + modern occurrence row + obligations — tests *preserves…*,
*backfills U18 shape*, *emits realtime…*. **Preflight:** duplicate pairs abort, message names pairs, `schema_version`
stays `0177`.

**U18 shape:** test *accepts the U18 legacy_seen shape with no operation id* — executed UPDATE, not DDL-only.

STATUS: pass

TEST_OUTPUT: see table above — **+46** total across four scout commands, **0 skips**, all passed.

ACCEPTANCE:

| Criterion | Verdict | Evidence |
|---|---|---|
| §0.1 storage additive, no row rewrite at migrate | met | Upgrade test: four seeded rows, all new columns NULL after `0178` |
| CHECK/partial UNIQUE reject with blameable names | met | 25 PG tests assert `ServerException.constraintName` (FK on bad operation id not covered) |
| Restart / idempotent replay | met | migrant `runTx`; double replay test green |
| Trigger propagates clear/logical-task changes | met | LISTEN test on upgrade path |
| Fresh + `0177→0178` paths | met | Two test groups + preflight |
| `legacy_seen` without operation id | met | Fresh + upgrade backfill tests |
| No repository behaviour change | met | git diff empty on three repos |
| Preflight abort with useful message | met | `m0178 preflight failed` + pair detail; version `0177` |
| TEST_CMD green, no PG blocker skips | met | Re-run counts above |
| Untouchables / focused commits | met | Diff scope; worktree pre-existing only |

GAPS: none blocking acceptance — optional follow-up: add one PG test that invalid `cleared_by_operation_id` raises
`notification_outbox__cleared_by_operation_fkey` (diagnostic completeness only).

---

### Manager verdict — U04 · **ACCEPTED** (hard; scout ✓ / inner Opus-low ✓ / verify pass, no finisher)

Overseer's own run: 5 PG suites → **48 passed, 0 skipped**. Migration `m0178.dart`, 388 lines, commits
`4a321f0b6` schema · `bfa45cf70` constraint-rejection tests · `f46648709` journal.

**The unit's most valuable output was a caught mistake, not the schema.** The inner layer's first
`clear_facts_chk` repeated `NOT requires_action`, so clearing an obligation tripped *that* constraint instead of
`clear_optional_only_chk`. Both rejected the write, so a `throwsA(isA<ServerException>())` test would have shipped
it — and a maintainer debugging a production rejection would have been sent to the wrong rule. Only the
name-asserting test caught it. This is the concrete payoff of requiring constraints to prove *which* rule
rejects, not merely that something did.

Independently confirmed by the verifier, each by execution rather than by reading:
- every m0178 CHECK and partial UNIQUE raises the name a maintainer would expect;
- the trigger fires on clear-column updates (observed `entity_changes` payload, not DDL inspection);
- the duplicate preflight aborts with `m0178 preflight failed` **and leaves `schema_version` at 0177**, so the
  migration is not recorded and re-runs cleanly after the data is fixed;
- `legacy_seen` with a NULL operation id is accepted, so U18's backfill can run;
- both paths tested: fresh database, and `0177→0178` over a legacy row with `occurrence_id IS NULL`;
- the three repository files are untouched — no behaviour change.

**Judgment I endorse:** no CHECK on `attention_clear_operation.surface`/`status`. The manifest freezes
`clear_reason` and not those, so inventing an enum now would bind U08/U09 to names the inner layer made up. It
documented the omission in `COMMENT ON TABLE` instead of guessing.

**One pre-existing file edited, justified:** ` CASCADE` appended to the `TRUNCATE` at
`attention_repository_pg_test.dart:810`, forced by the new FK and matching that file's own `setUp`.

**Skip discipline held.** The ~24 skips visible on a full PG sweep come from the pre-existing
`_skipHistoricalMigrationCoverage` constant (commit `5fb343ec5`, schema-squash cutover) — verified by the
overseer, not accepted on report. No suite skipped for an unreachable Postgres.

**Carried into U08:** the verifier's one optional gap — no test proves the `cleared_by_operation_id` FK rejects.
U08 is the first unit to write that column and must prove it there, so the "every constraint proves it rejects"
rule keeps no exceptions.

---

## UNIT U05 — Immutable dispatch identity · SCOUT BRIEF (2026-09-19)

**UNIT_BASE:** `d17d52ca3`. **Mode:** read-only scout; no production edits.

### Problem confirmation (live code)

`AttentionDispatchRepository.record` (`attention_dispatch_repository.dart:22–213`) does three durable writes per
successful new `source_event_key`:

1. **`attention_occurrence`** — `ON CONFLICT (source_event_key) DO NOTHING` then equality check on
   `{source_event_key, event_type, actor_user_id, immutable_payload}`; mismatch → `StateError`; match → **return
   without writing receipts** (replay is occurrence-grain, not receipt-grain).
2. **`attention_occurrence_recipient`** — always **INSERT** (PK `(occurrence_id, account_id)`); one row per
   occurrence×recipient; stores `collapse_key` (not copied to `notification_outbox`).
3. **`notification_outbox`** — `INSERT … ON CONFLICT (dedup_key) WHERE seen_at IS NULL DO UPDATE SET …` (lines
   125–148).

The conflict branch **rewrites** (does not touch `id`, `account_id`, `dedup_key`, `seen_at`, `read_at`,
`emailed_at`, or settlement columns):

| Column updated on conflict | Consumer / why it matters |
|---|---|
| `category`, `kind`, `priority` | Feed classification, preference gates, channel routing |
| `title`, `body`, `action_url` | In-app copy, push/email payload (via frozen `attention_channel_delivery.payload`) |
| `beacon_id`, `coordination_item_id`, `actor_user_id` | Scoping, mark-seen-for-beacon, GraphQL fields |
| `source_event_key`, `occurrence_id` | Receipt identity, FK to occurrence topology, U18 backfill anchors |
| `destination_kind`, `target_entity_id` | Navigation / destination map |
| `presentation_key`, `presentation_payload` | Card rendering (immutable-after-insert target) |
| `in_app_preference_class`, `suppression_class`, `access_policy` | Noisy vs standard, visibility |
| **`requires_action`** | Obligation vs optional axis — **can flip class on one stable `id`** |
| `attention_thread_key` | Legacy obligation thread identity (distinct from `logical_task_key`) |
| **`created_at = now()`** | Feed ordering, forward/`requestActivity` `MAX(created_at)` projections (`attention_repository.dart:302–341`, `:426–433`) |
| **`collapsed_count += 1`** | GraphQL `collapsedCount`; client “N more” when `>= 3` (`updates_feed_pane.dart`, `activity_stream_view.dart`) |

**Not updated:** settlement fields, clear columns (m0178), `logical_task_key` / `lifecycle_generation` (never written yet).

### `dedup_key` composition and readers

**Computed** in dispatch only:

```text
dedup_key = '${recipientId}|attention-v1|${collapseKey}'
collapseKey = recipient.collapseKey ?? intent.collapseKey
```

**`collapseKey` producers** — `AttentionIntentCase` + per-recipient overrides (`attention_intent_case.dart`):

- `AttentionCollapseKey.none(sourceEventKey)` → `v1|none|<encoded sourceEventKey>` (default; deadlines, relays at intent level use family keys on intent).
- `AttentionCollapseKey.family(name, subjects)` → `v1|<family>|<subjects…>` (e.g. `coordination_changed|beaconId`, `request_status|beaconId` for watcher-only status recipients, trust families).
- Intent-level examples: `coordinationChanged` → family `coordination_changed|[beaconId]`; `requestStatusChanged` intent uses `none(sourceEventKey)` but **watcher-only** recipients override to `family('request_status', [beaconId])` (`:714–716`).
- Tests/harness: `relay|beaconId` (`attention_repository_pg_test.dart:1118`).

**Readers of `dedup_key`:**

| Location | Use |
|---|---|
| `m0120` partial UNIQUE `(dedup_key) WHERE seen_at IS NULL` | **Blocks** a second unseen row with the same key — **in tension with immutable per-occurrence receipts** |
| `attention_dispatch_repository.dart` | Upsert target |
| `attention_repository.dart:1141–1147` | `markUnseen` refuses to resurrect a seen receipt if an **unseen sibling shares `dedup_key`** |
| `notification_outbox_repository.markEmailedByDedupKey` | After immediate email, marks **all** unseen rows with that key emailed (`email_notification_service.dart:111`) |
| `attention_channel_delivery` payload | `AttentionChannelDecision.dedupKey` copied into JSON (`_decisionPayload`) → push handoff + email |
| PG tests | Retention harness selects receipt by computed dedup (`attention_retention_pg_test.dart:127–133`) |

**`collapsed_count` on the outbox row** is a **write-time** artifact of the upsert. Activity forward ordering often uses **SQL `MAX(created_at)` across related receipts** (`attention_repository.dart:302–341`), which mimics collapse **without** requiring `collapsed_count` — the U02-tagged test `status event merges into forward and bumps created_at` is **projection**-driven (manual inserts, distinct `dedup-$id`), slated for **U10**, not U05.

### Channel delivery vs in-app collapse (m0121)

Topology (`m0121.dart`):

- `attention_occurrence` ← 1:1 `source_event_key`
- `attention_occurrence_recipient` ← audience snapshot + **`collapse_key`**
- `notification_outbox` ← receipt; **`dedup_key` is collapse-derived today**
- `attention_channel_delivery` ← **`UNIQUE (occurrence_id, account_id)`**, status machine, **`payload` json** (includes `dedupKey`, title/body, `receiptId`)

**On dedup-key upsert today:** the **same `receipt_id`** is kept; `occurrence_id` on the outbox row moves to the **latest** occurrence; channel path still **INSERTs a new delivery row** per new occurrence (`attention_dispatch_repository.dart:195–205`). So push/email already get **one job per occurrence**, while in-app shows **one row**. `claimDue` throttles to **one lease per account** (`attention_channel_delivery_repository.dart:41–44`; PG test `claimDue with two pending jobs…` expects **2 pending** jobs, **1 leased** — `attention_repository_pg_test.dart:1064–1094`).

**Channel aggregation today:** worker reads **frozen `payload`** (not live outbox join); `collapsed_count` on outbox is **not** read by the delivery worker. Email/push use **payload copy** + `dedupKey` for post-send outbox marking.

**Smallest split (D03-aligned):**

1. **In-app:** always **INSERT** a new outbox row per `(occurrence_id, account_id)`; satisfy m0178 `notification_outbox__occurrence_account`; stop using `ON CONFLICT (dedup_key) …` for identity.
2. **`dedup_key` on outbox:** must become **receipt-unique** (e.g. include `occurrence_id` or receipt `id`) **or** drop/replace `notification_outbox__dedup_seen` — otherwise the second unseen event in the same collapse family **violates UNIQUE** before immutable identity is achieved.
3. **Channel:** keep collapsing on **`collapse_key`** (already on `attention_occurrence_recipient`; optionally denormalize to delivery table). Replace “upsert outbox” semantics with **dedupe at delivery insert** — e.g. skip or `ON CONFLICT` update **pending** job keyed by `(account_id, channel_collapse_key)` while still attaching the **latest** payload for handoff. Preserves: one in-flight send per account (`claimDue`), fewer duplicate pushes for the same family, **without** rewriting receipt rows.
4. **Email `markEmailedByDedupKey`:** after (2), must key off **channel collapse key** (or mark by `receipt_id`), not receipt-unique `dedup_key`, or immediate-email dedupe regresses.

### `source_event_key` replay (must keep working)

Handled **before** outbox write (`attention_dispatch_repository.dart:25–66`). Replayed key with identical facts → **no new occurrence, no recipient row, no receipt, no delivery**. U05 must **not** move replay dedup onto `dedup_key` upsert. Regression test: double `record` same intent → still one occurrence, one receipt.

### Obligation identity: `logical_task_key` + `lifecycle_generation` (D03, §0.1)

**Not written anywhere yet** (m0178 columns NULL; CHECK allows NULL on obligations until U05).

| Concern | Where it should live |
|---|---|
| **Compute stable `logical_task_key`** (excludes generation) | New helper alongside `AttentionPolicy._threadKey` (`attention_policy.dart:316–331`) — D03: *event family + beaconId + subjectId + recipientId*; must **include beacon** (thread key today can omit beacon when subject is `coordinationItemId`). |
| **Assign `lifecycle_generation` on insert** | Dispatch writer when `requires_action` (default `1` for first live gen). |
| **One live row per `(account_id, logical_task_key)`** | m0178 `notification_outbox__live_logical_task` partial UNIQUE; writer must **settle/supersede predecessor** (`settlement_kind`, `settled_at`) in the **same transaction** before inserting new gen — D03 “semantic renewal supersedes transactionally”. |
| **Bump generation** | Re-offer / new review window / source reconciliation (U07b, U18) — not on channel **retry** (`retryOrDeadLetter` only mutates `attention_channel_delivery`). |

**`attention_thread_key`:** keep legacy meaning; do not rename to `logical_task_key` (U04 journal).

### Tests pinning current collapse (intentional rewrites for overseer)

**Not in U02 `CHANGES IN Uxx` list** — call out for pre-approval:

| File | Test | Current assertion | After U05 |
|---|---|---|---|
| `attention_repository_pg_test.dart` | `delivery jobs are durable and duplicate recording collapses` | 1 outbox row, `collapsed_count` max 2 after two relays same collapse | **2 receipts**, stable `created_at` each; channel behavior per delivery dedupe policy |
| `attention_repository_pg_test.dart` | `claimDue with two pending jobs for one account…` | 2 delivery rows for dup-a/dup-b same collapse | May become **1 pending** if channel dedupes by collapse key — **assert handoff count, not occurrence count** |
| `realtime_notification_migration_test.dart` | `seen-only collapse SQL and partial unique index remain exact` | Documents raw SQL upsert + `collapsed_count` 2/3 | **Rewrite or relocate** to legacy migration fixture; production path must not use that upsert |
| `attention_repository_pg_test.dart` | `markUnseen skips… shares dedup_key` | Sibling dedup semantics | Still valid if manual duplicate `dedup_key` possible; **invalid** if dedup unique per receipt — adjust to collapse-key or drop |

**U02 doomed tests:** none tagged U05. `status event merges…` / `activityOffers orders by effectiveActivityAt` remain **U10**.

**Manifest tests:** new **dispatch identity PG** file (concurrency + replay); keep `attention_dispatch_telemetry_test.dart` green (unit, no PG).

### m0178 interaction / transition data states

| Index / preflight | Pre-U05 live shape | When immutable INSERT lands |
|---|---|---|
| Preflight duplicate `(occurrence_id, account_id)` | **Empty** (collapse kept one row per pair) | Stays valid |
| `notification_outbox__occurrence_account` | One row per pair | **Enforced** on each new receipt |
| `notification_outbox__live_logical_task` | Harmless while `logical_task_key` NULL | **Violations** if U05 writes keys without superseding prior live obligation |
| `notification_outbox__dedup_seen` | One unseen row per collapse `dedup_key` | **Violations** if multiple unseen receipts share collapse unless `dedup_key` changes or index dropped |

**Reachable mid-rollout (server-only deploy before U18):** mixed receipts — legacy collapsed rows (possibly stale `occurrence_id`) plus new immutable rows; duplicate optional events visible in feed where one row existed before; obligations with NULL `logical_task_key` alongside new keyed rows until backfill/U07b. **U18** expects restartable backfill with fixed boundary — do not rely on rewriting old rows in U05.

### Proposed commit-sized STEPS

| # | Step | Files (primary) | Red test meaningful? |
|---|---|---|---|
| 1 | **Failing identity contract** — replay once; two source keys same collapse → two receipt ids, two `occurrence_id`s, `created_at` unchanged on re-read; concurrent duplicate `source_event_key` → one occurrence | `test/.../attention_dispatch_identity_pg_test.dart` (new) | **Yes** — asserts new behavior |
| 2 | **Receipt-unique `dedup_key` + plain INSERT** — remove `ON CONFLICT` upsert; `collapsed_count` default 1 | `attention_dispatch_repository.dart`; optional `m0179` drop/replace `notification_outbox__dedup_seen` | **Yes** — step 1 goes green |
| 3 | **Channel collapse dedupe** — pending delivery coalesced on `(account_id, collapse_key)`; payload refreshed; `receiptId` points at latest receipt or handoff uses latest copy | `attention_dispatch_repository.dart`, `attention_channel_delivery_repository.dart` and/or migration | **Yes** — adjust `claimDue` PG test expectations |
| 4 | **`logical_task_key` + `lifecycle_generation` write** on `requires_action` | `attention_policy.dart` (new key helper), `attention_dispatch_repository.dart` | **Yes** — insert obligation rows; assert columns set |
| 5 | **Supersede predecessor** in same transaction when renewal would violate `notification_outbox__live_logical_task` | dispatch + existing settlement port (minimal hook; full transitions U07b) | **Yes** — two help-offer gens → one live |
| 6 | **Email mark path** — mark emailed by channel collapse key | `email_notification_service.dart`, `notification_outbox_repository.dart` | **Yes** — two receipts one collapse, one email mark |

Do **not** change `_requiresAction` outcomes.

### TEST_CMD (verify suites exist)

**Dispatch / collapse / attention PG (U02 baseline + additive schema):**

```bash
cd /home/vader/MY_SRC/tentura/packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --tags pg -j 1 \
  test/data/repository/attention_repository_pg_test.dart \
  test/data/repository/attention_activity_stream_pg_test.dart \
  test/data/repository/attention_surface_pg_test.dart \
  test/data/repository/attention_mark_seen_for_beacon_pg_test.dart \
  test/data/repository/attention_live_obligations_pg_test.dart \
  test/data/repository/attention_retention_pg_test.dart \
  test/data/repository/my_work_attention_pg_test.dart \
  test/data/database/attention_additive_schema_pg_test.dart
```

**Unit (telemetry):**

```bash
cd /home/vader/MY_SRC/tentura/packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- \
  dart test test/data/repository/attention_dispatch_telemetry_test.dart
```

**Migration collapse fixture (rewrite candidate):**

```bash
cd /home/vader/MY_SRC/tentura/packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --tags pg -j 1 test/data/database/realtime_notification_migration_test.dart
```

**Attention regression (client, unchanged by U05 unless projections consume new receipt multiplicity):**

```bash
cd /home/vader/MY_SRC/tentura/packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 45m -- \
  flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env \
  test/domain/attention test/features/inbox test/features/my_work test/features/home
```

### UNTOUCHABLE

`key.fb`, `leo.key`, `out.key`, `dart-defines`, `.serena/project.yml`, `packages/force_directed_graphview/**`,
`docs/plans/constellation-*`, generated files, U02 tests except the **explicit U05 rewrite list above**,
`_requiresAction` classification in `attention_policy.dart`.

### RISKS

| Hazard | Detail |
|---|---|
| **`notification_outbox__dedup_seen` vs immutable rows** | Second unseen insert with same collapse **fails** unless `dedup_key` or index changes — plan step 2 before enabling multi-receipt feeds. |
| **Partial UNIQUE `(occurrence_id, account_id)`** | Safe if one INSERT per pair; **unsafe** if conflict upsert retained. |
| **`notification_outbox__live_logical_task`** | Inserting keyed obligations without supersede → **unique_violation**; partial deploy with NULL keys still OK. |
| **Push/email duplicate or stale** | Wrong channel dedupe → double push or payload pointing at superseded `receiptId`. |
| **Email mark by wrong key** | Receipt-unique `dedup_key` breaks collapse-aware `markEmailedByDedupKey`. |
| **Feed cardinality** | Optional events no longer collapse in outbox → more rows until U10 projection grouping; indicators may jump until read models adapt. |
| **U18 backfill** | Legacy rows may have **wrong `occurrence_id`** on collapsed receipts; backfill must not assume outbox↔occurrence join for pre-cutover rows. |
| **Rolling deploy** | Old writers collapse / new writers insert → duplicate or conflicting semantics; coordinate single server version or feature flag (not in manifest). |
| **Realtime trigger** | m0178 already watches `logical_task_key` / `lifecycle_generation`; U04 carried gap on `requires_action` / `occurrence_id` — widening tuple is optional separate commit. |

**STATUS:** complete

**BRIEF:** After U05, each new `(occurrence_id, account_id)` yields a **new immutable receipt** (`created_at`, presentation, `requires_action`, `source_event_key` never rewritten by later events). Replaying the same `source_event_key` still creates **zero** additional receipts. Channel push/email keep **collapse-family** aggregation via `collapse_key` / delivery dedupe, not outbox upsert. Live obligations use **`logical_task_key` + `lifecycle_generation`** with at most one unsettled row per key; semantic renewal supersedes in-transaction; delivery retry does not bump generation.

**STEPS:** See table above (6 commits: identity PG tests → dedup/INSERT → channel dedupe → logical task columns → supersede → email mark).

**TEST_CMD:** See commands above (`attention_repository_pg_test.dart` + six sibling PG suites + `attention_additive_schema_pg_test.dart` + `attention_dispatch_telemetry_test.dart` + optional `realtime_notification_migration_test.dart` + client attention regression).

**UNTOUCHABLE:** Listed above.

**RISKS:** Listed above (`dedup` index, live logical task UNIQUE, channel/email, U18 legacy occurrence linkage, deploy ordering).

---

## UNIT U05a — Receipt identity · INNER (2026-09-19)

**UNIT_BASE:** `8e3d82577`. **Scope:** scout steps 1 and 2 plus the index change they require.
Steps 3–6 (channel dedupe, email retargeting, logical task key, supersede-on-renewal) untouched — U05b/U05c.

### What changed

1. **`m0179`** — `notification_outbox__dedup` loses its uniqueness. m0120 created it as
   `notification_outbox__dedup_seen`, UNIQUE on `(dedup_key) WHERE seen_at IS NULL`, then renamed it; that
   uniqueness *was* the old collapse contract and a plain INSERT could not land while it stood. The index is
   recreated with the same columns and predicate — only `indisunique` goes — because `dedup_key` keeps its
   collapse-derived value and its two readers (`markEmailedByDedupKey`, `markUnseen`'s unseen-sibling check)
   still want collapse-family semantics. Moving those onto a channel key is U05b. The migration comment says at
   length why the uniqueness is not coming back.
2. **`AttentionDispatchRepository.record`** — the `ON CONFLICT (dedup_key) WHERE seen_at IS NULL DO UPDATE`
   branch is gone. The statement is a plain INSERT, so `created_at`, `presentation_*`, `source_event_key`,
   `occurrence_id`, `requires_action` and the rest are fixed at insert, and `collapsed_count` stays at its
   schema default of 1 instead of being a write-time counter.

Nothing in the channel or email path was touched. `_requiresAction` classification, `logical_task_key` and
`lifecycle_generation` were not touched.

### Where replay dedup lives now (overseer addition 3)

It never lived on the index that changed, and it still does not:

- **Occurrence grain.** `attention_occurrence.source_event_key` is UNIQUE. `record` inserts
  `ON CONFLICT (source_event_key) DO NOTHING`, and on a replay it checks the four idempotency facts and returns
  *before* any recipient or receipt row is written. A replay therefore never reaches the outbox statement.
- **Receipt grain.** m0178's UNIQUE `notification_outbox__occurrence_account` on
  `(occurrence_id, account_id)`. Before U05a it was merely satisfied by collapse; it is now the only thing
  standing between a producer bug and a duplicate receipt, and it raises rather than silently overwriting.

Both are asserted by writes in the new suites rather than left implicit. The concurrent replay case passes
because the losing transaction blocks on the `source_event_key` index until the winner commits, then takes the
`DO NOTHING` path.

### Characterization tests rewritten (overseer addition 4)

Two, both pre-approved in the scout brief. No other test's expectations were changed.

| File · test | Asserted before | Asserts now | Why intended |
|---|---|---|---|
| `attention_repository_pg_test.dart` · *delivery jobs are durable and duplicate recording collapses* → *…and a second occurrence adds a receipt* | Two relays sharing collapse key `relay\|<beaconId>` leave **1** outbox row with `max(collapsed_count) = 2` | **2** receipts, **2** distinct `occurrence_id`, **1** shared `dedup_key`, `max(collapsed_count) = 1` | Receipt-grain collapse is exactly what U05a removes. The old numbers pinned the rewrite-in-place behaviour; the new ones pin immutable identity. Delivery-job assertions in the same test are unchanged and still pass. |
| `realtime_notification_migration_test.dart` · *seen-only collapse SQL and partial unique index remain exact* → *the legacy collapse upsert no longer has an arbiter to collapse onto* | The retired `enqueue()` upsert yields `collapsed_count` 2, then 3 on a `read_at`-only row, then a second row once `seen_at` is set; sibling assertion: `notification_outbox__dedup` `startsWith('CREATE UNIQUE INDEX')` | The legacy statement raises **42P10** (no matching ON CONFLICT arbiter); three plain inserts leave **3** unseen receipts with `collapsed_count` 1; index is `CREATE INDEX`, not UNIQUE | The SQL it documented is unrunnable after m0179. Asserting the retirement, rather than deleting the test, keeps the legacy upsert from creeping back. The helper `_insertOutboxRow` became a plain INSERT and the upsert moved to `_insertOutboxRowWithLegacyCollapse`, used only by that negative assertion. |

The `markUnseen skips a seen sibling when another unread shares dedup_key` test the scout flagged as a possible
casualty needed **no** change: `dedup_key` keeps collapse semantics, so sibling logic is still meaningful.
`claimDue with two pending jobs for one account` also needed no change — the channel path is untouched, so it
still sees 2 pending jobs and leases 1.

### Feed cardinality (overseer addition 5)

No projection test failed on row count. The only regression-list failure in the whole sweep was the one
characterization test above. The accepted rise in receipts per Request is therefore currently visible only in
that test's numbers; U10 absorbs it.

### Findings

- **The scout's "optional m0179" is not optional.** With the UNIQUE index in place the second unseen receipt in
  a collapse family fails with 23505 — proven directly by the `m0179 upgrade path from 0178` group, which
  migrates to 0178, shows the rejection, applies 0179, and shows the same two writes succeed.
- **`realtime_notification_migration_test.dart` cannot be run at all.** Temporarily disabling
  `_skipHistoricalMigrationCoverage` to verify the rewrite fails in `setUpAll`, before any test body:
  `_rollBackM0135ForTest` runs `DROP FUNCTION block_hides(text,text)`, which `beacon_member` and
  `beacon_admitted_helper` now depend on (2BP01). Pre-existing and unrelated to U05a; the skip constant was
  restored unchanged. That rewrite is verified by reading only.
- **`dart format` would reformat `attention_repository_pg_test.dart` wholesale** (it is not formatter-clean at
  HEAD). The edit was reapplied by hand to keep the diff at 9 insertions / 5 deletions instead of 39/33.

### Commands

```
$ dart test --tags pg -j 1 test/data/repository/attention_dispatch_identity_pg_test.dart   # before step 2
00:02 +2 -2: Some tests failed.
  a second occurrence in the same collapse family adds a receipt instead of rewriting the first  [E] Expected: <2> Actual: <1>
  two concurrent occurrences in one collapse family both land                                     [E] Expected: <2> Actual: <1>

$ dart test --tags pg -j 1 test/data/repository/attention_dispatch_identity_pg_test.dart   # after
00:02 +4: All tests passed!

$ dart test --tags pg -j 1 test/data/database/attention_receipt_identity_index_pg_test.dart
00:03 +6: All tests passed!

$ dart test --tags pg -j 1 <the eight regression suites>   # after the dispatch change, before the rewrites
00:27 +94 -1: Some tests failed.
  attention_repository_pg_test.dart: delivery jobs are durable and duplicate recording collapses

$ dart test --tags pg -j 1 <both new suites + the eight regression suites>   # after the rewrites
00:31 +105: All tests passed!

$ dart test test/data/repository/attention_dispatch_telemetry_test.dart
00:00 +2: All tests passed!

$ dart test --exclude-tags pg
00:08 +1660: All tests passed!
```

Every command ran through `scripts/run_with_test_cleanup.sh` from `packages/server`. No PG suite reported
SKIPPED.

### Commits

| Hash | Subject |
|---|---|
| `23dfd68af` | test(attention): pin immutable receipt identity and replay dedup |
| `2f344973f` | schema(attention): m0179 drops uniqueness from the collapse index |
| `a005bf9b0` | feat(attention): insert in-app receipts instead of rewriting them |
| `ee8c3ad46` | test(attention): retire the two collapse characterizations U05a invalidates |

**STATUS:** complete

---

## UNIT U05a — Receipt identity · VERIFY (2026-09-19)

**UNIT_BASE:** `8e3d82577`. **Range reviewed:** `8e3d82577..99e426e91` (+ worktree audit).

### Replay dedup adjudication (scout vs inner)

**The inner layer is right.** `source_event_key` replay dedup never rested on
`notification_outbox__dedup_seen`. Live path: `attention_occurrence` INSERT with
`ON CONFLICT (source_event_key) DO NOTHING`; empty result → matching-row check →
**return at line 65** before any `notification_outbox` or channel write
(`attention_dispatch_repository.dart:25–66`). The partial UNIQUE on `dedup_key`
only constrained **second unseen rows in the same collapse family** for the
old upsert contract; it did not participate in replay. After U05a, receipt-grain
guard is m0178 `notification_outbox__occurrence_account` (duplicate
`(occurrence_id, account_id)` would error, not merge). **No bypass path found:**
the only production `INSERT INTO public.notification_outbox` is dispatch
(`rg` over `packages/server/lib`).

The scout brief conflated “removing collapse upsert” with “replay safety”; replay
was always occurrence-grain. No P0 replay gap.

### Independent execution (verifier, not inner tests only)

- **Immutability:** throwaway DB script `/tmp/u05a_verify_immutability.dart`
  (disposable PG, not committed) — two dispatches, same `collapseKey`, distinct
  `source_event_key`; snapshot of `created_at`, `requires_action`,
  `occurrence_id`, `source_event_key`, presentation columns for `verify-relay-1`
  **unchanged** after second dispatch; `count(*) = 2`. **Pass.**
- **Replay + concurrency:** `attention_dispatch_identity_pg_test.dart` (4 tests)
  and `attention_receipt_identity_index_pg_test.dart` (6 tests) — all green on
  verifier run.
- **m0179:** upgrade group proves pre-0178 `23505` on `notification_outbox__dedup`,
  post-0179 two unseen rows; occurrence-account UNIQUE still rejects duplicate
  pair; double-apply m0179 no-op. Comment block in `m0179.dart` matches behaviour.
- **Retired characterizations:** `attention_repository_pg_test` collapse test —
  **required** (1→2 rows, `collapsed_count` stays 1). `claimDue` test **unchanged**
  (still 2 delivery jobs — U05b scope preserved). `realtime_notification_migration_test`
  — rewrite **required** (legacy upsert now `42P10`; plain inserts allow 3 rows);
  **not weakened** beyond behaviour change.
- **Realtime suite unrunnable:** `_skipHistoricalMigrationCoverage` lines 22–24
  **byte-identical** to `8e3d82577`. Temp copy with `skip: false` → **2BP01** on
  `_rollBackM0135ForTest` / `DROP FUNCTION block_hides` (views depend). Rewritten
  assertion **not executed in CI** — pre-existing coverage gap.
- **Push/email:** no diff on `beacon_notification_service.dart`,
  `email_notification_service.dart`, `notification_outbox_repository.dart`,
  `attention_repository.dart`, `attention_policy.dart`. `dedup_key` still
  `recipient|attention-v1|collapseKey`; channel INSERT unchanged; `markUnseen`
  sibling + `markEmailedByDedupKey` tests still pass in `attention_repository_pg_test`.
- **Scope:** no `logical_task_key` / `lifecycle_generation` in dispatch. U05a
  commit files only (8 paths). Pre-existing worktree dirt (`.serena`,
  `force_directed_graphview`, secrets) **not** in U05a commits.

### Verifier TEST_CMD (2026-09-19)

```text
server PG suites (incl. new identity + m0179 index tests): 00:32 +105, 0 skipped
server attention_dispatch_telemetry_test.dart: 00:00 +2
client attention regression: 00:17 +407
realtime_notification_migration_test (unskipped temp copy): +0 -1 setUpAll 2BP01
```

**STATUS:** pass

### Manager verdict — U05a · **ACCEPTED** (hard; scout ✓ / inner Opus-low ✓ / verify pass, no finisher)

Overseer's own run: identity + index + 3 regression PG suites → **51 passed, 0 skipped**.
Commits `23dfd68af` red tests · `2f344973f` m0179 · `a005bf9b0` dispatch insert · `ee8c3ad46` retirements ·
`99e426e91` journal.

**The unit's real result is that the inner layer corrected the brief and the verifier adjudicated it.** The scout
warned that dropping the collapse upsert would break `source_event_key` replay dedup because the mechanism looked
index-dependent. The inner layer traced it instead: replay is guarded by `attention_occurrence.source_event_key`
UNIQUE at *occurrence* grain — which returns before any receipt is written — plus m0178's
`notification_outbox__occurrence_account` at *receipt* grain. The verifier followed both paths and confirmed **no
replay path bypasses the occurrence table**. The brief's risk was mis-attributed; had the inner layer believed
it, it would have built a redundant guard around a non-problem.

Verified by execution, not by reading:
- immutability, via the verifier's own script on a disposable database (full column-map equality on the first
  receipt after a second same-collapse-key dispatch);
- replay dedup under concurrency — two simultaneous deliveries of one `source_event_key` insert once;
- m0179: pre-migration schema rejects the second unseen receipt with 23505, post-migration accepts it,
  `occurrence_account` still rejects true duplicates, double-apply is a no-op;
- push/email untouched: `dedup_key` keeps its collapse-derived value, so `markEmailedByDedupKey` and
  `markUnseen`'s sibling check are behaviourally identical. U05b remains a clean, separate unit.

**Both retired characterizations are required, not weakened.** `attention_repository_pg_test` moved from
"one row, `collapsed_count = 2`" to two independent receipts — that *is* the intended behaviour change. The
`claimDue` test needed no edit at all, contradicting the scout's prediction that it would.

**Accepted debt, recorded rather than glossed:** `realtime_notification_migration_test.dart` carries a rewritten
collapse contract that **never executes** — the file is globally skipped because unskipping it fails in
`setUpAll` with 2BP01 (`_rollBackM0135ForTest` drops `block_hides`, which `beacon_member` /
`beacon_admitted_helper` depend on). Pre-existing, verified by both the inner layer and the verifier, skip
constant byte-identical to `8e3d82577`. A rewritten assertion that cannot run is no better than a missing one;
U19 should either repair that fixture or delete the file rather than leave it as decoration.

### Overseer deviation — U05b runs without its own scout

The U05 scout already analysed all six steps in depth, including U05b's two (channel pending-delivery dedupe and
email marking by channel collapse key) with their risks. Commissioning a second scout would re-derive a brief
that is already in this journal. U05b therefore goes straight to the inner layer, and its **verify pass reuses
the same U05 chat**, so the verifier still judges against a brief it wrote itself — which is the property that
matters in the sandwich, not the number of layers.

---

## UNIT U05b — Channel split · INNER (2026-09-19)

**UNIT_BASE:** `f583ac43c`. **Scope:** U05 scout steps 3 and 6. Steps 4–5 (`logical_task_key`,
`lifecycle_generation`, supersede-on-renewal) untouched — U05c.

### What changed

1. **`AttentionDispatchRepository.record`** — the channel write is no longer an unconditional INSERT. A new job
   coalesces into the account's existing **pending** `attention_channel_delivery` row for the same collapse
   family, repointing it at the newest occurrence and receipt and replacing its frozen payload. Only `pending`
   is collapsed into.
2. **`m0180`** — `CREATE INDEX attention_occurrence_recipient__account_collapse (account_id, collapse_key)`.
   Additive, non-unique, `IF NOT EXISTS`, plain `CREATE INDEX`, no data change.
3. **`markEmailedByDedupKey` → `markEmailedByChannelCollapseKey({accountId, channelCollapseKey})`**, through the
   port, the repository, `EmailNotificationService` (both send paths) and `BeaconNotificationService`.

### No new collapse vocabulary, and no new column (overseer addition 3)

The channel collapse key already exists twice over and neither copy was disturbed:

- `attention_occurrence_recipient.collapse_key` (m0121), one row per `(occurrence_id, account_id)` — exactly the
  grain a delivery job has, so the coalesce lookup joins that table instead of denormalising the key onto
  `attention_channel_delivery`. m0180 exists only so that join is an index scan.
- `notification_outbox.dedup_key` — `<accountId>|attention-v1|<collapseKey>`, the same key as persisted. U05a
  deliberately left it carrying its collapse-derived value; the email path now matches it **as stored** rather
  than recomposing it, so there remains exactly one place that builds the string (dispatch).

§0.1 names no channel-collapse object, and nothing here needed one.

The one genuine tightening: the marking predicate gained `AND account_id = $2`. It is per-account by definition
and must not depend on the account id happening to be a prefix of the key.

### Why the payload carries the newest receipt (overseer addition 2)

The coalesced job is repointed at the **newest** receipt of the family — `receipt_id`, `occurrence_id` and the
payload's `receiptId` all move together, so the row cannot disagree with its own payload.

Newest, not first, for three reasons. The notification shows the newest event's copy (the payload is replaced
wholesale), so any other id would open something the user did not just read about. The newest receipt was
written microseconds ago in the same transaction, so it cannot have been cleared, settled or retention-deleted
before the worker picks the job up; an older sibling can have been. And `deleteSettledOlderThan` protects a
receipt only while a `pending`/`leased` delivery references it by `receipt_id` — pointing the FK at the newest
receipt is what keeps the openable one alive. Asserted in
`attention_channel_collapse_pg_test.dart` against a freshly queried newest id, not against whichever row came
back first.

### Why a leased or delivered job is never collapsed into

A `leased` send is already in a worker's hands and a `delivered`/`dead` one has gone. Absorbing a later event
into either would not aggregate a notification, it would delete one. Both cases have their own test.

### Retention interaction (overseer addition 6)

`attention_retention_pg_test.dart` passes unchanged, and the meaning of `emailed_at` did not shift: it still
means "the digest owes nothing for this row". What did shift is which rows one send settles — one email now
settles the whole family, because the family is now one notification. That is the marking following the
delivery, not the other way round.

Secondary effect, deliberate: an older receipt in a collapsed family no longer has a delivery row pointing at
it, so once seen, emailed and past the window it becomes deletable slightly earlier than before. U06a's
guarantee is untouched — a live obligation is held by `NOT (requires_action = true AND settlement_kind IS NULL)`,
which has nothing to do with deliveries; the retention suite's *retains live obligations even when seen,
emailed, and older than the retention window* case still passes.

### Findings

- **The duplicate-notification failure mode the overseer described is real, but it is not U05a's doing.**
  `attention_channel_delivery` has UNIQUE `(occurrence_id, account_id)` and dispatch always inserted one job per
  occurrence×recipient, so two occurrences in one collapse family produced **two** delivery jobs — and two
  pushes — both before and after U05a. The pre-U05a receipt-grain upsert collapsed the in-app row, never the
  delivery. U05b is therefore a *reduction* in push/email volume for a collapse family (2 → 1), not a
  restoration of prior behaviour. It is the behaviour D03 asks for ("channel aggregation may retain its existing
  collapse key; split it from in-app receipt identity") and the one overseer addition 1 specifies, so it is what
  was built — but "push/email behaviour is unchanged end to end" is not literally true and should not be read as
  a verified claim. Nothing else about delivery changed: throttle, lease, retry, dead-letter and the frozen
  payload shape (`dedupKey` stays the payload's JSON key, so in-flight jobs written by the old code still
  decode) are all as they were.
- **`room_now_line_pg_test.dart` was already red at `f583ac43c`** — a U05a casualty its sweep missed, because
  U05a's regression list covers `test/data/repository/` and this suite lives under `test/domain/use_case/`.
  Verified by running the unmodified test in a throwaway `git worktree` at `f583ac43c` (generated files copied
  in, since they are gitignored): same failure, `Expected: <1> Actual: <2>`. Rewritten here rather than left
  red — see below.
- **The email retarget could not be made red by behaviour alone on the family it targets**, because
  `dedup_key` already *was* the channel collapse key; the first red was a compile error. The account-scoping
  tightening gave it a real behavioural red (below), which is why it was added rather than left as a rename.
- `m0143_capability_evidence_sql_test.dart` failed once in a whole-directory PG sweep and passed in isolation
  and on a full re-run of the same directory (`+142 ~22`). Flake, unrelated.
- **Worktree accident, disclosed:** a stray `git stash --keep-index` in one command stashed the three
  pre-existing modified files that belong to other people (`.serena/project.yml`, two
  `force_directed_graphview` files). Noticed immediately and `git stash pop`ed; `git status` matches the
  starting snapshot exactly (3 modified, 10 untracked). Nothing was lost, and no other stash entry was touched.
- `dart format` would reformat `email_notification_service_test.dart` (35/28) and `room_now_line_pg_test.dart`
  wholesale — neither is formatter-clean at HEAD, same trap U05a hit. Edits applied by hand.

### Characterization tests changed

| File · test | Asserted before | Asserts now | Why intended |
|---|---|---|---|
| `attention_repository_pg_test.dart` · *claimDue with two pending jobs for one account* | Two dispatches sharing collapse key `relay\|<beaconId>` leave 2 pending jobs | Two dispatches in **different** collapse families leave 2 pending jobs | The test's subject is the throttle CTE's ON CONFLICT 21000 guard, which needs two pending jobs for one account. Since U05b that state only exists across families. The scout predicted this edit; the assertions are unchanged, only the fixture. |
| `room_now_line_pg_test.dart` · *second identical NOW edit collapses outbox receipts by dedup key* → *…keeps two receipts but one notification* | 2 occurrences → **1** outbox receipt | 2 receipts sharing **1** dedup key → **1** pending delivery | The old number was the receipt-grain collapse U05a retired (already failing at UNIT_BASE). The rewrite pins where the collapsing went instead of deleting the coverage. |

### Commands

All from `packages/server` through `scripts/run_with_test_cleanup.sh`. No PG suite reported SKIPPED.

```
$ dart test --tags pg -j 1 test/data/repository/attention_channel_collapse_pg_test.dart   # before the change
00:02 +4 -1: Some tests failed.
  two receipts in one collapse family leave one pending delivery carrying the newest receipt
    Expected: an object with length of <1>  Actual: [<two pending jobs>]  Which: has length of <2>

$ dart test --tags pg -j 1 test/data/repository/attention_channel_collapse_pg_test.dart   # after
00:02 +5: All tests passed!

$ dart test --tags pg -j 1 test/data/repository/attention_email_marking_pg_test.dart   # before the rename
00:00 +0 -1: Error: The method 'markEmailedByChannelCollapseKey' isn't defined

$ dart test --tags pg -j 1 test/data/repository/attention_email_marking_pg_test.dart   # renamed, not yet account-scoped
00:02 +2 -1: marks every receipt of the sent family and nothing outside it
    Expected: <2>  Actual: <3>   (the foreign account's row was marked too)

$ dart test --tags pg -j 1 test/data/repository/attention_email_marking_pg_test.dart   # after
00:02 +3: All tests passed!

$ dart test --tags pg -j 1 <the 12 attention PG suites incl. both new ones>
00:33 +90: All tests passed!

$ dart test --tags pg -j 1 test/data/repository/
06:51 +567 ~2: All tests passed!

$ dart test --tags pg -j 1 test/domain/
00:48 +76: All tests passed!

$ dart test --tags pg -j 1 test/data/database/
03:39 +142 ~22: All tests passed!      # the ~22 are the pre-existing _skipHistoricalMigrationCoverage skips

$ dart test test/data/repository/attention_dispatch_telemetry_test.dart \
    test/data/service/beacon_notification_service_test.dart \
    test/data/service/email_notification_service_test.dart \
    test/domain/use_case/email_digest_case_test.dart
00:00 +15: All tests passed!

$ dart test --exclude-tags pg
00:07 +1660: All tests passed!

$ ./scripts/check-custom-lints.sh packages/server
total: 0 (baseline: 0) — OK
```

### Commits

| Hash | Subject |
|---|---|
| `cc1622368` | test(attention): pin channel-layer delivery collapse cardinality |
| `cd2d8ed10` | feat(attention): collapse push/email at the delivery layer |
| `200c57d37` | test(attention): pin which rows an immediate email marks |
| `8f9f68d6d` | refactor(attention): mark emailed by the channel collapse key |
| `af0315cf3` | test(attention): retire one more collapse characterization U05a invalidated |

**STATUS:** complete

### Overseer incident — I committed other people's work, and repaired it

**What happened.** My U03b verdict command used `git add -A docs/plans/`. That swept **27 untracked plan
documents belonging to unrelated work** (availability, nested-requests, request-threads, subjective-help-tag,
graph-navigation, several issue-1xx plans, constellation-ui-remediation) and a **pending modification to
`constellation-pin-badge-zoom-lod-implementation-journal.md`** into commit `d7a220a86`. Later verdicts repeated
the same `git add -A`.

**This was mine, not a worker's.** Every worker prompt forbids touching those paths, and every worker obeyed.
The orchestrator broke its own rule.

**Repair, forward-only, no history rewrite.** `git rm --cached` returned the 27 documents to untracked with
their content untouched on disk; the constellation journal's committed content was reverted to its pre-session
state and the owner's in-flight modification was written back into the working tree. Verified after: **37
untracked, 4 modified — identical to the session-open snapshot**, secrets present and unmodified.

**Rule adopted for the rest of this run:** never `git add -A` / `git add <dir>`. Every commit stages explicit
file paths only.

### Adjudication — my own instruction was wrong (U05b addition 1)

I told the inner layer both "push/email behaviour is unchanged end to end" **and** "two receipts sharing a
channel collapse key must produce one delivery". The inner layer found those contradict, and said so instead of
silently picking one: `attention_channel_delivery` carries UNIQUE `(occurrence_id, account_id)` and dispatch
always inserted one job per occurrence×recipient, so a two-occurrence collapse family produced **two** pushes
both before *and* after U05a — U05a's removed upsert collapsed the in-app receipt, never the delivery.

**Adjudicated: the volume reduction is correct and intended.** D03 puts aggregation at the channel layer; one
notification per collapse family is the design. My "unchanged end to end" was a factually wrong description of
the baseline, written to prevent regressions. The record is corrected here rather than left as a contradiction
the next unit inherits.

### Defect in my own review — a failing test I accepted

`room_now_line_pg_test.dart` was **already failing at `f583ac43c`**, i.e. U05a broke it and I accepted U05a
anyway. Cause: every regression list — the scout's, and therefore mine — enumerated suites under
`test/data/repository/`, and this one lives under `test/domain/use_case/`. The inner layer found it, verified it
in a throwaway worktree at `f583ac43c` before touching it, and rewrote it as part of U05b.

**Correction to my verification discipline, effective now:** a unit that changes a write path is verified against
the **whole server suite**, not against a named list of suites. A named list only proves the suites someone
thought of.

---

## UNIT U05b — Channel split · VERIFY (2026-09-19)

**UNIT_BASE:** `f583ac43c`. **Unit range:** `cc1622368`…`af0315cf3` (excludes overseer journal/untrack commits).

### Pre-existing push cardinality (overseer premise)

**Confirmed.** At `f583ac43c`, dispatch used a plain
`INSERT INTO attention_channel_delivery` per occurrence×recipient (no collapse SQL). With
`UNIQUE (occurrence_id, account_id)` on the delivery table, two occurrences in one collapse family produced
**two pending jobs** — verifier reproduced by checking out pre-U05b `attention_dispatch_repository.dart` only
and running `attention_channel_collapse_pg_test.dart`: **Expected length 1, Actual 2**. U05a did not change that
path. The 2→1 reduction is **new intended behaviour** (D03 channel aggregation), not preservation of prior
end-to-end push volume.

### Independent audit runs

| Check | Result |
|---|---|
| Red test before `cd2d8ed10` | Channel collapse PG test fails with pre-U05b dispatch (2 jobs) — **right reason** |
| `room_now_line` at UNIT_BASE assertion | Old test on **current** code: `Expected: 1 Actual: 2` outbox receipts — **U05a casualty**, not U05b regression |
| U05b PG suites at HEAD | `attention_channel_collapse_pg_test.dart` + `attention_email_marking_pg_test.dart` → **+8**, 0 skipped |
| Retention | `attention_retention_pg_test.dart` → **+2**, live-obligation case still passes |
| `ON CONFLICT` on outbox in dispatch | **Absent** (comment only) |
| `logical_task_key` / `lifecycle_generation` in U05b diff | **None** in production paths |

### Payload / receipt survival

While a job is `pending` or `leased`, `deleteSettledOlderThan` excludes rows referenced by
`attention_channel_delivery.receipt_id` (FK `ON DELETE RESTRICT` on the delivery row). Coalesce repoints the
job to the **newest** receipt before the worker runs; the newest row was just inserted and cannot yet be
retention-eligible (`seen_at` still null). **No verifier-constructed state** where the worker's `receiptId` is
missing at handoff time under normal dispatch. **Residual (documented, not new):** non-atomic coalesce can
briefly leave two pending jobs for one family; `claimDue` throttle bounds user-visible duplicate push — same
class as pre-U05b concurrency.

### Email retarget

`markEmailedByChannelCollapseKey(accountId, channelCollapseKey)` executed in PG:
marks both receipts of family A, not family B / other recipient / foreign-account row with same dedup string
(`attention_email_marking_pg_test.dart`). `dedup_key` on outbox remains collapse-derived
(`recipient|attention-v1|collapseKey`).

### Stash incident

`git stash list` unchanged in structure (top entry still `wip-visibility-before-attention-convergence`, not
the three-file incident). No stash reflog entry for a transient `keep-index` pop (expected if immediately
popped). Worktree still shows **pre-existing** `.serena/project.yml` and `force_directed_graphview/**`
modified; secrets remain untracked — **no evidence of loss** from the disclosed incident.

**STATUS:** pass

---

## UNIT U05c — Obligation identity · VERIFY (2026-09-19)

**UNIT_BASE:** `567eaee6b`. **Unit range:** `a1df38392`…`783458ef8` (excludes journal).

### Verifier runs

| Command | Result |
|---|---|
| `dart test --tags pg -j 1 test/data/repository/attention_obligation_identity_pg_test.dart` | **+10**, 0 skipped |
| `dart test --exclude-tags pg` | **+1660** |
| `dart test --tags pg -j 1` (sequential, after failed 5s artifact run) | **+835 ~24**, 0 skipped |
| U05b smoke: channel collapse + `beacon_hierarchy_child_independence_pg_test` | **+7** |
| `logicalTaskKey` missing subject (`/tmp/u05c_throw_test.dart`) | **+1** throws `ArgumentError` |

### Call-site audit (supersede atomicity)

Production `AttentionDispatchPort.record` outside `MutatingUnitOfWork.run`: **only**
`user_block_case.dart:211` (`helpWithdrawn` — optional, `logicalTaskKey` NULL). All obligation
dispatches go through `TransactionalAttentionCase` / `AttentionTransaction.record` inside
`unitOfWork.run`. **Claim holds for obligations today**; not enforced structurally — U07b should
guard if any bare `dispatch.record` ever emits `requires_action`.

### Beacon hierarchy “casualty”

No assertion rewrite in that file in U05c. Fix is **`m0181`** — extends
`attention_anonymize_deleted_actor` to NULL `logical_task_key` / `lifecycle_generation` on
erasure (production defect caught by teardown `23514` on `notification_outbox__logical_task_chk`).
`beacon_hierarchy_child_independence_pg_test` **+2** at HEAD.

**STATUS:** pass

---

### Manager verdict — U05b · **ACCEPTED** (hard; inner Opus-low ✓ / verify pass, no scout by design, no finisher)

Overseer's own run: **full server suite** — `dart test --exclude-tags pg` → **1660 passed**;
`dart test --tags pg -j 1` → **825 passed, 24 skipped** (all pre-existing `_skipHistoricalMigrationCoverage`).
This is the widened discipline adopted after the `room_now_line` miss: a unit that changes a write path is
verified against the whole suite, never a named list.

Commits `cc1622368` · `cd2d8ed10` · `200c57d37` · `8f9f68d6d` · `af0315cf3` · `879738845`.

**Both contested factual claims were settled by execution, not argument.**
- Reverting dispatch to `f583ac43c` produced **two** delivery jobs for a two-occurrence collapse family,
  confirming that two pushes were the behaviour *before* this unit — so the adjudication that 2→1 is an
  intended improvement rests on a verified premise, not on the inner layer's say-so.
- The old `room_now_line` assertion fails on current code with `Expected: 1, Actual: 2` receipts, confirming it
  was already broken at UNIT_BASE and that the rewrite tracks intended U05a/U05b behaviour rather than hiding a
  U05b regression.

Also verified: the coalesced payload's receipt cannot be deleted at handoff (FK plus retention's
`NOT EXISTS (pending|leased delivery)` guard), and the verifier could not construct a "gone receipt at worker
fire" state; email marking hits exactly the intended family and account and no other; U06a's obligation guard
still holds; no `ON CONFLICT (dedup_key)` returned to dispatch; no U05c work leaked in.

**Two residuals carried forward, neither blocking:**
1. **No test counts actual sends.** Cardinality is proven at the delivery-job and marking layers, not end to end
   as "one email arrived". U19's acceptance journeys should close that, since it is exactly the kind of gap a
   unit test cannot see.
2. **Coalescing is not atomic** — concurrent dispatch can briefly create two pending jobs, bounded afterwards by
   `claimDue`. Pre-existing concurrency class, documented in code. If a duplicate push is ever reported, start
   here.

**Stash incident closed:** the stack is intact, no entry belonging to anyone else was disturbed, and the three
pre-existing modified files are byte-identical to the snapshot.

---

## UNIT U05c — Obligation identity · INNER (2026-09-19)

**Inner:** Claude Code Opus 5, low effort. `UNIT_BASE` `567eaee6b`. Scope: the U05 scout's steps 4 and 5 only.
Three commits plus this entry.

### What changed

| Commit | What |
|---|---|
| `a1df38392` | `test/data/repository/attention_obligation_identity_pg_test.dart` — the red suite |
| `c30078d3d` | `AttentionPolicy.logicalTaskKey` + dispatch writes both columns |
| `783458ef8` | transactional supersede; `m0181` (erasure-trigger casualty) |

### The distinction the unit exists for (overseer addition 2)

A renewal and a retry look identical from the dispatch side and are not, so the suite asserts **both** directions
rather than the happy path:

- *renewal* — `a semantic renewal supersedes its predecessor and bumps to 2`: exactly one live row afterwards,
  generation 2, predecessor `settlement_kind = 'superseded'` and still carrying generation 1.
- *renewal, review flavour* — `a reopened review window is a new generation of one review task`.
- *retry, replay flavour* — `replaying one source_event_key does not bump the generation`: three `record` calls,
  one row, generation stays 1, `settlement_kind` stays NULL.
- *retry, channel flavour* — `a channel delivery retry bumps and supersedes nothing`: a real
  `claimDue` → `retryOrDeadLetter` cycle through the delivery repository, then the obligation row is compared
  **verbatim** against its pre-retry snapshot. Not a spot-check of two columns: no column may move.

The retry direction is the one that would have rotted silently. A suite proving only the renewal stays green
while every retry inflates a counter.

### Why the subject differs per variant

U07a says there are exactly two obligation variants, and their generations mean different things, so one subject
rule cannot serve both:

| Variant | Subject in the key | Because a generation varies over… |
|---|---|---|
| `helpOfferSubmitted` (author) | the **helper** (`targetEntityId`) | withdraw / re-offer cycles. Keyed on the offer id instead, a re-offer would be a *second* obligation, not the next generation of the author's one standing task |
| `reviewOpened` (reviewer) | the **Request** | review windows; reopen is the next generation |

Both carry `beaconId` explicitly, which is what D03 asked for and what the legacy `attention_thread_key` cannot
promise — hence `the same helper on two Requests holds two distinct live tasks`. Any other event type reaching
the helper **throws**: a future obligation variant must declare what its generations vary over rather than
silently inheriting the Request and collapsing unrelated tasks onto one key. `attention_thread_key` keeps its
legacy meaning and value, untouched.

### The constraint catches the mistake, proven by name (overseer addition 3)

`a second live obligation for one logical task is rejected by notification_outbox__live_logical_task` builds two
genuinely live obligations on two Requests, then repoints one at the other's key and asserts
`ServerException.constraintName` is that index — the U04 discipline. It is the one test in the suite that was
**red at the red commit and green after the writer landed**, because it needs real keys to exist before the index
can bite.

### Transactionality, forced rather than assumed (overseer addition 4)

`a failure after the supersede leaves the database unchanged` runs `dispatch.record` for a renewal inside the
caller's unit of work and then throws from that same closure. The supersede and the insert are not sequenced by
hand — they ride the ambient transaction (`MutatingUnitOfWork` → `TenturaDb.withMutatingUser`) — and the test
proves it by observation: afterwards the obligation table is byte-equal to its pre-renewal snapshot, and exactly
one row is live. Neither two live rows nor none.

### Backfill posture (overseer addition 6) — legacy rows keep NULL keys until U18

Existing live obligations keep `logical_task_key IS NULL`. Reasoning:

1. **The partial UNIQUE cannot fire on them.** `notification_outbox__live_logical_task` is
   `WHERE requires_action AND settlement_kind IS NULL AND logical_task_key IS NOT NULL`, and `NULL = 'x'` is not
   true anyway — so a legacy row neither blocks a new write nor gets superseded by one. Backfilling *now* would
   be the risky option, not the safe one: it would make legacy rows eligible for an index they were never
   written to satisfy, and two legacy siblings for one task would abort the migration.
2. **The generation is not derivable today.** A legacy row carries no record of which withdraw/re-offer cycle or
   review window it belonged to. Any backfill now would have to invent a number.
3. **U18 is where it belongs.** The scout's own transition table says U18 expects a restartable backfill with a
   fixed boundary and warns against rewriting old rows in U05.

Consequence, stated plainly: between now and U18 a legacy live obligation and a new keyed one for the *same*
logical task can coexist as two live rows. That is the pre-existing state, not a regression — before U05c every
obligation was in that state — and it is bounded, because only renewals of tasks first dispatched after this
commit are keyed.

### A casualty the unit's own suite could not see — `m0181`

The full PG sweep (not a named list of suites) failed two cases in
`test/domain/use_case/beacon_hierarchy_child_independence_pg_test.dart`, from its **fixture teardown**:

```
Severity.error 23514: new row for relation "notification_outbox" violates check constraint
"notification_outbox__logical_task_chk" ... requires_action = f ...
logical_task_key = v1|reviewOpened|BhierC000001|BhierC000001|Uhiereve0001, lifecycle_generation = 1
```

m0129's `attention_anonymize_deleted_actor` demotes every receipt touching an erased actor to a non-obligation —
it clears `requires_action`, `attention_thread_key` and the settlement facts — but predates m0178's columns, so
it left obligation identity on a row that is no longer an obligation. Harmless while nothing wrote those columns;
the moment dispatch does, **deleting a user who appears in a live obligation aborts**. That is a production
defect, not a test artifact.

`m0181` is m0129's function body verbatim (generated from it, not retyped) plus the two lines the original would
have had, `CREATE OR REPLACE` so the trigger binding is untouched. The unit's suite now covers it directly
(`erasing the actor demotes the obligation and drops its identity`), but it is worth recording that the unit's
own tests did **not** find this and the full sweep did — the second time in this plan a named suite list would
have shipped a casualty.

### Adjacent, deliberately not fixed (overseer addition 5)

`settleReviewerObligationOnPackageSend` still runs outside the attention transaction
(`evaluation_case.dart:1616`). U07b's problem, untouched here. **It does not get worse, and it gets slightly
easier:** that call settles an obligation, it never dispatches one, so it does not pass through the supersede
path at all. When U07b moves it inside the transaction it will be joining a write path where the obligation
supersede is *already* transactional, so there is no second boundary to reconcile.

Also untouched, per the brief: the channel/email path (U05b), `_requiresAction` classification, U03/U03b
contract data.

### Commands

Red, at `a1df38392` (before any writer):

```
$ dart test --tags pg -j 1 test/data/repository/attention_obligation_identity_pg_test.dart
00:02 +3 -6: Some tests failed.
```

After the writer only (`c30078d3d`) — the three renewal/transaction cases still red, and the
constraint-by-name case now green because real keys exist for the index to reject:

```
00:02 +6 -3: Some tests failed.
```

Green, at `783458ef8` (10 cases, the erasure regression added with the fix):

```
$ dart test --tags pg -j 1 test/data/repository/attention_obligation_identity_pg_test.dart
00:02 +10: All tests passed!
```

Casualty suite, after `m0181`:

```
$ dart test --tags pg -j 1 test/domain/use_case/beacon_hierarchy_child_independence_pg_test.dart
00:04 +2: All tests passed!
```

Full server suite, both halves, everything through `scripts/run_with_test_cleanup.sh`:

```
$ dart test --exclude-tags pg
00:08 +1660: All tests passed!

$ dart test --tags pg -j 1
11:45 +835 ~24: All tests passed!
```

24 skips, all `_skipHistoricalMigrationCoverage`, as expected. No other skip.

**One invalid run, disclosed:** an earlier full PG sweep reported 351 failures, every one of them a *load*
failure with an empty error message, because I had started the non-PG suite in the foreground while it ran and
the two races over the build output. Re-run alone, it is the `+835 ~24` above. The failing log is not evidence of
anything and no code changed between the two runs.

### Findings

1. **m0181 above** — a real production defect (account erasure aborting) created by becoming the first writer of
   m0178's columns, found only by the full sweep.
2. **Generation is computed from the superseded rows, not from a counter.** `max(previous) + 1` over whatever the
   supersede returned, so it stays correct if a legacy or repair path ever settles a predecessor by another
   route; and it yields 1 when there is nothing to supersede.
3. **The logical key is a policy concern, not a projection field.** It is a method on `AttentionPolicy` rather
   than a new `AttentionReceiptProjection` field, which kept freezed codegen out of this unit entirely. If U07b
   or U12 needs the key on the projection, that is a mechanical move.
4. **`record` is only safe because every caller wraps it.** Atomicity here is inherited from the ambient
   mutating transaction, not asserted by the repository. The transaction test proves the property for the real
   call shape; a caller that invoked `record` outside a unit of work would get a supersede that commits on its
   own. No such caller exists today. A guard (`isInAmbientMutatingTransaction`) would make it structural and is
   a candidate for U07b, which is already editing this boundary.

**STATUS:** complete

---

### Manager verdict — U05c · **ACCEPTED** (hard; inner Opus-low ✓ / verify pass, no finisher) — U05 complete

Full server suite at HEAD, run by both the verifier and the overseer: **1660 non-PG**, **835 PG / 24 known
skips**. Commits `a1df38392` red · `c30078d3d` writer · `783458ef8` supersede + m0181 · `39a14d571` journal.

**The verifier refuted an inner-layer claim, which is exactly its job.** The inner layer stated that no caller
reaches the supersede outside an ambient mutating transaction. The verifier grepped every call site and found
one: `user_block_case.dart:211` calls `dispatch.record` bare. It is **benign today** — that path emits no
obligations, so the supersede is never entered — but the claim as written was false, and the safety therefore
rests on a coincidence rather than a guarantee. **U07b must add the structural guard**
(`isInAmbientMutatingTransaction` or equivalent), since it already edits this boundary.

**A pre-existing erasure defect was exposed and fixed (m0181).** `attention_anonymize_deleted_actor` dates from
m0129: it demotes an erased actor's receipts to non-obligations by clearing `requires_action`, but it predates
m0178's identity columns and left `logical_task_key` / `lifecycle_generation` populated — violating the new
CHECK and failing a hierarchy suite's teardown with 23514. This is the **second** casualty in this plan found
outside every named regression list, and the first one that was a genuine production bug rather than a stale
test expectation.

Verified by execution: renewal bumps the generation and leaves exactly one live row; a delivery retry leaves the
generation unchanged; a second live obligation for one logical task is rejected by
`notification_outbox__live_logical_task` by name; a failure injected after the supersede leaves the database
unchanged.

**Judgment I endorse — legacy keys wait for U18.** Backfilling `logical_task_key` now would require *inventing*
generation numbers, because a legacy row records nothing about which offer cycle or review window it belonged
to. The partial UNIQUE excludes NULL keys, so legacy rows neither block writes nor get superseded. The named
consequence — a legacy live obligation and a new keyed one for the same task can coexist until U18 — is bounded
to tasks first dispatched before this commit and is acceptable.

**Coverage gaps recorded, none blocking:** no PG proof of the legacy-NULL/keyed coexistence (index semantics
only); no test for "a new `requires_action` type missing from the `logicalTaskKey` switch" (it throws by
construction); and the U05b receipt-at-handoff residual is unchanged.

---

## UNIT U06b — Retention posture + personal Request history read · SCOUT BRIEF (2026-09-19)

**UNIT_BASE:** `40546dde8`. **Mode:** read-only scout; no production edits in this layer.

### Context loaded

- Manifest **§0.2** frozen API name: `attentionRequestHistory(beaconId, cursor, limit)` (design plan §4.2 prose
  says `requestAttentionHistory` — **manifest wins**).
- **D17** / `docs/features/request-attention.md` §9: clearing ≠ deletion; History/timeline stay complete within
  authorization; retention must not remove live obligations or uncleared updates; delivery-job cleanup may stay
  separate.
- **U06a** (`3df3d8eee`): live obligations excluded from retention.
- **U04** (`m0178`): `cleared_at`, `clear_reason`, `cleared_by_operation_id` exist; CHECK ties `cleared_at` to
  `requires_action = false`.
- **U05a/b/c**: immutable `(occurrence_id, account_id)` on new dispatch; channel dedupe is on
  `attention_channel_delivery`, not outbox upsert.
- **U18 not run:** no cutover timestamp column; no `legacy_seen` backfill; `cleared_at` remains NULL on shipped
  rows until later units write it.

---

### (a) Retention posture

#### What `deleteSettledOlderThan` deletes today (post-U06a)

**Caller:** `TaskWorkerCase` only — throttled to once per **6 hours**, age argument **`Duration(days: 30)`**
(`task_worker_case.dart:267–276`). No other production caller.

**Predicate** (`notification_outbox_repository.dart:131–147`):

| Condition | Meaning |
|---|---|
| `seen_at IS NOT NULL` | Read on the read axis |
| `emailed_at IS NOT NULL` | Digest/immediate email channel marked |
| `created_at < now() - age` | Older than 30d window |
| `NOT (requires_action = true AND settlement_kind IS NULL)` | **U06a:** keep live obligations |
| `NOT EXISTS (… delivery.status IN ('pending','leased'))` | Keep receipts with in-flight channel jobs |

**Effect:** Deletes **outbox rows**; **`m0125`** `ON DELETE CASCADE` removes **terminal** `attention_channel_delivery`
rows tied to those receipts (see retention PG test comment). Does **not** delete orphaned delivery jobs for
retained receipts.

**Still deletable today:** Old, seen+emailed **optional** receipts (`requires_action = false`) with no pending/
leased delivery — including rows that are merely “seen” on the read axis but **not cleared** (`cleared_at` ignored).
**Settled** obligations (`settlement_kind IS NOT NULL`) are **not** covered by U06a and remain deletable when
seen+emailed+old. **Unemailed** rows never match (`emailed_at IS NULL`). **Post-U05 dispatch** receipts with
non-null `occurrence_id` are still deletable under the same rules if seen+emailed+old.

#### Required predicate extensions (U06b)

Align DELETE with journal U06a follow-up + manifest step + D17:

1. **Uncleared optional (unconditional):** `NOT (requires_action = false AND cleared_at IS NULL)` — uses m0178;
   matches U06a journal predicate; covers pre-U18 rows where `cleared_at` is always NULL (all optionals protected
   until explicitly cleared).
2. **Post-cutover / attention-bearing history (no date marker until U18):** express as **`occurrence_id IS NOT
   NULL`** — manifest §0.1 defines post-cutover immutable identity as UNIQUE `(occurrence_id, account_id)`; U05
   dispatch always writes `occurrence_id`. Do **not** invent a cutover `timestamptz` in U06b. Legacy rows with
   `occurrence_id IS NULL` may still age-delete when seen+emailed+old (honest pre-cutover limitation; U18 backfill
   does not replay deleted rows).
3. **Optional tightening for cleared history (recommended same commit):** `NOT (cleared_at IS NOT NULL)` so
   cleared receipts are never age-deleted even on legacy NULL-`occurrence_id` rows once clearing lands (U09+).

**Do not change** the pending/leased delivery guard or the seen+emailed age gate for the **legacy deletable
slice**; **do not** add a separate DELETE against `attention_channel_delivery` — “delivery cleanup stays separate”
means channel workers (`AttentionChannelDeliveryRepository.claimDue` / mark delivered) continue independently; receipt
retention only deletes jobs **via CASCADE** when a receipt row is actually removed.

#### `task_worker_case.dart`

Manifest lists it under **Owns**; expect **no schedule change** unless product asks for a different window — U06b
is predicate-only. Worker test `throttles digest and retention sweeps` should stay green with mock outbox.

#### Tests pinning retention (intentional edits expected)

| File | Role |
|---|---|
| `test/data/repository/attention_retention_pg_test.dart` | **Primary.** Test 1 expects `deleted == 2` today (`Nattretlegacy` + terminal relay receipt); after predicate work expect **0** (legacy optional uncleared + dispatch `occurrence_id`). Test 2 (live obligation) should stay **unchanged**. Add explicit cases: uncleared optional retained; post-cutover seen+emailed+settled retained; pending/leased still retained. |
| `test/data/repository/attention_email_marking_pg_test.dart` | **Comment-only contract** — wrong `markEmailedByChannelCollapseKey` + retention can “delete early”; no assertion on `deleteSettledOlderThan` counts unless marking tests start seeding deletable legacy rows. |
| `test/domain/use_case/task_worker_case_test.dart` | Mock counts `deleteSettledOlderThan` invocations only. |

No other file calls `deleteSettledOlderThan`.

---

### (b) `attentionRequestHistory(beaconId, cursor, limit)`

#### Authorization path (“visibility wall”)

Every attention read/subwrite intersects **`public.visible_attention_receipts(p_account_id)`** (installed **`m0117`**
— `beacon_can_read_content` / `beacon_can_read_tombstone`, `access_policy`, preference mutes, `recipient_safe` /
`profile` allowlists). Repository pattern:

```23:25:packages/server/lib/data/repository/attention_repository.dart
  static const _authorizedReceiptJoin = '''
FROM public.visible_attention_receipts(\$1) visible
JOIN public.notification_outbox receipt ON receipt.id = visible.receipt_id''';
```

Ack paths (`markSeen`, `markUnseen`, `markSeenForBeacon`, settlement) all use `receipt_id IN (SELECT … FROM
visible_attention_receipts($1))`. **History must use the same wall** — never `notification_outbox WHERE account_id
AND beacon_id` alone. Tombstone substitution stays in `_mapRow` via `tombstone_copy` from the join (same as feed).

**Not the same query as Activity child expansion:** `activityAttention` loads only `visible.surface = 'activity'`,
excludes `relay_received`, and excludes beacons in **My Work responsibility scope** (`activityAttention` stats query
`WHERE $2 NOT IN (SELECT scope.beacon_id FROM scope)`). History is **all surfaces** for one `beaconId` — My Work
+ Activity receipts, settled obligations, future cleared rows — still gated by `visible_attention_receipts`.

#### Pagination (match feed, do not invent)

Reuse **`AttentionCursor`**: `(createdAt, id)` descending, strict tuple comparison — same as `attentionFeed` and
`_loadActivityChildReceipts` / `activityAttention`:

```536:545:packages/server/lib/data/repository/attention_repository.dart
      cursorClause.write(
        '''
AND (
  $streamAlias.created_at < \$5::timestamptz
  OR ($streamAlias.created_at = \$5::timestamptz AND $streamAlias.id < \$6)
)''',
```

GraphQL: reuse **`QueryAttention._encodeCursor` / `_decodeCursor`** (base64url JSON `createdAt` + `id`) — same
opaque cursor as `attentionFeed` / `activityAttention`. Default/limit clamp **1..100** like feed (`limit.clamp(1,
100)`); manifest does not override — match feed default **50** or activityAttention **20** only if manifest silent;
**prefer 50 + same clamp as `attentionFeed`** for one cursor codec.

Return shape: smallest additive type — e.g. `{ items: [AttentionReceipt], nextCursor }` (new Freezed page type in
`attention_models.dart` + `gqlType…` in `custom_types.dart`). **Do not** reuse `ActivityBeaconAttention` stats
(`eventTotal`, activity-only semantics). **`clearedAt` / `clearReason` not in GraphQL `_mapReceipt` yet** — OK for
U06b if columns are NULL; U13 client integration will extend projection when clearing ships.

#### GraphQL wiring (server-only slice)

| Layer | Location |
|---|---|
| Port | `domain/port/attention_query_port.dart` — add `attentionRequestHistory` |
| SQL | `data/repository/attention_repository.dart` |
| GraphQL field | `api/controllers/graphql/query/query_attention.dart` — add to `all`, mirror `activityAttention` args (`beaconId`, `cursor`, `limit`) |
| Types | `api/controllers/graphql/custom_types.dart` |
| Tests | `test/api/controllers/graphql/attention_graphql_test.dart` (+ update `legacy_canonical_compat_fixture_test.dart` mock port) |
| PG | New group in `attention_repository_pg_test.dart` or dedicated `attention_request_history_pg_test.dart` |

**Client:** manifest **U13** owns `packages/client/lib/features/attention/data/gql/*.graphql`, Ferry codegen,
`AttentionCase`. **U06b should not ship client documents or `_g/`** — smallest coherent land: **server port +
repository + GraphQL resolver + PG + graphql unit tests**. That is testable without a consumer (existing pattern for
`activityAttention`, which also has **no** dedicated PG test file today — add PG coverage here as the proof).

#### Server-only worth landing now?

**Yes.** History retention guarantees (D17) are server-side; U17 timeline/History UI depends on this read but U13
can wire later. PG + `attention_graphql_test` are sufficient acceptance for this unit.

---

### RISKS (explicit)

| Risk | Answer |
|---|---|
| **Unbounded growth** | Post-cutover rows (`occurrence_id IS NOT NULL`) + uncleared optionals + cleared rows (if `cleared_at` guard added) **stop age deletion** → outbox grows per account until **account erasure** (`m0125` CASCADE) or explicit privacy/source deletion paths. Product accepts this per D17 / §9. Legacy NULL-`occurrence_id` slice may still shrink. |
| **Consumers depending on receipts disappearing** | **`attentionFeed` / markers / summaries** have **no time window** — they already assume retained rows (`notification-attention-convergence-plan.md`). Retention shrink mostly affected **old seen+emailed optionals** and **settled** rows removed from DB (not from feed logic). After U06b, **deleted receipts vanish from History read too** — only the **legacy deletable** subset. Tests in **`attention_retention_pg_test.dart`** are the main consumer of deletion counts. |
| **History leak vs feed** | Same **`visible_attention_receipts`** wall → **no extra** blocked-user or deleted-Request content vs any other attention read; tombstone copy applies. History **shows more rows per Request** than Activity stream (My Work receipts, settled obligations, cleared future) — that is **intended**, not a leak. **Does not** expose other participants’ private receipts (still per-account outbox). **Request Timeline UI** (`activity_list.dart`) uses **domain timeline sources**, not receipts — merging personal receipts into timeline is **U17**, not U06b. |
| **Live-code contradictions** | U06b manifest **Owns** `task_worker_case.dart` but only retention **scheduling** lives there — predicate change is in outbox repo. **`attentionRequest` (§0.2)** is **not** in U06b steps — do not implement. Design plan API table names differ (`requestAttention*`) — use manifest names only. |

---

STATUS: complete

BRIEF: After this unit, (1) `deleteSettledOlderThan` no longer removes uncleared optionals (`cleared_at IS NULL`,
`requires_action = false`), post-cutover receipts (`occurrence_id IS NOT NULL`), or live obligations; legacy
NULL-`occurrence_id` rows may still age-delete when seen+emailed+old; channel worker behavior and pending/leased
guards unchanged. (2) `attentionRequestHistory` returns an authorized, paginated, newest-first personal receipt
list for one Request through `visible_attention_receipts`, cursor-compatible with `attentionFeed`, server-only.

STEPS:
1. **Retention predicate** — `notification_outbox_repository.dart` — extend DELETE `WHERE` (uncleared optional +
   post-cutover + optional `cleared_at IS NOT NULL` guard) — **red:** extend `attention_retention_pg_test.dart`
   first (new cases + update `deleted` expectations) — **yes**
2. **Domain port + models** — `attention_query_port.dart`, `attention_models.dart` (history page type) — **red:** PG
   test calling port — **yes**
3. **Repository** — `attention_repository.dart` (`attentionRequestHistory` SQL + `_mapRow`) — **red:** same PG
   tests — **yes**
4. **GraphQL** — `custom_types.dart`, `query_attention.dart`; mocks in `attention_graphql_test.dart`,
   `legacy_canonical_compat_fixture_test.dart` — **red:** graphql test for cursor/beacon bounds — **yes**
5. **Journal verify entry** — command output only — **no** production code

TEST_CMD:

```bash
# Focused (run red → green during development)
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --tags pg -j 1 \
  test/data/repository/attention_retention_pg_test.dart

cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --exclude-tags pg \
  test/api/controllers/graphql/attention_graphql_test.dart

# Unit acceptance + plan gate (never run PG and non-PG concurrently)
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --exclude-tags pg
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 45m -- dart test --tags pg -j 1
```

Named PG suites touched by attention work (non-exhaustive; **full `dart test --tags pg -j 1` required** — casualties
have appeared outside lists, e.g. `room_now_line_pg_test.dart` after U05b):
`attention_retention_pg_test.dart`, `attention_repository_pg_test.dart`, `attention_activity_stream_pg_test.dart`,
`attention_surface_pg_test.dart`, `my_work_attention_pg_test.dart`, `attention_mark_seen_for_beacon_pg_test.dart`,
`attention_dispatch_identity_pg_test.dart`, `attention_obligation_identity_pg_test.dart`,
`realtime_notification_migration_test.dart` (attention sections).

UNTOUCHABLE: `key.fb`, `leo.key`, `out.key`, `dart-defines`, `.serena/project.yml`,
`packages/force_directed_graphview/**`, `docs/plans/constellation-*`, generated `*.g.dart` / client `_g/`; do not
implement U13 client GraphQL/codegen in this unit.

RISKS: Retention test 1 **`deleted == 2` → ~0** must be an intentional assertion update, not a silent drift.
Settled **legacy** obligations with NULL `occurrence_id` remain deletable until U18 — document in test comments.
Implementing History without `cleared_at` in GraphQL payload is fine until U09/U13. Do not widen
`visible_attention_receipts` in U06b. Running PG and non-PG `dart test` **concurrently** has caused flakes — serialize.

---

## UNIT U06b — Retention posture + personal Request history read · INNER (2026-09-19)

Base `40546dde8`. Server-only, as the brief required: no client documents, no Ferry codegen, no
`_requiresAction` / contract-data / channel-email / obligation-identity edits.

### Commits

| Hash | Subject |
|---|---|
| `3ae9c8c58` | feat(attention): retain attention-bearing receipts from age deletion (U06b) |
| `31543c4ec` | feat(attention): read personal Request history behind the shared wall (U06b) |
| `0edeb92b3` | feat(attention): expose attentionRequestHistory over GraphQL (U06b) |

The brief asked for `port+model` and `repository SQL` as two commits. They landed as one: adding
`attentionRequestHistory` to `AttentionQueryPort` without the repository override does not compile, so a
port-only commit would have been a broken tree. No new model type was needed either — see below.

### (1) Retention is not a no-op — both sides pinned

Predicate after the change (`notification_outbox_repository.dart:129–169`), three new conjuncts on top of the
U06a guard:

```sql
AND NOT (requires_action = true AND settlement_kind IS NULL)   -- U06a: live obligations
AND NOT (requires_action = false AND cleared_at IS NULL)       -- D17: uncleared updates
AND cleared_at IS NULL                                         -- D17: clearing is not deletion
AND occurrence_id IS NULL                                      -- U05: post-cutover history
```

Those four collapse to a single surviving deletable class, and it is a real one, not an empty set:

> **legacy** (`occurrence_id IS NULL`) **∧ settled obligation** (`requires_action = true AND settlement_kind IS
> NOT NULL`) **∧ never cleared ∧ seen ∧ emailed ∧ older than 30 days ∧ no pending/leased handoff.**

Both sides are asserted in `attention_retention_pg_test.dart`:

| Class | Test | Assertion |
|---|---|---|
| live obligation | `retains live obligations even when seen, emailed, and older…` (pre-existing, unchanged) | `deleted == 0`, row present |
| uncleared optional | `retains an uncleared optional even when seen, emailed and old` | `deleted == 0`, row present |
| cleared receipt | `retains a cleared receipt — clearing is not deletion (D17)` | `deleted == 0`, row present |
| post-cutover receipt | `retains a post-cutover settled obligation (occurrence_id IS NOT NULL)` | `deleted == 0`, row present |
| pending / leased handoff | test 1 (pre-existing guard) | rows present, delivery jobs intact |
| **legacy settled obligation** | `still deletes a legacy settled obligation that is seen, emailed, old and carries no pending delivery` | **`deleted == 1`, row gone** |

That last row is the proof the 6-hourly `TaskWorkerCase` sweep still does work. `task_worker_case.dart` was not
touched: the window (30 days) and the throttle (6 hours) are unchanged, as the brief expected.

### (2) Growth consequence, in rows

What no longer bounds `notification_outbox`: **age**. Every receipt written by the U05 dispatch path carries an
`occurrence_id`, so from cutover onward *every* receipt this system produces is permanent as far as retention is
concerned. One occurrence with *N* eligible recipients writes *N* rows, and none of them will ever be removed by
the 30-day sweep — not when read, not when cleared, not when the obligation settles, not when the Request closes.
A busy Request that emits 40 occurrences to 10 recipients contributes 400 permanent rows.

What still bounds it:

1. **Account erasure** — `m0125` made the `notification_outbox` → `user` FK `ON DELETE CASCADE`, and
   `attention_channel_delivery` cascades from the receipt. Deleting an account still removes its entire receipt
   history. This is the only mechanism that removes a post-cutover row.
2. **The legacy slice, once** — pre-cutover rows matching the class in §1 continue to age out. This is a finite,
   monotonically shrinking pool that reaches zero and never refills; it is not ongoing capacity relief. U18's
   backfill does not replay rows deleted this way, and that loss is already accepted in
   `docs/features/request-attention.md` §9 ("events lost before this model existed … are not reconstructed").
3. Nothing else. There is no per-account cap, no per-Request cap, and no size-based trim.

Operator query for what the sweep can still reach, i.e. how much of bound 2 is left:

```sql
SELECT count(*) FROM public.notification_outbox
WHERE occurrence_id IS NULL AND cleared_at IS NULL
  AND requires_action AND settlement_kind IS NOT NULL
  AND seen_at IS NOT NULL AND emailed_at IS NOT NULL;
```

When that reaches zero, `deleteSettledOlderThan` becomes a scheduled no-op in practice. D17 accepts this; the
consequence is that any future capacity work has to be a deliberate archival/partitioning decision, not a tweak
to the retention window.

### (3) Authorization — verified in code, not assumed

The scout's claim that the wall is shared with the feed is **correct**, and the enforcing function is
`public.visible_attention_receipts(p_account_id)`, installed by `m0117` (`migration/m0117.dart:7–66`).
`attentionRequestHistory` reaches it through the same `_visibleWithSurfaceCte` constant the feed,
`surfaceSummary`, `myWorkAttention` and `activityAttention` all use — there is no second code path.

Two properties matter and both come from that one function:

- **Foreign accounts.** `WHERE n.account_id = p_account_id` in the candidate CTE. A different account's request
  for this Request's history is structurally empty — it is not a filter applied after the fact. Pinned by
  `a foreign account reads nothing of another account history`.
- **Blocked relationships.** `access_policy = 'beacon_content'` routes through
  `public.beacon_can_read_content`, whose first branch is `WHEN public.block_hides(b.user_id, p_viewer_id) THEN
  false` (`m0171.dart:83`). Pinned by `a block hides history the viewer could otherwise read`, which reads the
  row successfully through a forward edge, inserts a `user_block`, and reads again to get nothing.

### (4) What the read actually returns

`returns cleared and settled receipts for the Request, newest first` seeds three rows on one Request — one
cleared (`cleared_at`/`clear_reason` set), one settled obligation (`settlement_kind = 'resolved'`), one live —
and asserts all three come back in `created_at DESC, id DESC` order, with `settlementKind` mapped through and
`isLiveObligation == false` on the settled one. A query that silently filtered the cleared or settled rows would
fail this, which was the point of the requirement.

Scope is one Request only (`is scoped to one Request`), across **all** surfaces — unlike `activityAttention`,
which restricts to `surface = 'activity'` and excludes beacons in responsibility scope.

### (5) Cursor parity

No new codec. The repository emits the same `AttentionCursor(createdAt, id)` with the same strict tuple
comparison as `attentionFeed`, and the resolver reuses `QueryAttention._encodeCursor` / `_decodeCursor`
verbatim, so an `attentionRequestHistory` cursor is byte-identical in form to a feed cursor. Proven at both
levels:

- PG — `pages on the feed cursor without duplicates or gaps, and stays stable when a newer row arrives between
  pages`: 5 rows over three `limit: 2` pages, with a **newer** row inserted after page 1 is served; the three
  pages return exactly the original 5 ids in order, no duplicate, no gap, and the late arrival does not surface.
- PG — `ties on created_at break by descending id, like the feed`: three rows sharing one `created_at` page
  cleanly across the boundary.
- Unit — `attentionRequestHistory scopes to the account and returns an opaque cursor the feed can also decode`
  takes the cursor string this field emits and feeds it to the `attentionFeed` field, asserting it decodes to
  the same `(createdAt, id)`. That is the parity contract, executable.

### (6) Changed test expectations — named

Exactly one pre-existing test changed its expectations.

**`attention_retention_pg_test.dart`, test 1** — renamed from `keeps pending and leased handoffs, then removes
terminal and no-delivery receipts` to `keeps pending and leased handoffs, and after U06b keeps the terminal and
no-delivery receipts too`.

| Assertion | Before | After | Why |
|---|---|---|---|
| `deleted` | `2` | `0` | Both former casualties are now protected |
| rows surviving of the 5 seeded | `3` | `5` | — |
| surviving id set | `{Nattretunemailed, pending, leased}` | `{Nattretlegacy, Nattretunemailed, pending, leased, terminal}` | — |
| `deliveryCountFor(terminalId)` | `0` (cascaded away with its receipt) | `1` | Nothing was deleted, so m0125's CASCADE never fired |

The two rows that changed class: `Nattretlegacy` is an uncleared optional (`requires_action` defaults to `false`
per `m0118`, `cleared_at IS NULL`) and so is caught by the D17 uncleared-update guard; the terminal relay receipt
is written by `AttentionDispatchRepository.record` and therefore carries an `occurrence_id`, so it is
post-cutover history. Both are intentional, both are commented at the assertion.

Test 2 (`retains live obligations…`) is untouched, as the brief expected. No other pre-existing assertion in the
repository changed. `legacy_canonical_compat_fixture_test.dart` gained a mock-port stub only (the interface grew
a member); it asserts nothing new.

### Test evidence

Step 1 — retention predicate, red:

```
$ cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
    dart test --tags pg -j 1 test/data/repository/attention_retention_pg_test.dart
00:01 +2 -4: Some tests failed.
Failing tests:
  … keeps pending and leased handoffs, and after U06b keeps the terminal and no-delivery receipts too
  … retains a cleared receipt — clearing is not deletion (D17)
  … retains a post-cutover settled obligation (occurrence_id IS NOT NULL)
  … retains an uncleared optional even when seen, emailed and old
```

All four are assertion failures (`Expected: <0> Actual: <1>`, and `Expected: <0> Actual: <2>` on test 1), not
load errors. The fifth new test — the one pinning that deletion still happens — was green from the start, which
is correct: that class was deletable before and stays deletable.

Green:

```
00:01 +6: AttentionRetentionRepository deleteSettledOlderThan (tearDownAll)
00:01 +6: All tests passed!
```

Step 2/3 — history port + repository, red (compile-level, the method does not exist yet):

```
$ … dart test --tags pg -j 1 test/data/repository/attention_request_history_pg_test.dart
test/data/repository/attention_request_history_pg_test.dart:297:34: Error: The method
'attentionRequestHistory' isn't defined for the type 'AttentionRepository'.
00:00 +0 -1: Some tests failed.
```

Green:

```
00:02 +6: attentionRequestHistory (tearDownAll)
00:02 +6: All tests passed!
```

Step 4 — GraphQL, red:

```
$ … dart test --exclude-tags pg test/api/controllers/graphql/attention_graphql_test.dart
00:00 +14 -2: Some tests failed.
Failing tests:
  attentionRequestHistory rejects bad beacon ids and cursors
  attentionRequestHistory scopes to the account and returns an opaque cursor the feed can also decode
```

Green:

```
00:00 +16: All tests passed!
```

Full non-PG server suite:

```
$ cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --exclude-tags pg
00:07 +1662: All tests passed!
```

First attempt at that suite was `+1660 -1`, a load failure in
`test/domain/attention/legacy_canonical_compat_fixture_test.dart` — its fake `AttentionQueryPort` did not
implement the new member. Fixed with a stub in the same commit as the resolver.

Full PG sweep — `dart test --tags pg -j 1`, run strictly after the non-PG run, never concurrently:

```
$ cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 45m -- dart test --tags pg -j 1
11:49 +845 ~24: All tests passed!

[exited with code 0]
```

`~24` is exactly the expected `_skipHistoricalMigrationCoverage` count (`realtime_notification_migration_test`,
`beacon_cover_migration_test`, `m0149_resolution_removal_migration_test`). No other skip appeared, and no
attention suite outside the two touched files changed behaviour — including
`attention_repository_pg_test.dart`, `attention_activity_stream_pg_test.dart`, `attention_surface_pg_test.dart`,
`my_work_attention_pg_test.dart`, `attention_dispatch_identity_pg_test.dart`,
`attention_obligation_identity_pg_test.dart` and `room_now_line_pg_test.dart`.

### Findings

- **No new page type was needed.** The scout suggested a new Freezed page + `gqlType…`. `AttentionPage`
  (`{items, nextCursor}`) and `gqlTypeAttentionPage` already model exactly that and are already the feed's
  return shape, so reusing them is both smaller and what makes the cursor-parity claim structural rather than
  coincidental. `ActivityBeaconAttention` was correctly *not* reused — its `eventTotal`/`unseenCount` are
  Activity-stream semantics that mean nothing for a full-surface history.
- **`clearedAt` / `clearReason` are still absent from the GraphQL receipt projection.** The repository reads the
  rows; `_mapReceipt` does not expose the fields, because `AttentionReceipt` has no such members yet. Harmless
  now (nothing writes `cleared_at` until U08/U09) but it means a client cannot yet *distinguish* a cleared
  receipt in the history payload. That belongs to U09/U13, per the brief.
- **The retention predicate reduces to something simpler than it reads.** `NOT (requires_action = false AND
  cleared_at IS NULL)` combined with `cleared_at IS NULL` means every optional is kept unconditionally; only
  settled obligations survive the filter chain. The redundant-looking form is kept deliberately so each D17 rule
  is legible as its own line and can be removed independently later.
- **Fixture correction, not a code finding:** `settlement_kind` is constrained to
  `resolved|dismissed|superseded|legacy_archived|expired` (`m0118` + `m0166`). An initial fixture used
  `'system'` and was rejected by `notification_outbox__settlement_kind_chk`.

---

## UNIT U06b — Retention posture + personal Request history read · VERIFY (2026-09-19)

**UNIT_BASE:** `40546dde8`. **Commits audited:** `3ae9c8c58`, `31543c4ec`, `0edeb92b3`, `ab95f16f8` (journal only).
Verifier re-ran suites and U06b PG files; did not rely on inner-layer claims alone.

### Inner claims audited by execution

1. **Scheduled no-op once legacy drains** — **Mostly confirmed, one nuance for the owner.** Production
   `deleteSettledOlderThan` is the only ongoing `DELETE FROM notification_outbox` in `packages/server/lib/` (grep
   verified). When **no row matches** `occurrence_id IS NULL ∧ cleared_at IS NULL ∧ settled obligation ∧ seen ∧
   emailed ∧ age ∧ no pending/leased handoff`, the sweep returns **0** — verified by test 1 expecting `deleted ==
   0` while five protected rows remain. **Until that legacy settled slice is empty, the sweep is not a no-op**
   (`still deletes a legacy settled obligation…` → `deleted == 1`). Post-cutover rows (`occurrence_id IS NOT
   NULL`) never match the DELETE. **Other pruning:** account `ON DELETE CASCADE` (`m0125`); one-off / domain
   teardown deletes in migrations (e.g. `m0158`, `m0126`) — not the 6-hour worker. Rows **never emailed**
   (`emailed_at IS NULL`) were never age-deletable (pre-existing); that is a separate growth path, not introduced
   here.
2. **Both sides of retention pinned** — **Confirmed.** Re-ran `attention_retention_pg_test.dart`: **12 passed**
   (6 tests), including keep-classes (live, uncleared optional, cleared, post-cutover, pending/leased) and
   **delete** of `Nattretlegacysettled`.
3. **Authorization** — **Confirmed by executing PG tests** (not code-reading only): `a foreign account reads
   nothing…` and `a block hides history…` both **passed** in `attention_request_history_pg_test.dart`. Wall:
   `visible_attention_receipts` via `_visibleWithSurfaceCte`; account scoping from `n.account_id = p_account_id`;
   blocks via `beacon_can_read_content` → `block_hides` (`m0171:83`).
4. **History returns cleared + settled** — **Confirmed.** `returns cleared and settled receipts for the Request,
   newest first` **passed**; SQL filters `beacon_id` only (no feed `view`/unread/surface predicate on the page).

### Also verified

- **Cursor parity:** `AttentionPage` + existing `_encodeCursor`/`_decodeCursor`; graphql test decodes history
  cursor through `attentionFeed`; PG pagination/stability tests **passed**.
- **`deleted == 2` → `0`:** Required because `Nattretlegacy` (uncleared optional) and terminal dispatch receipt
  (`occurrence_id`) are now protected — not a weakened assertion; legacy-delete class has its **own** test.
- **`clearedAt`/`clearReason` absent from `_mapReceipt`:** Confirmed (`query_attention.dart:372–409`). No
  `cleared_at` writes in server `lib/` outside migration comments/schema. No client `lib/` references to
  `attentionRequestHistory` or `clearedAt`. Harmless today; U13 client will need fields when clearing UI lands.
- **Scope:** `40546dde8..ab95f16f8` touches **9 server paths + journal**; **0** `packages/client` diff. **0** diff
  on contract / dispatch / obligation-identity paths. Worktree: **4 modified + 37 untracked** (overseer dirt
  unchanged; `request-centric-attention-implementation-plan.md` modified outside unit commits).

### Full server suite (verifier)

```
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 45m -- dart test --exclude-tags pg
→ 00:07 +1662: All tests passed!  exit 0

cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 45m -- dart test --tags pg -j 1
→ 11:52 +845 ~24: All tests passed!  exit 0
```

`~24` skips: only `_skipHistoricalMigrationCoverage` in the three historical migration DB test files (message:
"Disabled for the planned schema squash cutover…"). No unexpected skips.

**Verdict:** **PASS** — accept U06b for merge on evidence; no code defects found. Owner messaging should not
equate "no `occurrence_id IS NULL` rows" with "no-op" until the **legacy settled deletable** count (inner §2
operator query) also hits zero.

### Manager verdict — U06b · **ACCEPTED** (scout ✓ / inner Opus-low ✓ / verify pass, no finisher)

Overseer's own full server suite: **1662 non-PG**, **845 PG / 24 known skips**, no `[E]`, no load failures.
(First attempt was spoiled by my own `tail -2`, which cut the PG summary and left only dart's
chain-stack-traces hint; re-run with a proper filter. A verification I mangled is not a verification.)
Commits `3ae9c8c58` retention · `31543c4ec` history read · `0edeb92b3` GraphQL · `ab95f16f8` journal.

**The disclosure this unit was commissioned for, corrected by the verifier.** The inner layer reported that
retention becomes a scheduled no-op "once legacy rows drain". The verifier tightened it: uncleared legacy
optionals with `occurrence_id IS NULL` are kept **forever**, so the sweep stops doing work when the *legacy
settled deletable* count reaches zero — and there is a second, pre-existing growth path nobody had named:
rows that were never emailed were never age-trimmed at all. The operator-facing statement is now accurate
rather than reassuring, which was the point of asking for it in rows instead of adjectives.

Verified by execution rather than by reading:
- retention is pinned on **both** sides — live obligation, uncleared optional, cleared, post-cutover and
  pending/leased rows survive; a legacy settled row (`occurrence_id IS NULL`, seen, emailed, aged) is still
  deleted, so the sweep is not already a no-op;
- authorization on the new history read — a stranger gets an empty page, and a page empties after a block;
  path confirmed as `visible_attention_receipts` (m0117) plus `block_hides` in `beacon_can_read_content`
  (m0171:83);
- the history returns exactly what it exists for — live, settled **and** cleared receipts for the Request,
  with no inherited feed filter silently removing them.

**Design note worth keeping:** no new page type or cursor codec was introduced. History reuses `AttentionPage`
and the feed's own encode/decode, so cursor parity is structural instead of a hand-maintained coincidence.

**Debt, owned elsewhere:** `clearedAt` / `clearReason` are absent from the GraphQL receipt projection, so a
client cannot yet distinguish a cleared row — harmless until something writes `cleared_at` (U08/U09), and owned
by U09/U13.

---

### U07b1 — settlement integrity · `inner`

Base `549aa0288`. Four commits, one per scope item, journal last.
Brief was the U07a matrix (`request-centric-attention-obligation-transition-matrix.md`); no scout. Every row
the matrix cites was re-checked against live code before acting, and every one held — the matrix is accurate,
so nothing in it needed correcting here.

**Commits.** `82a96f293` P0 withdrawal · `d74b9e044` P1 terminal paths · `3c65f7fbb` P2 transaction boundary ·
`9ecdba245` U05c structural guard.

#### The settlement kind is `superseded`, not `resolved`

Every obligation this unit newly settles ends as **`superseded`**, never `resolved`. `resolved` is reserved for
accept/decline and package-send — an actual answer. A withdrawn offer, a removed offerer and a closed Request
all end the obligation without the author ever answering it; recording those as `resolved` would be the
dishonest decrement D04 forbids. `superseded` also gives U07b2 a clean key to hang the "never silently
decrement" explanation event off.

New port methods: `supersedeAuthorHelpOfferSubmitted` (per offerer) and
`supersedeAuthorHelpOfferObligationsOnBeaconClose` (whole beacon). Both are `settlement_kind IS NULL`-guarded,
so they are idempotent, and both run inside the caller's existing attention transaction.

#### 1 · P0 — `HelpOfferCase.withdraw`

Confirmed exactly as the matrix described: `withdraw` recorded the commitment event, the repo withdrawal, room
access revocation, Inbox state and an optional `helpWithdrawn` receipt, and left the author's obligation live.

Per overseer addition 1, the red test asserts the **user-visible count**, not the call:
`AttentionRepository.surfaceSummary(...).needsYouTotal` — the same `requires_action AND settlement_kind IS NULL`
aggregate the desk badge reads. New suite
`packages/server/test/domain/use_case/help_offer_obligation_settlement_pg_test.dart` drives the real
`HelpOfferCase` / `CoordinationCase` / `EvaluationCase` against a disposable Postgres.

```
dart test --tags pg -j 1 test/domain/use_case/help_offer_obligation_settlement_pg_test.dart
RED   00:02 +0 -4    (all four: expected 0/1, actual 1/2/2 — the count never moved)
GREEN 00:02 +4       All tests passed!
```

#### 2 · P1 — `offerRemoved` and beacon close

`offerRemoved` has two producers, both in `coordination_case.dart`: `removeFromRoom` and the removal branch
inside `releaseCommitment`. Both now supersede the author obligation for that offerer.

Beacon close settles per beacon, placed next to `_recordUnansweredAtCloseOffers` inside
`runInBeaconStateTransaction`, so it covers **both** close branches (direct close and review-window open).

Honesty note on the `removeFromRoom` test: `removeFromRoom` requires an *admitted* participant, and admission
goes through `acceptHelpOffer`, which already settles. So in a healthy system the obligation is gone before
`offerRemoved` fires. The test therefore re-opens the receipt with SQL to model a receipt that outlived
admission, and asserts the count drops. That path is a belt, not the main strap — the beacon-close test is the
real P1 coverage and is driven end to end by the use cases.

#### 3 · P2 — settlement inside the transaction (overseer addition 2)

`settleReviewerObligationOnPackageSend` now runs as the last statement inside `runAction`, still
unconditionally (an already-`status = 2` re-entry must still settle a receipt left live by another path).

**What guarantees idempotency now that the retry position is gone.** The old comment cited retries: the call sat
outside the transaction so a failed settle could be re-driven by a later `evaluationFinalize`, after the send
had already committed. That is exactly the split D04 forbids, and it was *only* needed because the two could
commit separately. Idempotency is now carried by the SQL predicate itself — `outbox.settlement_kind IS NULL`
means a second run updates zero rows — and the retry it was protecting cannot arise: if the settlement throws,
the send rolls back with it, so there is no half-applied state to retry into. Re-entry after a *successful*
finalize still works and is still a no-op.

Both directions are pinned, as required:

```
dart test --tags pg -j 1 test/domain/use_case/review_obligation_settlement_pg_test.dart
RED   00:02 +12 -1   'a failing settlement rolls the package send back with it'
                     Expected: not <2>  Actual: <2>   (status committed, receipt live)
GREEN 00:03 +13      All tests passed!
```

`_FailingPackageSendSettlement` delegates every other settlement to the real repository and throws only on the
package-send call, so the failure is injected at the exact seam under test.

#### 4 · U05c structural guard — why a lint test, not a throw (overseer addition 3)

`test/architecture/attention_dispatch_transaction_boundary_test.dart`. It pins the set of `lib/` files that hold
`AttentionDispatchPort` directly (port, repository, `TransactionalAttentionCase`, `UserBlockCase`) and requires
every non-boundary holder to also hold a `MutatingUnitOfWorkPort`.

Three reasons this beats a runtime assertion, in order of weight:

1. **A runtime check cannot see this defect.** `user_block_case.dart:211` — the very call site U05c flagged —
   *is* inside an ambient mutating transaction, entered by `block()`'s own `_unitOfWork.run`. `TenturaDb`
   already exposes `isInAmbientMutatingTransaction`, and a check on it would pass there. The defect class is
   structural: *who holds the port*, i.e. who can reach `record` without a boundary at all. Only a static rule
   sees that.
2. **`user_block_case.dart:211` must keep working, and cannot be converted.** Routing it through
   `TransactionalAttentionCase.runAction` would nest a mutating transaction with a *different* actor — the
   withdrawn offerer, not the blocker — and `TenturaDb.withMutatingUser` raises `StateError` on nested actor
   mismatch. The exception is real, so the rule has to admit it explicitly rather than be enforced blindly.
3. **Blast radius vs. production risk.** A throw in `AttentionDispatchRepository.record` would fire in ~15
   existing PG test files that record fixtures bare, none of them this unit's to rewrite; and a throw on a real
   user path in production would be a worse outcome than the coincidence it replaces. (An `assert` would avoid
   production risk but keeps the whole test blast radius and still fails point 1.)

The guard proves it bites rather than asserting a tautology: a third test feeds a synthetic bare holder to the
same predicate and requires rejection. I additionally verified it end to end by dropping a violating
`lib/domain/use_case/_rogue_dispatch_probe.dart` into the tree:

```
RED   00:00 +0 -2    'direct dispatch-port holders are a declared, reviewed set'
                     'every direct holder owns a mutating transaction boundary'
                     lib/domain/use_case/_rogue_dispatch_probe.dart records attention
                     without holding a MutatingUnitOfWorkPort
GREEN 00:00 +3       All tests passed!   (probe removed)
```

#### Verification

```
dart test --exclude-tags pg          00:10 +1665: All tests passed!
dart test --tags pg -j 1             see manager note below
```
Both through `scripts/run_with_test_cleanup.sh`, one at a time.

`di.config.dart` regenerated (`build_runner`) after `HelpOfferCase` gained `attentionSystemSettlement`;
confirmed injected.

#### Findings

- The U07a matrix is accurate. Nothing in it was wrong, so nothing in it was edited.
- `test/support/review_finalization_test_support.dart`'s `NoopAttentionSystemSettlement` and the other port
  fakes are all `extends Fake`, so the two new port methods did not break them. Only
  `coordination_case_commitment_events_test.dart`'s recording fake needed the new methods, because
  `removeFromRoom` now calls one.
- Pre-existing, untouched: `review_obligation_settlement_pg_test.dart:790` carries an
  `override_on_non_overriding_member` warning on `_StubUserProfileBatchLookup`. Not this unit's.

#### Out of scope, confirmed untouched

Generic user settlement (`attention_settlement_case.dart`, the client Done control), the expiry/cancellation
explanation event, and every `resolutionTransitions` edit — all U07b2. The contract JSON was not opened.

---

### U07b1 — settlement integrity · `verify`

Read-only audit against U07a matrix + U07b1 scoped items. Unit commits `82a96f293` · `d74b9e044` ·
`3c65f7fbb` · `9ecdba245` on base `549aa0288`. Re-ran targeted suites locally; full-suite green cites
overseer run at journal inner entry.

**STATUS:** pass

**TEST_OUTPUT:**
- Overseer (green light): `dart test --exclude-tags pg` → 1665 passed; `dart test --tags pg -j 1` → 851 passed,
  24 known skips (via `scripts/run_with_test_cleanup.sh`).
- Verify: `dart test test/architecture/attention_dispatch_transaction_boundary_test.dart` → 3 passed;
  `dart test --tags pg -j 1 test/domain/use_case/help_offer_obligation_settlement_pg_test.dart` → 4 passed;
  `dart test --tags pg -j 1 test/domain/use_case/review_obligation_settlement_pg_test.dart` → 13 passed.

**ACCEPTANCE:**
- P0 withdrawal / user-visible count — **met** — `help_offer_obligation_settlement_pg_test.dart` asserts
  `AttentionRepository.surfaceSummary(...).needsYouTotal` (not mock `verify` on settlement port); journal
  RED/GREEN on all four PG cases.
- P1 terminal paths — **met** (one coverage note) — `supersedeAuthorHelpOfferSubmitted` in
  `removeFromRoom`, `releaseCommitment` admitted branch, and `supersedeAuthorHelpOfferObligationsOnBeaconClose`
  in `beaconClose`; PG regressions with pre-fix RED for `needsYou` on withdraw, beacon close, and
  `removeFromRoom` (SQL re-open belt). **`releaseCommitment` → `offerRemoved` has no dedicated PG test** —
  same settlement call as `removeFromRoom`, verified by code only.
- P2 transaction + idempotency — **met** — settlement inside `runAction` closure
  (`evaluation_case.dart:1624–1627`); tests `package send and its settlement commit together` and
  `a failing settlement rolls the package send back with it` (`_FailingPackageSendSettlement`); idempotency
  from `settlement_kind IS NULL` SQL guards plus atomic rollback (not “nothing”).
- Structural guard — **met** — architectural inventory test (not runtime throw); `user_block_case.dart:211`
  remains bare `dispatch.record` inside `_unitOfWork.run`; declared holder set includes explicit exception;
  synthetic bare-holder predicate test proves the rule bites; choice defensible per inner rationale.
- Scope / no U07b2 leak — **met** — diff `549aa0288..9ecdba245`: 9 server files only; zero client,
  zero `updates-event-contract.json`, zero `attention_settlement_case.dart`.
- `di.config.dart` regeneration — **met** — `**.config.dart` gitignored; on-disk file is Injectable-generated
  (`GENERATED CODE` header) and wires `attentionSystemSettlement` into `HelpOfferCase`; not in git (expected).
- Tests / untouchables — **met** — no deleted or weakened tests in unit diff (only new PG `skipReason`
  guards); pre-existing modified files and untracked noise unchanged by unit commits.

**GAPS:** No PG regression for `CoordinationCase.releaseCommitment` when it emits `offerRemoved` and calls
`supersedeAuthorHelpOfferSubmitted` (second `offerRemoved` producer); belt on `removeFromRoom` does not
exercise that branch.

### U07b1 gap — `releaseCommitment` settlement coverage · `inner (remediation)`

Base `f5b0b9d50`. One defect, one test, no fix needed.

The verify entry's GAP: `CoordinationCase.releaseCommitment`'s admitted branch (`coordination_case.dart:536–560`)
emits `offerRemoved` and calls `supersedeAuthorHelpOfferSubmitted`, but was covered by code inspection only —
`removeFromRoom`'s PG test does not reach this branch.

New case in `help_offer_obligation_settlement_pg_test.dart`, shaped after the sibling `removeFromRoom` belt:
`offerHelp` → `acceptHelpOffer` (admits + acknowledges) → SQL re-open of the `helpOfferSubmitted` receipt to
model one that outlived admission → `releaseCommitment`. It asserts the user-visible consequence
(`AttentionRepository.surfaceSummary(...).needsYouTotal` drops 1 → 0) plus `settlement_kind = 'superseded'`.

**Outcome: it passed on the current code.** This was a coverage gap, not a live P1 defect — `releaseCommitment`
already settles the author obligation. No production change was made.

```
dart test --tags pg -j 1 test/domain/use_case/help_offer_obligation_settlement_pg_test.dart
00:02 +5: All tests passed!      (unchanged code — the new case is +5)
```

Because a test that has never been red proves nothing on its own, I mutation-checked it: temporarily deleting
the `supersedeAuthorHelpOfferSubmitted` call from the `releaseCommitment` admitted branch turns it red on the
exact assertion, and only that one.

```
00:03 +4 -1: Some tests failed.
  releasing an admitted offerer drops a still-live author obligation
  Expected: <0>  Actual: <1>
  releasing the commitment ends the author obligation too
```
The mutation was reverted; `git diff packages/server/lib` is empty.

**TEST_CMD (all through `scripts/run_with_test_cleanup.sh`):**
```
dart test --tags pg -j 1 help_offer_obligation_settlement_pg_test.dart
                         attention_live_obligations_pg_test.dart
                         my_work_attention_pg_test.dart            00:07 +16: All tests passed!
dart test coordination_case_{release,commitment_events,revert}_test.dart
          coordination_room_access_test.dart help_offer_case_test.dart  00:00 +91: All tests passed!
```

---

### Manager verdict — U07b1 · **ACCEPTED** (hard; no scout by design / inner Opus-low ✓ / verify pass / one remediation)

Overseer's own full server suite at HEAD: **1665 non-PG**, **851 PG / 24 known skips** (up from 1662 / 845 —
the new tests). Commits `82a96f293` P0 · `d74b9e044` P1 · `3c65f7fbb` P2 · `9ecdba245` guard ·
`b6b271a58` remediation.

**The runner killed the inner worker mid-verification**, not mid-work: its four commits and its journal entry
were complete, but it was waiting on its own full PG sweep when the 3600s limit expired, so the entry never got
committed. The overseer committed it with attribution. **Process change adopted:** inner workers on this plan no
longer run the full server suite — the overseer runs it independently anyway, so the duplication was costing an
hour of worker budget and, here, the journal commit.

**The transaction move's real question got a real answer.** `settleReviewerObligationOnPackageSend` sat outside
the attention transaction behind a comment citing retry idempotency; moving it inside could have silently traded
that away. It did not: idempotency now rests on `settlement_kind IS NULL` in the settlement SQL plus
single-transaction rollback, so a half-applied send+settle is unreachable and a successful re-entry is a no-op
UPDATE. Both directions proven by execution — success commits both, an injected settlement failure rolls the
package send back with it.

**The structural guard is an architectural inventory test, not a runtime throw** — and the reasoning is sound:
a runtime ambient-transaction check would have false-passed the very call site that prompted it
(`user_block_case.dart:211`), and a throw on a live user path would be worse than the coincidence it replaces.

**Remediation, and the right outcome honestly reported.** The verifier found the P1 path
`releaseCommitment → offerRemoved` was covered by code inspection only. The remediation test **passed on current
code** — a coverage gap, not a defect — and rather than leave that as an assertion, the worker proved the test
bites by deleting `supersedeAuthorHelpOfferSubmitted` from the branch, observing the failure on exactly that
case, then reverting and confirming `git diff packages/server/lib` was empty. No production code changed.

---

### U07b2 — lifecycle vocabulary · `inner`

Base `1db2a9684`. Three items, three commits: `f04d2ec56` · `30f99902a` · `caf76942d`. No scout by design;
brief was `request-centric-attention-obligation-transition-matrix.md`, which held up on every row I re-checked.

#### 1 · Generic user settlement refuses every obligation kind (owner decision C)

The matrix's P1: `attentionSettle` still resolved help-offer obligations while review was blocked at three
layers. Rather than add `helpOfferSubmitted` to a deny-list, the use case now refuses on the *class*:
`liveObligationEventType` only ever names a receipt that still `requires_action`, so a non-null answer is by
definition a live obligation, whatever kind it is. The repository statement gained the second layer review
already had (`event_type IS DISTINCT FROM 'helpOfferSubmitted'`).

**Consequence, stated plainly:** `attentionSettle` can now settle nothing at all, because the only rows it was
ever able to match were obligations. That is decision C, not an accident — "there is no bare Done". The mutation
is left in place because removing it is a client-visible change and the client's Done control is U15.

```
dart test test/api/controllers/graphql/attention_graphql_test.dart
RED   00:00 +15 -1   'attentionSettle rejects helpOfferSubmitted live obligations'
                     (the case called through; settle returned 1)
GREEN 00:00 +17      All tests passed!

dart test --tags pg -j 1 test/domain/use_case/help_offer_obligation_settlement_pg_test.dart
RED   00:02 +5 -1    'generic user settlement refuses a help-offer obligation'
                     Expected: throws ArgumentError   Actual: emitted <1>
GREEN 00:02 +6       All tests passed!
```

The PG case pins both layers on one live obligation: the use case throws, and the repository — called directly,
past the use case — updates 0 rows and leaves `needsYouTotal` at 1.

#### 2 · The expiry sweep explains the obligation it ended

New event type `AttentionEventType.obligationEnded`, presentation key `obligation_ended`, optional, standard
suppression, `unblocksMe`, beacon destination.

**The guard was checked before the declaration, as required.** Adding the enum value with no classification row
failed `updates_event_contract_test.dart` exactly as it should:

```
dart test test/architecture/updates_event_contract_test.dart
00:00 +1 -1   'event classifications cover every AttentionEventType'
              each runtime enum value must have exactly one classification row
```

Only then was the contract row written: all mandatory card-contract fields present, `coalescible: false`,
`recoverableVia: request_timeline`. **`schemaVersion` 4 → 5, deliberately** — a new event type changes what a
reader of the contract must handle, which is what the version is for. Both mirrors (`packages/server` and
`packages/client` architecture tests) and `AttentionEventTypeCatalog.contractSchemaVersion` moved with it.

**`coalescible: false`** is a judgement, not a copy of the neighbouring row: an explanation that merges into a
count stops explaining. There can only ever be one per Request per reason anyway, so nothing is lost.

**Idempotency is the occurrence grain, not a new dedup mechanism.** The source event key is derived
(`obligation_ended:review_expired:<beaconId>`), never a fresh id, so a second sweep hits
`ON CONFLICT (source_event_key) DO NOTHING` and returns before any receipt is written. The test sweeps twice and
asserts one occurrence and one receipt per reviewer.

```
dart test --tags pg -j 1 test/domain/use_case/review_obligation_settlement_pg_test.dart
RED   00:02 +0 -2    (producer mutated off: `if (false)`)
                     'an expired sweep explains the obligation it ended, exactly once'   Expected: <1> Actual: <0>
                     'a reviewer who sent their package gets no expiry explanation'      Expected: <1> Actual: <0>
GREEN 00:03 +15      All tests passed!    (13 before this unit)
```

The mutation was reverted before the green run; `git diff` on the sweep case is the shipped version.

**Per-row reasoning — which transitions owe an explanation (overseer addition 2).** Item 2 says "expiry *or*
cancellation". I did not emit for every settlement that is not the person's own act; I asked per row whether the
drop was already explained, and only one row was not:

| Obligation ends by | Whose act | Already explained? | Decision |
|---|---|---|---|
| Review window expires (`AttentionExpirySweepCase.runDue`) | nobody's — a timer | **No.** `requestStatusChanged` says the Request closed; it does not say the reviewer's own task ended | **New `obligationEnded` producer** |
| Author closes the window early (`EvaluationCase.closeNow`) | the author's | n/a — **unreachable**: `_canCloseNow` refuses unless every author/committer participant is already at status 2, so `closeAndFinalize` can leave no `expired` obligation behind | **No producer.** I wrote one, then deleted it rather than ship a producer that can never fire and a contract row that would have claimed it could |
| Author cancels the window (`EvaluationCase.reopenFromReview`) | the author's | **Yes** — `reviewWindowCancelled`, high priority, to the same review participants | No new producer |
| Helper withdraws their offer (`HelpOfferCase.withdraw`) | the helper's | **Yes** — `promiseWithdrawn` (`helpWithdrawn` intent) to the author | No new producer |
| Author closes the Request (`EvaluationCase.beaconClose`) | the author's own | the author is the actor and the recipient | Nothing to explain |
| Author removes/releases an offerer (`removeFromRoom`, `releaseCommitment`) | the author's own | same | Nothing to explain |

Both "no producer" conclusions are recorded on `AttentionObligationEndReason` in code, so the next reader does
not re-derive them: the enum has exactly one value and says why it has one.

#### 3 · `resolutionTransitions` reconciled, per row

The contract is the specification and the code is the evidence, so each disagreement got a verdict, not a
find-and-replace:

| Declared | Live | Verdict | Action |
|---|---|---|---|
| `HelpOfferCase.withdrawHelpOffer` | `HelpOfferCase.withdraw` | **Declaration wrong.** The transition is real, the method is real, and U07b1 made it settle — only the label was invented | Renamed |
| `EvaluationCase.submitReviewPackage` | `EvaluationCase.evaluationFinalize` | **Declaration wrong**, same shape: package send settles via `settleReviewerObligationOnPackageSend` inside the transaction since U07b1 | Renamed |
| — | `ReviewFinalizationCase.closeAndFinalize` | **Contract under-declares.** §5 names window close as one of the three ways a review ends; the code has always settled there | Added |
| — | `EvaluationCase.reopenFromReview` | **Contract under-declares.** §5's "author cancelling"; supersedes | Added |
| — | `ReviewObligationBackfillCase.run` | **Contract is right to omit it.** It re-runs the window-close transition as a repair job; it is not a way a review can end | Left out, deliberately |
| — | `CoordinationCase.removeFromRoom`, `CoordinationCase.releaseCommitment`, `EvaluationCase.beaconClose` | **Contract under-declares** the terminal-invalidation paths U07b1 implemented | Added |
| `attentionSettle` / My Desk Done | was a live settlement path | **Code was wrong** — fixed in item 1 | Never declared; now cannot settle |

Nothing here was a U07b1-class defect: every declared transition existed in code and settled. The two failures
were both naming, and the omissions were all in the contract's direction.

New guard `test/architecture/obligation_resolution_transitions_test.dart` fails when a declared transition names
a method that does not exist on the class it names — matching the *declaration* (two-space member indent), so a
call site cannot vouch for a method nobody defined. It keeps the two U07a labels as a negative fixture, so the
rule is proven to bite rather than asserted to.

```
dart test test/architecture/obligation_resolution_transitions_test.dart
RED   00:00 +2 -1    ['HelpOfferCase.withdrawHelpOffer', 'EvaluationCase.submitReviewPackage']
GREEN 00:00 +3       All tests passed!
```

#### Test changes, named (overseer addition 3)

The item-1 blast radius the overseer predicted **did not exist**: I grepped every use of `AttentionSettlementCase`
and `AttentionSettlementRepository.settle` in `test/` — three call sites, all already asserting refusal or using
a null live-obligation fake. No test settled a help-offer obligation through the generic path for convenience, so
no test was rewritten to accommodate item 1. Everything below is item 2's contract widening.

| File | Before | Now | Why |
|---|---|---|---|
| `attention_graphql_test.dart` | 3 `attentionSettle` cases; `reviewOpened` refused | +1 case: `helpOfferSubmitted` refused, `settleCalls` stays 0 | New behaviour |
| — same file, `'scopes a user-resolvable live obligation'` | **unchanged** | **unchanged** | Its fake reports *no* live obligation, so it still exercises the pass-through branch. Left alone deliberately: it is now the only case proving the refusal is scoped to live obligations and not blanket |
| `help_offer_obligation_settlement_pg_test.dart` | 5 cases | +1 two-layer refusal case, +`_helpOfferReceiptId` helper | New behaviour |
| `review_obligation_settlement_pg_test.dart` | 13 cases; `_FailingPackageSendSettlement` implemented 6 port methods | +2 expiry-explanation cases, +3 count helpers, +real `AttentionExpirySweepCase`; the fake delegates the 7th port method | New port method + new producer |
| `attention_policy_test.dart` | fixture per contract `eventTypes` row | +`obligationEnded` fixture (`reviewParticipant`, base role) | Data-driven guard demanded it — it failed first, `No policy fixture for obligationEnded` |
| `attention_intent_case_test.dart` | producer fixture per migrated type | +`obligationEnded` fixture; +`v1\|obligation_ended\|` collapse-key arm | Same guard; failed twice first (missing fixture, then `v1\|none\|` collapse assumption) |
| `updates_event_contract_test.dart` (server **and** client) | rev 4 row list | +`obligationEnded` row, `schemaVersion` 5, title says rev 5 | Contract change |

**One client file was touched**, against the untouchable list, and only this one:
`packages/client/test/architecture/updates_event_contract_test.dart`. It is a hand-mirrored copy of the server's
contract constants; a server-side contract change cannot leave it green. No client `lib/` file changed — the
client renders server-supplied title/body and falls back generically on an unknown presentation key, so
`obligation_ended` needs no client copy to display correctly. Adding it to `updates_receipt_display_copy.dart`'s
fallback map is a real (small) follow-up, listed under REMAINING.

#### Verification

```
dart test test/architecture/ test/domain/attention/ test/domain/evaluation/ \
          attention_expiry_sweep_case_test.dart help_offer_case_test.dart \
          attention_graphql_test.dart                                   00:01 +293: All tests passed!

dart test --tags pg -j 1 review_obligation_settlement_pg_test.dart \
          help_offer_obligation_settlement_pg_test.dart attention_live_obligations_pg_test.dart \
          my_work_attention_pg_test.dart attention_surface_pg_test.dart \
          attention_obligation_identity_pg_test.dart attention_dispatch_identity_pg_test.dart
                                                                        00:19 +60: All tests passed!

(client) flutter test test/architecture/                                00:11 +16: All tests passed!
```

All through `scripts/run_with_test_cleanup.sh`. Per the process change adopted at U07b1, the full server suite
was **not** run here; the overseer runs it independently. `di.config.dart` regenerated via `build_runner` after
the port gained a method.

#### Findings

- **`EvaluationCase.closeNow` cannot strand a reviewer.** This is the one place the matrix's framing was
  incomplete — it lists close-now as a settlement path producing `expired`, which is true of
  `settleReviewObligationsAfterWindowClose` in isolation but unreachable through `closeNow`'s own precondition.
  Worth knowing before U15 writes copy for it.
- `attentionSettle` is now a mutation that always refuses. Flagged for U08/U15 rather than removed here.
- `AttentionSystemSettlementPort` gained `listExpiredReviewObligationAccountIds`; every test fake but one is
  `extends Fake`, so only `_FailingPackageSendSettlement` (a real `implements`) needed the new member.

#### Out of scope, confirmed untouched

The client Done control and every other client `lib/` file (U15), obligation identity, the channel/email path,
`AttentionExpirySweepCase`'s per-beacon isolation semantics, and the U07a P2 gaps closed in U07b1.

#### finisher · test doubles for `listExpiredReviewObligationAccountIds`

Overseer full-suite verify: 11 failures, one root cause — `NoopAttentionSystemSettlement` (and every PG stack
that wires `ReviewFinalizationCase` through it) still `extends Fake` without the U07b2 port method
`listExpiredReviewObligationAccountIds`, so `closeAndFinalize` blew up at line 93 before lifecycle or trust
assertions ran.

**Fix:** implement on `NoopAttentionSystemSettlement` only — `listExpiredReviewObligationAccountIds` → `[]`
(incidental no-op: finalization-shape tests do not assert expiry explanations; those live in
`review_obligation_settlement_pg_test.dart`). Also stubbed the two help-offer supersede port methods the class
had already been missing, so the fake fully implements the port.

**Meaning tests after green:** `re-close is idempotent when forward episode already exists` and `manual and expiry
finalization share the same hierarchy closed shape` still pass unchanged — **plumbing-only**; U07b2's new
`recordEligibleSourceTransition` call does not alter re-close idempotency or the closed hierarchy shape those
cases assert.

```
dart test review_finalization_case_test.dart forward_outcome_finalization_test.dart     00:00 +7: All passed!
dart test --exclude-tags pg                                                             00:07 +1671: All passed!
dart test --tags pg -j 1                                                                12:01 +855 ~24: All passed!
```

All through `scripts/run_with_test_cleanup.sh`. `~24` skips are `_skipHistoricalMigrationCoverage` only.


### Manager verdict — U07b2 · **ACCEPTED** (hard; no scout by design / inner Opus-low / verify FAIL → finisher ✓)

Overseer's own full suite after the finisher: **1671 non-PG**, **855 PG / 24 known skips** (baselines 1665 / 851).
Commits `f04d2ec56` refuse generic settlement · `30f99902a` expiry explanation · `caf76942d` contract
reconciliation · `c36a752bc` journal · `5af413658` finisher.

**This unit is why the overseer now owns the full sweep.** The inner layer was told *not* to run it (the previous
worker died on exactly that), reported green on its named suites — correctly, within what it ran — and the
**overseer's gate caught 11 failures**, all one root cause: `closeAndFinalize` gained a call to a port method
that the `extends Fake` doubles do not implement, so they threw `noSuchMethod` before any assertion ran. The
split of duties worked: work with the inner layer, completeness with the overseer.

**The finisher was given the one question that mattered and answered it.** Two of the failures were about
meaning, not plumbing — "re-close is idempotent when a forward episode already exists" and "manual and expiry
finalization share the same hierarchy closed shape". Fixing the doubles could have left them green while hiding
a genuine change in closed-shape behaviour. It reported **plumbing-only**, and both tests pass with their
**original assertions** — so the new event does not alter re-close idempotency or the hierarchy closed shape.

**Three honest negative results from the inner layer, all worth keeping:**
1. **A producer was written, found unreachable, and deleted.** `EvaluationCase.closeNow` cannot strand a
   reviewer — `_canCloseNow` refuses unless every participant is already finished — so an author-cancelled
   explanation could never fire. The matrix's framing was true of the SQL in isolation, not of that path.
   Shipping a dead producer plus a contract row claiming it fires would have been worse than shipping nothing.
2. **Only one row actually needed a new explanation.** Author-cancel is already `reviewWindowCancelled`,
   helper-withdraw is `promiseWithdrawn`, and the rest are the recipient's own act.
3. **The blast radius I predicted did not exist**: no test settled a help-offer obligation through the generic
   path, so zero tests were rewritten for item 1. I expected otherwise and was wrong.

**Disclosed boundary touch, accepted:** `packages/client/test/architecture/updates_event_contract_test.dart` is a
hand-mirrored copy of the server contract constants and cannot stay green through a contract change. No client
`lib/` file was touched. `schemaVersion` 4 → 5 for the new event type, with both mirrors and the catalog moved.

**Carried forward:** `attentionSettle` is now a mutation that always refuses — left in place because removing it
is client-visible (U15/U08); and `obligation_ended` has no arm in the client's fallback display-copy maps
(harmless while the server supplies title and body — U15).

---

## UNIT U08 — Clear command (single and open) · SCOUT BRIEF (2026-09-19)

**Scout:** read-only at `UNIT_BASE` `f38913f8d` (`HEAD` matches). No production code, no tests, no commits
beyond this journal entry.

### Live baseline (verified)

| Area | Fact |
|---|---|
| **Clear columns** | `notification_outbox.cleared_at`, `clear_reason`, `cleared_by_operation_id` exist (`m0178`); **no server writer** yet. |
| **Operation tables** | `attention_clear_operation` (PK `id` = client `operationId`), `attention_clear_operation_member` (PK `(operation_id, receipt_id)`; `outcome_generation`, `state`, snapshot `beacon_id`). |
| **FK (U04 carry)** | `notification_outbox__cleared_by_operation_fkey` → `attention_clear_operation(id) ON DELETE SET NULL`. U04 suite proves valid op id; **no test rejects unknown id** — U08 must. |
| **Request state** | `attention_request_state` empty in prod until first writer; columns `outcome_generation`, `decision_revision` for outcome identity. |
| **Feed / history reads** | All use `visible_attention_receipts($account)` + `visible` CTE (`attention_repository.dart:147–173`). **No `cleared_at` filter** in projections; unread still `seen_at IS NULL` (U10 will switch indicators to D02). |
| **Pagination cursor** | `QueryAttention._encodeCursor` / `_decodeCursor`: base64url JSON `{"createdAt","id"}` only (`query_attention.dart:312–341`). **Not** a membership snapshot. |
| **Ack today** | `attentionMarkSeen`, `attentionMarkSeenForBeacon`, etc. (`mutation_attention.dart`); `markSeenForBeacon` sets `seen_at` only (`attention_repository.dart:1277–1298`). **No server Request-open lifecycle** — D05's pre-nav ack is client-driven today. |
| **Frozen mutation** | `attentionClear(snapshotToken, operationId)` in manifest §0.2; **not implemented**. `attentionDismissAll` = **U09**. |
| **GraphQL receipt** | `_mapReceipt` omits `clearedAt` / `clearReason` (U06b verify) — fine for U08 server-only. |
| **`attentionRequest` query** | §0.2 frozen name; **not on server** (only `attentionRequestHistory` from U06b). |

### D02 optional axis (SQL)

**Active optional (D02):** `requires_action = false AND cleared_at IS NULL`.

**Eligible to capture/clear (authorized):**

```sql
receipt.id IN (SELECT receipt_id FROM public.visible_attention_receipts($account_id))
AND receipt.account_id = $account_id
AND NOT receipt.requires_action
AND receipt.cleared_at IS NULL
```

Add `receipt.beacon_id = $beacon_id` for Request-scoped open/card captures; add `receipt.id = $receipt_id` for event `×`.

**Must never be cleared (DB + product):**

| Class | Why |
|---|---|
| Live obligations | `requires_action = true` → `notification_outbox__clear_optional_only_chk` / `__clear_facts_chk` reject writes. |
| Settled obligations | Still `requires_action`; same CHECK. |
| Owner decision A rows | Unanswered forwards (`inbox_item` pending decision — D07), pending invite/setup prompts — **exclude at capture** for open/single; U09 sweep skips at apply. U08 does not implement sweep-wide capture. |
| Decision-bearing feed rows | Forward **outcome** rows are not normal optional receipts; do not put them in a single-event token. **Outcome tombstone** (`inbox_item.tombstone_dismissed_at`) extension is **U09** step 1 — U08 owns **outbox optional receipts** only unless manifest is amended. |

`clear_reason` for U08: `explicit` (event/card explicit dismiss) and `request_open` (post-display open clear). `sweep` is **U09**.

### Snapshot token — do **not** reuse the feed cursor

The feed cursor is a **pagination key** `(created_at, id)` over a moving projection. After U05, receipts are **immutable per occurrence**; the boundary for clearing is a **finite member set** (+ outcome identity), not “older than cursor”.

**Reuse:** only the **transport pattern** (base64url JSON) from `QueryAttention._encodeCursor`, with a **different schema version** and payload.

**Token must bind (verify on apply):**

1. **Account** — from JWT (`getCredentials(args).sub`); never trust client-supplied account id inside token without HMAC/signature keyed server-side.
2. **Request** — `beaconId` for open/card paths; for single-event, beacon id in token must match receipt's `beacon_id` (or null non-beacon optional — single-receipt path still binds receipt id list).
3. **Member set** — ordered-stable list of `receipt_id` captured at issue time (immutable after capture).
4. **Outcome identity** — `outcome_generation` and `decision_revision` read from `attention_request_state` at capture (use `0`/`0` when no row); store on each `attention_clear_operation_member` row for undo/conflict detection (U09).
5. **Capture kind** — `explicit` vs `request_open` (drives `clear_reason` on apply).
6. **Schema version** — int constant so U10 cursor versioning does not collide.

**Issue snapshot (server):** new port method e.g. `captureClearSnapshot(accountId, beaconId, {ClearCaptureKind kind, String? singleReceiptId})` runs authorize (`beacon_can_read_content` / visibility — same wall as history), evaluates eligible predicate above, returns opaque token + optional diagnostic counts for tests.

**Manifest gap:** U08 **Owns** list names only `mutation_attention.dart` + clear case/repo — but D05 requires **issue-before-apply**. Implementer should either (a) amend manifest to add minimal **`attentionRequest`** (or `attentionRequestSnapshot`) on `query_attention.dart` returning `{ snapshotToken }`, or (b) expose capture only on the domain port for PG tests and add GraphQL in a tiny follow-up commit before U13. **Recommendation:** add frozen-name **`attentionRequest(beaconId)`** returning `{ snapshotToken }` in U08 (page/events wait for U10).

### `attentionClear(snapshotToken, operationId)` — idempotency & tables

**First apply (new `operationId`):**

1. `INSERT INTO attention_clear_operation (id, account_id, surface, status, …)` — `id` = client `operationId`; `surface` free text (e.g. `request_open`, `explicit`, `beacon:<id>`).
2. `INSERT` members from decoded token (fixed set); `ON CONFLICT DO NOTHING` on `(operation_id, receipt_id)`.
3. Per member: re-check `visible_attention_receipts`, eligible optional predicate, beacon scope; `UPDATE notification_outbox SET cleared_at = now(), clear_reason = $reason, cleared_by_operation_id = $operationId` where eligible.
4. Set `cleared_by_operation_id` **whenever** operation row exists (manifest idempotency + FK proof) — contradicts m0178 COMMENT suggesting NULL for explicit/open; **treat COMMENT as stale**; manifest + U04 verify win.

**Replay same `operationId`:** header `INSERT` conflicts → load existing operation + members; **do not extend membership**; re-run apply only for members still uncleared; return **same authoritative applied set** as first success (counts/idempotent). No duplicate clears, no error.

**Concurrent replay:** two requests same `operationId` — one wins `INSERT`, other reads; both return identical applied summary; partial apply + retry must not add receipts.

**FK proof (carried U04):** PG test: `UPDATE notification_outbox SET cleared_by_operation_id = 'missing-op'` → FK violation `notification_outbox__cleared_by_operation_fkey`.

**Foreign / invisible receipt in token:** deny apply for that member (or whole token if tampered) **without** confirming existence to unauthorized callers (D11) — mirror `markSeen` visibility subquery pattern.

**Return shape (design plan §4.2):** typed result: `appliedReceiptIds`, `skippedReceiptIds`, `deniedReceiptIds`, `operationId`, `status` (`complete` / `partial` / `denied` / `stale`); GraphQL field on mutation.

### U08 vs U09 boundary

| | **U08 `attentionClear`** | **U09 `attentionDismissAll`** |
|---|---|---|
| **Trigger** | Deliberate single event, Request-open snapshot, explicit card optional set (multi-receipt token, still one Request). | Whole **surface** sweep (For You). |
| **Capture** | Client holds **pre-issued** `snapshotToken` (finite list). | Server captures **all dismissible members** across unloaded pages at sweep start. |
| **Scope** | One Request (or one receipt). | Entire `activity` surface. |
| **Skips** | Members not in token; obligations never in token. | Unanswered forwards, prompts, obligations, Requests that gained My Desk responsibility since capture. |
| **Progress** | Single transaction or small batch OK. | Batched apply, `applied/skipped/failed`, resumable, undo window — uses same tables but U09 owns orchestration. |
| **Outcome tombstone** | Prefer **U09** unless card `×` is explicitly in U08 scope as multi-receipt `explicit` only. |

Do **not** implement sweep eligibility scanning, surface-wide capture, undo, or `attentionDismissAll` in U08.

### Request-open path (D05) — server contract for U13/U17

**Today:** no server open hook; client calls `attentionMarkSeenForBeacon` before navigation (`mutation_attention.dart:81–89`).

**Target contract:**

1. **After authorize + load** (client has validated navigation target): call snapshot issue (`attentionRequest` / capture port) → receive `snapshotToken` bound to **current** optional receipt ids + outcome generation.
2. **After Request detail successfully mounts** (client-only gate): call `attentionClear(snapshotToken, operationId)` with `clear_reason = request_open`.
3. **Failed auth / forbidden / aborted navigation:** client must **not** call clear; server rejects tokens issued then invalidated if apply attempted without visibility.
4. **Events committed after step 1** are **not** in member list → remain uncleared (acceptance).
5. **Review deep link:** capture excludes live review obligation; optional updates only (product §4).

Server does **not** infer “open” from beacon fetch or room watermark (`bridgeRoomWatermark` is read axis only).

### Race / auth — correct observable outcomes (implement tests)

| Scenario | Correct outcome |
|---|---|
| **Event arrives between snapshot and apply** | New receipt **uncleared**; dot/count unchanged for that event until explicit clear or later open. |
| **Same `operationId` replayed (serial or concurrent)** | **No-op** on already-cleared members; response equals first successful apply; one operation row. |
| **Request moves to My Desk / leaves Activity scope between capture and apply** | Members still clear if still visible + optional; if visibility lost, **skip/deny** those members without leaking; do not clear hidden receipts. |
| **Authorization lost mid-apply** | Uncleared for lost-access receipts; no settlement; partial result reported; no existence leak for foreign ids. |
| **Tampered token (extra foreign receipt id)** | **Denied** / dropped member; no cross-account effect. |
| **Obligation receipt id in token** | Apply **fails** CHECK if forced; capture path must not include. |
| **Unknown `cleared_by_operation_id`** | FK **rejects** (dedicated PG test). |

### Suggested implementation layout

| Layer | Files |
|---|---|
| Port | `packages/server/lib/domain/port/attention_clear_port.dart` — capture + apply |
| Case | `packages/server/lib/domain/use_case/attention_clear_case.dart` |
| Repo | `packages/server/lib/data/repository/attention_clear_repository.dart` (raw SQL; keep `attention_repository.dart` for U10) |
| GraphQL | `mutation_attention.dart` — `attentionClear`; optional `query_attention.dart` — snapshot issue |
| DI | `@Injectable` registration alongside other attention ports |

Do **not** change client, contract JSON, obligation identity, or channel path.

### TEST_CMD (implementer — affected suites only)

```bash
cd /home/vader/MY_SRC/tentura/packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --tags pg -j 1 test/data/repository/attention_clear_operation_pg_test.dart

cd /home/vader/MY_SRC/tentura/packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- \
  dart test test/api/controllers/graphql/attention_graphql_test.dart
```

Also extend **`attention_additive_schema_pg_test.dart`** OR clear suite for FK reject if not duplicated.

Optional regression (no projection change expected yet): `attention_mark_seen_for_beacon_pg_test.dart`, `attention_request_history_pg_test.dart`.

Overseer runs full server suite independently.

---

STATUS: complete

BRIEF: Ship server `attentionClear(snapshotToken, operationId)` with HMAC-bound snapshot tokens (member receipt ids + beacon + outcome/decision generation + capture kind), using `attention_clear_operation` / `_member` for fixed membership and idempotent replay; capture via new clear port (+ minimal `attentionRequest` snapshot issue recommended); clear only authorized optionals (`NOT requires_action AND cleared_at IS NULL`); `explicit` and `request_open` reasons; prove FK on `cleared_by_operation_id`; leave sweep/undo/outcome tombstone/`attentionDismissAll` to U09 and indicator projection to U10.

STEPS:
1. Port + models for capture token codec and clear result — `attention_clear_port.dart`, extend `attention_models.dart` — red: PG test compile — **yes**
2. Repository: capture SQL + apply with operation insert/members/updates — `attention_clear_repository.dart` — red: eligible predicate + FK reject tests — **yes**
3. `AttentionClearCase` orchestration (authz, idempotent replay) — `attention_clear_case.dart` — red: replay + barrier concurrent arrival PG test — **yes**
4. GraphQL `attentionClear` + snapshot issue field — `mutation_attention.dart`, `query_attention.dart` — red: `attention_graphql_test.dart` — **yes**
5. Injectable wiring — generated `di.config` locally only — red: server unit tests compile — **yes**

TEST_CMD:
```bash
cd /home/vader/MY_SRC/tentura/packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --tags pg -j 1 test/data/repository/attention_clear_operation_pg_test.dart
cd /home/vader/MY_SRC/tentura/packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- dart test test/api/controllers/graphql/attention_graphql_test.dart
```

UNTOUCHABLE: `key.fb`, `leo.key`, `out.key`, `dart-defines`, `.serena/project.yml`, `packages/force_directed_graphview/**`, `docs/plans/constellation-*`, generated files, **all client code**, channel/email path, obligation identity / dispatch, `docs/contracts/updates-event-contract.json`, `attentionDismissAll`/sweep/undo (U09), broad projection changes in `attention_repository.dart` (U10).

RISKS:
- **Feed/summary ignore `cleared_at` until U10** — clearing will not yet change dots/counts in `attentionFeed` / `surfaceSummary` (still `seen_at`-based); tests should assert DB + clear API, not feed omission.
- **Manifest owns vs snapshot issue** — D05 needs capture GraphQL or U13 blocked; amend owns or add query in U08.
- **m0178 COMMENT** on `cleared_by_operation_id` says NULL for explicit/open — implementer should set FK for all operation-backed clears per manifest.
- **`attention_request_state` empty** — capture uses `0/0` until U09/U10 writers; still bind in token.
- **Card `×` outcome tombstone** — product D06 vs U09 owns; avoid half-building sweep outcome logic in U08.
- **Do not use wall-clock** “clear older than tap” — membership-only boundary (collapse history).

---

## UNIT U08 — Clear command (single and open) · INNER (2026-09-19)

**Layer:** inner (Claude Opus 5), tagged **hard** (races). Base `f38913f8d`. Five commits, journal last.
Followed the scout's STEPS and TEST_CMD; the full server suite is the overseer's, and was not run here.

### What landed

| Layer | File |
|---|---|
| Models + token codec | `lib/domain/attention/attention_clear_models.dart` |
| Port | `lib/domain/port/attention_clear_port.dart` |
| Case | `lib/domain/use_case/attention_clear_case.dart` |
| Repository | `lib/data/repository/attention_clear_repository.dart` |
| GraphQL | `mutation_attention.dart` (`attentionClear`), `query_attention.dart` (`attentionClearSnapshot`), `custom_types.dart` |
| Migration | `m0182` (comment only) |
| Tests | `test/data/repository/attention_clear_operation_pg_test.dart` (new, 13 cases), `test/api/controllers/graphql/attention_graphql_test.dart` (+5) |

DI is generated (`di.config.dart`, gitignored): `AttentionClearPort` → `AttentionClearRepository` (singleton),
`AttentionClearCase` (factory), both written by `build_runner`.

### The boundary

**Membership, never wall-clock.** A capture is a finite, ordered list of receipt ids plus the Request's outcome
identity; the apply re-authorizes exactly that list and nothing else. There is no `created_at` comparison
anywhere in this unit, because collapse rewrites `created_at` and "everything older than my tap" is therefore
not a boundary this system can express.

**The token is opaque, not trusted.** Base64url JSON with its own `schemaVersion` (1), deliberately distinct
from the feed cursor's shape so the two can never be fed to each other. It is *not* signed, and does not need
to be: the account inside it is checked against the JWT, and every member is re-checked at apply against
`visible_attention_receipts` plus `NOT requires_action AND cleared_at IS NULL`. Tampering with the member list
can therefore only produce denials — it cannot clear anything the caller could not already clear. This is a
deliberate choice against adding an HMAC secret to `Env` for no additional guarantee; if a later unit needs a
token that is *unforgeable* rather than merely *unhelpful to forge*, that is a one-line change to the codec.

**Idempotency is the primary key.** `INSERT INTO attention_clear_operation … ON CONFLICT (id) DO NOTHING`
inside one transaction. A concurrent twin blocks on that key until the winner commits, then falls through to
the replay path and rebuilds the answer from the stored membership — it never re-captures. The whole apply is
one transaction, so there is no half-applied state for a retry to discover.

**Three outcomes, and why two of them look alike from outside.** `applied` = cleared. `skipped` = a receipt the
account owns but can no longer clear (visibility lost, already cleared, or an obligation). `denied` = an id
that resolves to no receipt *of this account*. A receipt belonging to somebody else and a receipt that never
existed both resolve to nothing, so they are reported identically — that is the non-disclosure property, and
the test asserts the two ids come back in the same list.

### The four races, each asserted with its outcome stated first

| Race | Test | Outcome |
|---|---|---|
| Event arrives between capture and apply | `an event committed after the capture survives the clear` | the new receipt is not a member; `cleared_at IS NULL` |
| Same `operationId` replayed | `a replayed operation id has exactly one effect` | same result, `cleared_at` not re-stamped, one op row, one member row; a receipt that arrived after the first apply is **not** swept up |
| …replayed concurrently | `a concurrently replayed operation id has exactly one effect` (two `TenturaDb` connections, `Future.wait`) | identical results, one op row, `applied = 1` |
| Request leaves the viewer's scope | `a Request that left the viewer scope … is skipped, not cleared` (author blocks viewer mid-operation) | `skipped`, member state `skipped`, status `stale`, nothing cleared |
| Authorization lost / foreign id | `a foreign receipt is denied exactly as a receipt that does not exist`, `a token issued for another account clears nothing` | denied, no clear, and a cross-account token does not even leave an operation row |

### Obligations

Never captured (`NOT requires_action` is in the capture predicate) and never cleared even if forced into a
token by hand (`an obligation forced into a token is skipped, never cleared`). The m0178 CHECK
`notification_outbox__clear_optional_only_chk` is the second line, proven **by name** with a direct offending
`UPDATE` — so if the predicate ever regresses, the database still refuses, and refuses via that constraint.

### Carried-in obligation from U04's verify: discharged

`notification_outbox__cleared_by_operation_fkey` now has a test that names it: an `UPDATE` setting
`cleared_by_operation_id` to an operation id that does not exist is rejected by that FK, and the row is
unchanged afterwards. U08 is the first writer of that column, so this was the first unit that could owe it.

### The three overseer decisions, in my own words

**2 — every clear is operation-backed.** I set `cleared_by_operation_id` on every clear, including explicit and
request-open ones, and shipped `m0182` to correct m0178's comment rather than leave the schema documenting the
opposite. The comment was not merely stale prose: it described a world in which a single-event dismiss has no
operation row, and in that world there is nothing for a replayed `operationId` to find, so D12's idempotency
and U09's undo are both impossible. `legacy_seen` stays the one operation-free reason (U18's backfill has no
operation), which is why the column stays nullable and `notification_outbox__clear_facts_chk` is unchanged.

**3 — `attention_request_state` has no writer yet.** Capture reads `outcome_generation` / `decision_revision`
from that table and gets `0 / 0` for every Request today, because nothing writes it until U09/U10. Both values
are bound into the token and stamped onto every `attention_clear_operation_member` row anyway. Once those
writers exist, the captured generation is what lets U09 notice that the Request's outcome moved *underneath* an
in-flight clear — a clear captured at generation 3 and applied after the outcome advanced to 4 is a different
question from one that never moved — and it is the anchor undo needs to know what it is unwinding. Shipping the
column full of honest zeroes now means the token shape does not change when the meaning arrives.

**6 — the feed does not change yet, and that is not a bug.** `attentionFeed` and `surfaceSummary` still count
`seen_at IS NULL`; `cleared_at` has no effect on any dot or count until U10 moves the indicators onto the
optional axis. So a receipt cleared by this unit is still unread, still counted, still shown. Every test here
asserts the database (`cleared_at`, `clear_reason`, `cleared_by_operation_id`, member rows) and the clear API's
return value — **none** asserts feed omission, and one test (`clearing does not change the read axis yet`)
pins the *absence* of a `seen_at` change explicitly so a later reader cannot mistake the gap for a defect.

### Manifest deviation, disclosed

Per overseer decision 1 I shipped the snapshot-issue query. I named it **`attentionClearSnapshot`**, not the
frozen `attentionRequest` — §0.2 reserves `attentionRequest(beaconId, cursor, limit)` for U10's Request *page*,
and taking that name for a field with a different shape would force U10 to rename or overload it. The frozen
name is untouched and still available.

Two other disclosed touches: `custom_types.dart` gained two result types (additive), and four settle tests in
`attention_graphql_test.dart` selected their field with `.all.last` — adding a mutation silently retargeted
them at `attentionClear`, so they now name the field they mean. No behaviour change.

### Tests actually run

```
# RED — step 2, before the port/case/repository existed
dart test --tags pg -j 1 attention_clear_operation_pg_test.dart   00:00 +0 -1  (compile: Undefined name 'AttentionClearCaptureKind')
# RED — step 3, before the GraphQL fields existed
dart test attention_graphql_test.dart                             00:00 +0 -1  (compile: No named parameter 'clear')
# RED — step 4, before m0182
dart test --tags pg -j 1 attention_clear_operation_pg_test.dart   00:04 +12 -1 (comment still said "NULL for explicit")

# GREEN
dart test --tags pg -j 1 attention_clear_operation_pg_test.dart   00:03 +13: All tests passed!
dart test attention_graphql_test.dart                             00:00 +22: All tests passed!

# Regression, no change expected and none seen
dart test --tags pg -j 1 attention_additive_schema_pg_test.dart   00:05 +25: All tests passed!
dart test --tags pg -j 1 attention_mark_seen_for_beacon_pg_test.dart \
  attention_request_history_pg_test.dart attention_repository_pg_test.dart \
  attention_surface_pg_test.dart                                  00:11 +41: All tests passed!
```

All through `scripts/run_with_test_cleanup.sh`, PG with `--tags pg -j 1`.

### Findings

- **The first commit was green on arrival, and that is the point.** The FK and obligation-CHECK tests needed no
  production code — they prove constraints m0178 already shipped. U04 built them; nothing had ever made them
  fire. A constraint that has never refused anything is a comment.
- **Denied members cannot be recorded.** `attention_clear_operation_member.receipt_id` has an FK to
  `notification_outbox`, so an id naming no receipt cannot be stored. Denials are therefore recomputed on
  replay as *requested ids minus stored members* — which reproduces the first answer exactly for a genuine
  replay, and correctly denies any id a tampered replay tries to add.
- **drift warns about a second `TenturaDb`.** The concurrent-replay test opens a second connection on purpose,
  so the two applies really race in Postgres instead of being serialized by one drift executor. The warning in
  that test's output is expected.

### Out of scope, confirmed untouched

No `attentionDismissAll`, no sweep, no undo, no outcome/tombstone clearing, no shared helper built for U09.
No client code, no contract JSON, no channel/email path, no obligation identity, and no projection change in
`attention_repository.dart` — U10 still owns every read.

---

## UNIT U08 — Clear command (single and open) · VERIFY (2026-09-19)

**Layer:** verify (read-only). Audited commits `05343478f`…`2f8162725` on `UNIT_BASE` `f38913f8d`. Re-ran
focused suites; did not run full server suite.

### Four races — execution audit

| Race | Test | Proves outcome | Fails without impl |
|---|---|---|---|
| Post-capture arrival survives | `an event committed after the capture survives the clear` | `Nu08raceb` uncleared; only `Nu08racea` in `appliedReceiptIds` | Yes — needs `AttentionClearCase` / repo (`05343478f` file had constraints only; apply group added `4138cd77b`) |
| Replay idempotent (serial + concurrent) | `a replayed operation id…`, `a concurrently replayed operation id…` | Same result lists; one op/member row; `cleared_at` not re-stamped; post-replay insert not swept | Yes — same |
| Scope lost → skipped | `a Request that left the viewer scope…` | `skippedReceiptIds`, `stale`, member `state=skipped`, `cleared_at` NULL | Yes — same |
| Auth loss / foreign id non-disclosure | `a foreign receipt is denied…`, `a token issued for another account…`, scope test via `user_block` | Foreign + ghost both `denied`; cross-account `denied` with **0** operation rows; blocked forward skipped not cleared | Yes — same |

Concurrent replay uses a second `TenturaDb` connection (expected drift warning).

### Judgement calls

| Call | Verdict | Evidence |
|---|---|---|
| Unsigned token OK | **Accept** | JWT binds `accountId` in case (`attention_clear_case.dart:65–74`); apply re-checks `visible_attention_receipts` + ownership (`attention_clear_repository.dart:133–181`). PG: tampered token with `Nu08theirs` + `Nu08ghost` → denied, not cleared; cross-account capture token under stranger JWT → `denied`, no storage. **No P0 break found.** |
| Denied ids not stored; replay recomputes | **Accept** | Members only for applied/skipped (`:186–205`); `_replay` denied = `requestedIds − stored` (`:314–317`). Serial replay test matches first result exactly. **Gap (test debt only):** no PG case that replays with a **strictly larger** token membership; code review says extras land in `deniedReceiptIds` without `UPDATE`. |
| `attentionClearSnapshot` not `attentionRequest` | **Accept** | Query field `attentionClearSnapshot` only; comment defers `attentionRequest` to U10 (`query_attention.dart:36–39`). No `attentionRequest` GraphQL field added. |

### Other acceptance checks

- **FK by name:** `notification_outbox__cleared_by_operation_fkey rejects an unknown operation id` — `ServerException.constraintName` assertion; row stays uncleared.
- **Obligation CHECK by name:** `notification_outbox__clear_optional_only_chk` on forced obligation UPDATE.
- **No wall-clock boundary:** capture is membership; apply `UPDATE` uses `id IN (...)` only; `now()` stamps `cleared_at`, not eligibility.
- **U10 gap pinned:** `clearing does not change the read axis yet` asserts `seen_at` still NULL after clear.
- **GraphQL `.all.last` fix:** four `attentionSettle` tests + auth test now `singleWhere(… == 'attentionSettle')`; resolve bodies/assertions unchanged vs `f38913f8d` (pre-U08 `.all.last` targeted settle because it was the last mutation).
- **Scope:** `git diff f38913f8d..2f8162725` — 12 server files only; no client, contract, `attention_repository.dart`, dismiss/undo APIs.
- **Untouchables:** four pre-existing modified paths unchanged by U08 diff; secrets not in commits.

### Tests run (verifier)

```
dart test --tags pg -j 1 test/data/repository/attention_clear_operation_pg_test.dart   → +13
dart test test/api/controllers/graphql/attention_graphql_test.dart                       → +22
```

Both via `scripts/run_with_test_cleanup.sh`.

STATUS: pass

TEST_OUTPUT: `dart test --tags pg -j 1 attention_clear_operation_pg_test.dart` — 13 passed; `dart test attention_graphql_test.dart` — 22 passed

ACCEPTANCE: four races — met — PG tests above; FK/CHECK by name — met — constraint group; no wall-clock boundary — met — code + race test; U10 seen_at gap — met — `clearing does not change the read axis yet`; unsigned token — met — PG + case/repo; denied replay semantics — met — code + serial replay test (expanded-token replay untested); naming — met — `attentionClearSnapshot` only; no U09/client/contract/projection — met — diff; GraphQL retarget fix — met — diff review; focused commits — met — five commits; untouchables — met — worktree status

GAPS: none (product). Optional test debt: PG case for replay with same `operationId` but token carrying **additional** receipt ids (behaviour asserted by `_replay` code, not executed in tests). No PG fixture for unanswered-forward / pending-prompt **capture exclusion** (product relies on visibility + optional predicate; inbox decision rows are U09 sweep concern).

---

## UNIT U08 — replay cannot widen its reach · INNER (remediation) (2026-09-19)

**Layer:** inner (remediation). `UNIT_BASE` `2f8162725`. One gap, one test file touched, one commit.

### The gap

U08's verify accepted "denied ids are not stored; `_replay` recomputes them" on code reading alone, and flagged
the one thing no PG case executed: a replay of a known `operationId` carrying a **larger** token membership than
the original. That is security-adjacent — if a replay could expand what it clears, anyone who observed an
operation id could clear rows the first call never captured.

### Outcome: **coverage gap, not a hole**

The behaviour was already correct on current code. Two cases added to
`test/data/repository/attention_clear_operation_pg_test.dart` (13 → 15):

- `a replayed operation id cannot clear a receipt the first apply never captured` — clear `{A, B}` under
  `OPu08expand`, then replay the **same** id with a hand-built token `{A, B, C}` where `C` is a receipt the very
  same caller could legitimately clear in a *new* operation. Asserts `C.cleared_at IS NULL`, applied/skipped
  identical to the first answer, `A.cleared_at` not re-stamped, one operation row, and the stored membership
  still exactly `{A, B}`.
- `a replayed operation id with a smaller membership still returns the first answer` — replay with `{A}`;
  the answer is the first answer, not a narrowed one, and membership is still 2.

**One honest nuance, asserted rather than smoothed over:** the widened replay is not byte-identical to the first
answer. Applied and skipped are reproduced exactly, but the added id comes back in `deniedReceiptIds` and the
status therefore moves `complete` → `partial`. That is the caller being told their extra id was refused, which
is the right answer; the test pins it with a reason so a future reader does not read the difference as drift.

### Proving the tests bite

Passed on arrival, so the mutation was the evidence. Temporarily disabled the short-circuit into `_replay`
(`if (inserted == 0)` → guarded by a probe constant), which is exactly the defect class in question — a replay
that re-applies from the token instead of from stored membership:

```
dart test --tags pg -j 1 attention_clear_operation_pg_test.dart   00:04 +11 -4: Some tests failed.
  a replayed operation id cannot clear a receipt the first apply never captured [E]
    Expected: null                       <- Nu08expandc.cleared_at
      Actual: DateTime:<2026-09-19 04:37:25.032392Z>
  a replayed operation id with a smaller membership still returns the first answer [E]
    Expected: ['Nu08shrinka', 'Nu08shrinkb']
      Actual: []
```

Both new cases fail on the mutation, and the expanded one fails on the security assertion itself — `C` really
does get cleared when `_replay` is bypassed. The two pre-existing replay tests fail too, as expected.

Mutation reverted; `git diff packages/server/lib` is empty (0 files).

### Green

```
dart test --tags pg -j 1 test/data/repository/attention_clear_operation_pg_test.dart  00:04 +15: All tests passed!
dart test test/api/controllers/graphql/attention_graphql_test.dart                     00:00 +22: All tests passed!
```

Both through `scripts/run_with_test_cleanup.sh`. Full server suite not run — the overseer owns it.

STATUS: complete

### Manager verdict — U08 · **ACCEPTED** (hard; scout ✓ / inner Opus-low ✓ / verify pass / one remediation)

Overseer's full server suite: **1676 non-PG**, **870 PG / 24 known skips**. Commits `05343478f` ·
`4138cd77b` · `b6b39c949` · `3d3a8055e` (m0182) · `2f8162725` · `c06bbdb9d` (remediation).

**All four races carry a stated-in-advance outcome and a test that proves it**: an event arriving between
capture and apply survives; a replayed operation id — including concurrently — has exactly one effect; a Request
that leaves scope mid-operation is *skipped and reported*, not cleared; and a lost authorization clears nothing
without disclosing whether the row exists.

**The verifier tried to break the unsigned snapshot token and could not.** The inner layer's argument was that
forging a member list can only produce denials, because the token's account is checked against the JWT and every
member is re-authorized at apply. Cross-account tokens deny with **zero** operation rows; a tampered obligation
in the token is skipped, not cleared. The decision is recorded as reversible — signing is a one-line codec
change if a later unit needs unforgeability rather than uselessness-to-forge.

**Remediation closed a security-adjacent coverage gap.** Nothing proved that a replay cannot *widen* what it
clears — an observer who learned an operation id could otherwise have cleared rows the original never captured.
The new test passes on current code (coverage gap, not a hole) and was proven to bite: disabling `_replay`'s
short-circuit leaves the added receipt with a non-null `cleared_at`. Reverted, `git diff packages/server/lib`
empty. Honest nuance reported rather than smoothed: a widened replay is **not** byte-identical — applied and
skipped reproduce exactly, but the extra id comes back in `deniedReceiptIds` and the status moves
`complete → partial`, which is the caller being told, not a silent no-op.

**Two judgement calls I endorse:** the snapshot field is `attentionClearSnapshot`, deliberately *not* the frozen
`attentionRequest` that §0.2 reserves for U10's Request page — no frozen name was squatted; and denied ids are
not stored (the member table's FK forbids it), so denials are recomputed on replay as requested-minus-stored.

**A pre-existing test defect found in passing:** four settle tests selected their GraphQL field with
`.all.last`, so adding a mutation silently retargeted them onto `attentionClear` — they had been passing for the
wrong reason. They now name their field, with assertions unchanged.

**Deliberate gap, pinned by a test so it cannot be misread:** clearing does not move `seen_at`, dots or counts
yet. `attentionFeed` and `surfaceSummary` still read the read-axis; U10 moves them onto the optional axis.

**Overseer decisions recorded:** the snapshot-issue query ships here (without it D05 is unimplementable and U13
is blocked), and m0182 corrects m0178's `COMMENT`, which claimed `cleared_by_operation_id` is NULL for explicit
and open clears — every clear is operation-backed, which is what makes replay idempotent and U09's undo possible.

---

## UNIT U09 — Outcomes, sweep, undo · SCOUT BRIEF (2026-09-19)

**Layer:** scout (read-only). **Base:** `062c4e872` (U08 accepted). **Tag:** hard.

### Live baseline (what U08 already gives U09)

| Piece | Location | Reuse for U09 |
|---|---|---|
| Operation header + counters | `attention_clear_operation` (`m0178`) | Same table; `surface` = `'activity'` (or frozen string) for sweep; set `undo_deadline` on first commit |
| Fixed membership + replay | `attention_clear_operation_member` + `AttentionClearRepository._replay` | Same idempotency story (`INSERT … ON CONFLICT DO NOTHING` on op id; membership never extended) |
| Optional receipt clear | `UPDATE notification_outbox SET cleared_at, clear_reason='sweep', cleared_by_operation_id` | Same apply primitive; U08 uses `explicit` / `request_open` |
| Capture predicate (receipts) | `AttentionClearRepository._eligibleReceipts` | **Subset** of sweep receipt members: activity-surface optionals only (see SQL below) |
| Token capture | `AttentionClearSnapshotToken` + `captureEligible` | **Single-Request / finite list only** — sweep does **not** use this token; server-side capture at `attentionDismissAll` start |
| Outcome identity (read) | `attention_request_state.outcome_generation`, `decision_revision` | Read at capture; **U09 is first writer** — must bump `decision_revision` on inbox stance transitions and maintain `outcome_generation` when the visible outcome identity changes |
| Outcome hide (read path) | `inbox_item.tombstone_dismissed_at` + `dismissed_tombstone` CTE in `attention_repository.dart:286–291` | Feed already hides dismissed **closed/deleted** tombstones; trigger `inbox_item_guard_tombstone` **only allows** `tombstone_dismissed_at` when `status IN (3,4)` (`m0024.dart:44–47`) — **blocks helping/watching/notInterested dismissal today** |
| Client tombstone dismiss | Hasura `InboxTombstoneDismiss` → `update_inbox_item` (`inbox_tombstone_dismiss.graphql`) | **Not** a v2 attention mutation; U09 should add **server** dismiss path (D11) — client wiring is U16 |
| `attentionDismissAll` / `attentionUndo` | — | **Not implemented** (manifest §0.2 names only) |

**U08 vs sweep — what generalises, what must differ**

| Concern | U08 `attentionClear` | U09 sweep |
|---|---|---|
| Capture | Client-held token; ≤500 receipt ids (`maxMembers`) | **Server** scans full authorized **activity** surface (no page cursor); may exceed 500 → **batched member insert + batched apply** |
| Members | Receipt ids only | **Two member kinds:** (1) optional `notification_outbox` rows, (2) **outcome rows** keyed by `beacon_id` (synthetic `inbox:<beacon_id>` stream items) |
| Scope | One `beaconId` (or one receipt) | All dismissible attention on surface; **skip** My Desk–owned Requests' obligations and **unanswered** pinned forwards |
| `surface` column | `explicit`, `request_open`, or `beacon:<id>` | Constant e.g. `activity` for dismiss-all |
| Resume | Single transaction today | **Required:** re-enter by `operationId`; process members in `pending`/`failed` batches; counters `applied/skipped/failed` authoritative |
| Outcome clear | **Not applied** in U08 | Must clear captured **outcome generation** per Request (D07), not only receipts |

### Owner decision A in SQL — “rows that carry their own ×”

Express as the **union** of two dismissible sets minus hard exclusions. This is the safety margin; implement as one shared SQL function or CTE used by **capture**, **apply re-check**, and (later U10) **eligibility** — do not fork predicates.

**Shared prelude** (mirror `attention_repository.dart` `_visibleWithSurfaceCte` + `_activityGroupingCtes`):

- `visible` = authorized receipts + `surface` (`myWork` vs `activity`) via `responsibility_scope_base_beacons` + live obligations in `scope`.
- `eligible_pinned` = **unanswered forward awaiting decision** = `inbox_item` with `status = 0`, `tombstone_dismissed_at IS NULL`, `beacon_id NOT IN scope`, readable (`attention_repository.dart:246–254`).

**Set R — dismissible optional receipts (receipt axis)**

```sql
-- Pseudonym: activity_optional_dismissible
SELECT o.id AS receipt_id, o.beacon_id
FROM visible v
JOIN notification_outbox o ON o.id = v.id
WHERE v.surface = 'activity'
  AND NOT o.requires_action
  AND o.cleared_at IS NULL
  -- Exclude synthetic forward shell: relay_received rows are inbox-synthesized, not outbox
  AND o.presentation_key IS DISTINCT FROM 'relay_received'
```

Includes: standalone activity receipts (`beacon_id IS NULL`), child optional events on grouped cards, profile/network optionals on For You, timeline-only items that surface on activity. **Excludes:** all obligations (`requires_action`), anything already `cleared_at`.

**Set O — dismissible outcome tombstones (inbox axis, decision B)**

```sql
-- Pseudonym: activity_outcome_dismissible
SELECT ii.beacon_id,
       COALESCE(ars.outcome_generation, 0) AS outcome_generation,
       COALESCE(ars.decision_revision, 0) AS decision_revision
FROM inbox_item ii
JOIN … -- same visibility rules as eligible_forward (attention_repository.dart:255–279)
LEFT JOIN attention_request_state ars
  ON ars.account_id = ii.user_id AND ars.beacon_id = ii.beacon_id
WHERE ii.user_id = $account
  AND ii.tombstone_dismissed_at IS NULL
  AND ii.beacon_id NOT IN (SELECT beacon_id FROM eligible_pinned)  -- NOT unanswered forward
  AND (
    ii.beacon_id IN (SELECT beacon_id FROM scope)           -- helping (status 0 in scope)
    OR ii.status IN (1, 2, 3, 4)                            -- watching, notInterested, terminals
  )
```

**Hard exclusions (never in capture, never cleared on apply even if tampered into a token)**

| Exclusion | SQL / rule |
|---|---|
| Unanswered forward | `beacon_id IN eligible_pinned` |
| Live obligation receipts | `requires_action AND settlement_kind IS NULL` |
| Request now My Desk–owned | At apply: `beacon_id IN scope` ⇒ **skip** optional clears that would hide work owned on My Desk (D07: “Request now owned by My Desk — skip”) — *optional* receipts on that beacon may still be skipped as a unit with the card |
| Pending prompt (no ×) | **No dedicated prompt row in `attention_repository.dart` today.** Until classified events exist, predicate is “nothing that is `requires_action` or `eligible_pinned`.” When prompts ship, contract must mark them `clearPolicy: forbidden` and they fall out of Set R automatically |

**Predicate precision:** The margin between unanswered forward and answered outcome is **exactly** `eligible_pinned` vs `eligible_forward` minus pinned. If a beacon is both “needs me” (`status=0`, not in scope) and has optional child receipts, only the **forward row** is non-dismissible; card optionals remain in Set R.

**Watching digest** (`watching-digest` item, `attention_repository.dart:465–515`): not a separate stance change; dismissible members are the **underlying uncleared optional receipts** on watching beacons (Set R), not the digest shell id.

### `tombstone_dismissed_at` vs `cleared_at` — keep both axes

| Axis | Stores | Used for |
|---|---|---|
| `notification_outbox.cleared_at` | Optional **receipt** attention (D02) | Event ×, card optional set, network optionals, sweep receipt members |
| `inbox_item.tombstone_dismissed_at` | **Outcome row** hide (presentation trace of inbox stance) | Answered-forward tombstones in stream SQL |

**Do not** move outcome dismissal onto `cleared_at` — there is no outbox row for `inbox:<beacon_id>`. Sweep must **commit both** in one operation per Request batch: receipt clears + outcome dismiss for captured beacon ids.

**Migration required:** relax `inbox_item_guard_tombstone` so `tombstone_dismissed_at` can be set for **all** outcome statuses in Set O (not only 3/4). Index `ii_user_tombstone_visible` may need widening (currently `status IN (3,4)` only, `m0024.dart:136–138`).

### `attention_request_state` — first writer (U09) vs U10

| Field | U09 responsibility | U10 consumption |
|---|---|---|
| `outcome_generation` | Bump when visible outcome identity changes (stance transition, terminal tombstone, new forward generation that replaces outcome row). Capture stores generation on each outcome member; apply dismisses only if live generation **equals** captured | Dot / “uncleared outcome” predicate (D09) |
| `decision_revision` | Bump on every inbox **decision** (`setStatus`, restore, help-offer path that changes forward stance). Undo/skip if live revision ≠ captured | Conservative undo + “someone else decided” detection |
| `first_entry_at` | May **lazy-init** on first For You appearance or first state write; stable ordering anchor | D08 ordering — **U10 owns sort keys**, but needs this column populated |

U09 does **not** rewrite `attention_repository.dart` feed projections (UNTOUCHABLE for indicator work); it **must** still write state so U10 predicates and undo have data. Tests assert DB + mutations; feed omission for outcomes can be tested via existing `attention_activity_stream_pg_test.dart` patterns once dismissal works for status 1/2/helping.

### Operation members without a receipt — manifest tension

`attention_clear_operation_member.receipt_id` is **NOT NULL** with FK → `notification_outbox` (`m0178`). Outcome-only members have **no** receipt id. **Stop-and-amend §0.1** unless implementer chooses one of:

1. **Recommended:** amend member table: nullable `receipt_id`, add `member_kind` (`receipt` \| `outcome`), CHECK one of (`receipt_id`, `beacon_id`) for outcomes, partial unique `(operation_id, beacon_id)` for outcome members.
2. **Alternative:** store outcome undo only on `attention_request_state` + operation audit json — **conflicts** with frozen member shape.

Denied ids stay **unstored** (U08); outcome members use `beacon_id` + generations on the member row.

### Undo (D13) — what to store; do not use `markUnseen`

**Window:** set `attention_clear_operation.undo_deadline` = now() + 30s on first successful apply (server-enforced).

**Restore payload per member kind:**

| Kind | Apply | Undo (if guards pass) |
|---|---|---|
| Receipt | Sets `cleared_at`, `clear_reason`, `cleared_by_operation_id` | `cleared_at/clear_reason/cleared_by_operation_id` → NULL **only if** `cleared_by_operation_id = operationId` and receipt still visible + optional |
| Outcome | Sets `inbox_item.tombstone_dismissed_at` | Set `tombstone_dismissed_at` → NULL **only if** `decision_revision` and `outcome_generation` still match member snapshot |

**Guards (skip member, report partial):** authorization lost; live `decision_revision` ≠ captured; live `outcome_generation` ≠ captured for outcomes; another operation cleared the same receipt; obligation settled; domain transition (help accepted elsewhere, review submitted, terminal state change).

**`markUnseen`** (`attention_repository.dart:1182–1222`) is the **read** axis and refuses when an unseen sibling shares `dedup_key`. **Wrong tool for undo** after U05a immutable receipts — undo must reverse **`cleared_*`**, not `seen_at`. Do not call `markUnseen` from undo.

**Undo token:** return opaque `undoToken` bound to `operationId` + account (same philosophy as snapshot token: bind account, do not trust client).

### Extend U08 apply path vs new case

- **Single outcome dismiss** (replaces Hasura for D11): extend `AttentionClearPort` / repository with `captureOutcome(beaconId)` + apply branch, or `attentionClear` token with **empty `receiptIds`** but `beaconId` + generations — must still write operation + members.
- **`attentionDismissAll(surface, operationId)`:** new case method: phase 1 capture all Set R ∪ Set O into operation + members (chunked); phase 2 batch apply with per-beacon recheck; return `{applied, skipped, failed, status, undoToken?, undoDeadline?}`; resume if header exists.
- **`attentionUndo(operationId, undoToken)`:** reverse eligible members only.

GraphQL: `mutation_attention.dart` + types in `custom_types.dart` / `query_attention.dart` for progress poll if needed.

Wire **`decision_revision` bumps** into server inbox write paths (`inbox_repository.setStatus`, forward/help flows) — otherwise undo cannot detect Restore / re-pin.

### Race scenarios — observable outcomes

| Scenario | Outcome |
|---|---|
| Forward **answered** after capture listed unanswered forward | **Impossible** if capture excludes `eligible_pinned` — forward was not a member |
| Forward **answered** after capture listed outcome tombstone | At apply, outcome generation/revision changed → **skip** outcome member; pinned forward **appears** (correct) |
| **Restore** notInterested during sweep | `decision_revision` bump → outcome member **skipped**; restore stands |
| Request gains **My Desk** responsibility during sweep | Receipt/outcome members for that beacon **skipped** at apply (D07) |
| New optional receipt after capture | Not in membership → **stays uncleared** |
| Resumed sweep after timeout | **Same** membership; ineligible members → `skipped`; never extend set |
| Undo after another device cleared same receipt | `cleared_by_operation_id` ≠ op → **skip** receipt |
| Undo after another user’s stance change | revision mismatch → **skip** outcome |
| Undo after expired deadline | **Denied** whole or per-member |

### TEST_CMD (implementer — affected suites only)

```bash
cd /home/vader/MY_SRC/tentura/packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 25m -- \
  dart test --tags pg -j 1 \
    test/data/repository/attention_clear_operation_pg_test.dart \
    test/data/repository/attention_dismiss_sweep_pg_test.dart

cd /home/vader/MY_SRC/tentura/packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- \
  dart test --tags pg -j 1 test/data/repository/attention_activity_stream_pg_test.dart

cd /home/vader/MY_SRC/tentura/packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- \
  dart test test/api/controllers/graphql/attention_graphql_test.dart
```

(`attention_dismiss_sweep_pg_test.dart` — **new** — sweep ≥3 pages, all outcome kinds, resume, undo conflicts; extend clear PG suite for outcome dismiss + undo.)

Overseer runs full server suite independently.

### UNTOUCHABLE (scout)

`key.fb`, `leo.key`, `out.key`, `dart-defines`, `.serena/project.yml`, `packages/force_directed_graphview/**`, `docs/plans/constellation-*`, generated files, **all client code** (U16), channel/email path, obligation identity / dispatch, `docs/contracts/updates-event-contract.json`, **indicator/projection rewrites** in `attention_repository.dart` (U10) — U09 may add **outcome dismissal side effects** and shared SQL helpers **outside** that file or via migration/trigger only.

---

## UNIT U09a — dismissible foundations · INNER (2026-09-19)

**Layer:** inner (implementer), tagged hard. `UNIT_BASE` `19fd71abd`. Scope: the scout brief's steps 1–4 only.
No sweep, no `attentionDismissAll`, no undo, no GraphQL — those are U09b and U09c.

### What landed

| Step | Commit | What |
|---|---|---|
| 1 + overseer addition 4 | `68b170d48` | **m0183** — the tombstone guard stops restricting `tombstone_dismissed_at` to statuses 3/4; `attention_clear_operation_member` takes an outcome instead of a receipt |
| 2 | `c3408619d` | `attention_dismissible_sql.dart` — the one "rows that carry their own ×" predicate |
| 3 | `83605cd56` | **m0184** — `attention_request_state` acquires its first writer, as a trigger |
| journal | this entry | |

### Step 1 — the defect was in the database, not the client

The scout was right and it is worth restating plainly: `inbox_item_guard_tombstone` (m0024) refused any write to
`tombstone_dismissed_at` unless `status IN (3, 4)`. So `helping` (0, in scope), `watching` (1) and
`notInterested` (2) could not be dismissed **at all** — not "the client has no × yet", but "the write is
rejected". The earlier plan text describing the mechanism as present-but-unwired was true only for
`closed`/`deletedBeforeResponse`. m0183 removes the status list and says in its comment why the old restriction
was wrong, so nobody restores it while "tidying".

What the guard still refuses is unchanged, and the tests name each refusal: a tombstone row may not change
`status` or `rejection_message` (even with the beacon trigger's flag borrowed — the freeze rule fires first);
a row may not be inserted into, or transitioned into, a tombstone status without that flag. Dismissal is a
presentation fact; stance transitions stay the beacon trigger's business.

m0183 also adds `ii_user_outcome_undismissed (user_id, status) WHERE tombstone_dismissed_at IS NULL`, because
the m0024 index only covers statuses 3/4 and the new predicate scans every status of one viewer. The old index
stays — it still serves the tombstone card's `before_response_terminal_at` ordering.

### Overseer addition 4 — §0.1's amended member shape

`attention_clear_operation_member` gained `outcome_beacon_id`, `receipt_id` became nullable, and
`attention_clear_operation_member__member_target_chk` requires `num_nonnulls(receipt_id, outcome_beacon_id) = 1`
— proved by name in both directions, neither set and both set.

Two consequences worth knowing before U09b:

- **The primary key had to go.** A PK column cannot be nullable, so `(operation_id, receipt_id)` is replaced by
  two partial UNIQUE indexes, `__receipt_once` and `__outcome_once`. The capture-once guarantee is identical;
  only the constraint enforcing it is renamed. U08's member insert therefore now names the index predicate in
  its `ON CONFLICT (…) WHERE … IS NOT NULL` — without that the whole U08 suite fails to infer an arbiter, which
  is how I found it. One assertion in `attention_additive_schema_pg_test.dart` moved to the new name.
- **`outcome_beacon_id` is deliberately not a foreign key**, for the same reason the existing `beacon_id`
  snapshot is not: the operation audit and its counters must survive deletion of the Request. `ON DELETE
  CASCADE` would silently delete members and make the counters lie; `ON DELETE SET NULL` would violate the new
  CHECK. Undo of a member whose Request is gone has nothing to restore and is skipped. **Flagging this as a
  judgement call** in case the overseer meant a literal FK.

### Step 2 — the predicate, and what the test had to do to be worth anything (addition 2, in my own words)

`AttentionDismissibleSql` (in `data/repository/`, **not** in `attention_repository.dart`, which U10 owns) holds
three SQL fragments: a `prelude` (visibility, responsibility scope, surface, `eligible_pinned`), **Set R**
`activity_optional_dismissible` and **Set O** `activity_outcome_dismissible`. U09b composes these; it must not
write its own copy, because owner decision A is only as strong as the *weakest* place the question gets asked,
and capture, apply re-check and button-eligibility are three places.

Proving an exclusion is harder than proving an inclusion: a test that asserts "the obligation is absent" passes
just as happily when the predicate has been deleted and the set is empty for some unrelated reason. So each
exclusion is asserted twice — the row is absent from the real predicate, and a **deliberately loosened copy**
(the exact string a careless refactor would leave behind) puts it back. The loosened assertion is what fails if
someone widens the predicate.

Two findings came out of insisting on that:

- **An obligation on a Request is excluded twice over.** The first version of the obligation test failed its
  loosened half: deleting `NOT requires_action` still did not admit the row, because a live obligation puts its
  Request into the responsibility scope, so the surface filter rejects it anyway. Defence in depth, but it
  means a beacon-scoped obligation proves nothing about the obligation exclusion itself. The load-bearing case
  now uses a **Request-less** obligation (profile axis), and the double exclusion is a separate, explicitly
  named test.
- **Forwarding already creates the inbox row** (`inbox_item_on_forward_insert`), so fixtures set a stance on the
  row that is there rather than inserting one.

For Set O, `NOT IN eligible_pinned` is written as the single load-bearing exclusion rather than the
projection's `status <> 0 OR beacon_id IN scope`. For rows that pass the readability clause the two are
equivalent, and stating it as the pinned-zone exclusion is what makes both the intent and its test legible —
deleting that line is what the loosened test detects.

**Pending prompts, and exactly what will need revisiting.** There is no prompt row in the feed today — no
`inbox_item` status and no `presentation_key` corresponds to "pending invite / setup prompt". So the predicate
cannot exclude prompts by name, and it does not pretend to: "awaits a decision" is expressed entirely as two
exclusions, unanswered forwards (Set O) and obligations (Set R). **When prompts gain a live row they will not
fall out of these predicates by themselves.** Whatever carries them has to be excluded explicitly: if a prompt
arrives as a `notification_outbox` receipt it will be optional and uncleared and will therefore land in Set R
unless its `presentation_key` is excluded there, or the contract marks it `clearPolicy: forbidden` and the
predicate learns to read that. This is written in the class doc too, not only here.

### Step 3 — what the two counters mean and who reads them next (addition 3, in my own words)

`outcome_generation` and `decision_revision` had no writer; every reader coalesced them to 0. Undo is *defined*
against them, so until now U09c was undefined.

- **`decision_revision` — "the viewer decided something."** Bumped when `status` changes, or the
  `rejection_message` that carries a decision changes. **U09b** skips a member whose Request was decided between
  capture and apply; **U09c** refuses an undo whose stance moved underneath it; **U10** has no direct use but
  inherits the honesty of the field.
- **`outcome_generation` — "the visible outcome row is a different row now."** Every decision, plus a new
  forward generation (`latest_forward_at` advancing, which replaces the outcome row's content), plus arrival of
  a before-response terminal state. **U09b** captures it per outcome member; **U09c** compares it before
  restoring; **U10** reads it for the "uncleared outcome" predicate (D09).
- **`first_entry_at`** is lazily initialised on the viewer's first inbox row for a Request. U10 owns the sort
  keys; this only guarantees the column is populated.

**`tombstone_dismissed_at` bumps neither, on purpose:** a sweep that bumped the generation would refuse to undo
itself. There is a test with exactly that name.

**Why a trigger rather than a repository method.** This is the part I would most want a reviewer to check.
`InboxRepository.setStatus` has **no server-side caller at all** — the client changes stance through Hasura
(`update_inbox_item`), which is also how **Restore** works; the m0024/m0097 beacon trigger writes terminal
statuses in pure SQL; `inbox_item_apply_tombstone_after_withdraw` likewise. A Dart-level writer would have
missed precisely the transition undo cares about most. m0184 puts an `AFTER INSERT OR UPDATE` trigger on
`inbox_item` so every writer is seen. Two tests pin the paths Dart cannot reach: Restore through a bare
`UPDATE`, and a terminal status produced by updating `beacon.status`.

### Addition 5 — the two axes stay separate, and why

`notification_outbox.cleared_at` and `inbox_item.tombstone_dismissed_at` remain **different axes**, and this
unit did not merge them. The reason is structural, not stylistic: there is no `notification_outbox` row for an
outcome. An outcome row is synthesised from `inbox_item` by the feed projection; `inbox:<beacon_id>` is not a
receipt id and has no receipt to carry a `cleared_at`. Moving outcome dismissal onto the receipt axis would mean
manufacturing receipts for outcomes, which is a design change — and per the overseer's instruction it belongs in
a decision, not in a step. I am not proposing it.

What this unit did instead is make **one operation able to span both axes**, which is what U09b needs: the
member table now holds receipt members (`receipt_id`) and outcome members (`outcome_beacon_id`) side by side
under one `attention_clear_operation`. A sweep therefore captures Set R ∪ Set O into one operation and commits
receipt clears and outcome dismissals per Request batch — one operation id, one undo, two axes. Nothing in this
unit forces U09b to make two passes or two operations.

### Addition 6 — the feed is unchanged, deliberately

No projection was touched. `attentionFeed` and `surfaceSummary` still read the read-axis; U10 moves them. Every
assertion in this unit is on database or predicate state — `tombstone_dismissed_at`, constraint names, counter
values, predicate membership — and never on "the dot went away". The existing
`attention_activity_stream_pg_test.dart` (26 tests) passes unchanged, which is the evidence that the feed did
not move.

### Tests actually run

```
# RED — step 1 + addition 4, with m0183 unregistered from the migration list
dart test --tags pg -j 1 attention_outcome_dismissible_pg_test.dart     00:02 +7 -8: Some tests failed.
  (helping/watching/notInterested dismissal + un-dismissal + all four member-shape cases)
  e.g. "column \"outcome_beacon_id\" of relation \"attention_clear_operation_member\" does not exist"

# RED — step 2, before attention_dismissible_sql.dart existed (file moved aside)
dart test --tags pg -j 1 attention_dismissible_predicate_pg_test.dart   00:00 +0 -1: compile: Undefined name 'AttentionDismissibleSql'

# RED — step 3, with m0184 unregistered
dart test --tags pg -j 1 attention_request_state_writer_pg_test.dart    00:01 +0 -7: Some tests failed.

# RED found by the migration itself, not by me: U08's member insert
dart test --tags pg -j 1 attention_clear_operation_pg_test.dart         00:0x +5 -10  (no arbiter for ON CONFLICT)

# GREEN
dart test --tags pg -j 1 attention_outcome_dismissible_pg_test.dart     00:02 +15: All tests passed!
dart test --tags pg -j 1 attention_dismissible_predicate_pg_test.dart   00:02 +12: All tests passed!
dart test --tags pg -j 1 attention_request_state_writer_pg_test.dart    00:01  +7: All tests passed!

# GREEN — every affected suite together (the scout's list plus the three new files)
dart test --tags pg -j 1 \
  attention_outcome_dismissible_pg_test.dart attention_dismissible_predicate_pg_test.dart \
  attention_request_state_writer_pg_test.dart attention_clear_operation_pg_test.dart \
  attention_activity_stream_pg_test.dart ../database/attention_additive_schema_pg_test.dart \
  attention_repository_pg_test.dart attention_surface_pg_test.dart \
  attention_request_history_pg_test.dart attention_mark_seen_for_beacon_pg_test.dart
                                                                        00:33 +137: All tests passed!
dart test attention_graphql_test.dart                                   00:00 +22: All tests passed!
./scripts/check-custom-lints.sh packages/server                         total: 0 (baseline: 0) — OK
```

All through `scripts/run_with_test_cleanup.sh`, PG with `--tags pg -j 1`. Full server suite not run — the
overseer owns it.

### Findings

- **The migration found a live caller before any test did.** Dropping the member primary key broke U08's
  `ON CONFLICT (operation_id, receipt_id)` arbiter inference — Postgres will not infer a *partial* index unless
  the statement repeats its predicate. Ten U08 tests went red on the first run after m0183 and were green again
  once the insert named `WHERE receipt_id IS NOT NULL`. This is a good argument for keeping the U08 suite in
  every U09 run.
- **`beacon.state` does not exist; it is `beacon.status`** (renamed before m0097, and the tombstone trigger
  moved with it). The scout brief and m0024's original text both say `state`.
- **A Request-less obligation needs the `profile` access policy** to be visible at all —
  `visible_attention_receipts` admits a beacon-less receipt only under `profile` with
  `destination_kind = 'profile'` and a `mutual_connection_formed` / `invite_accepted` presentation key. Anything
  else with `beacon_id IS NULL` is invisible, and `beacon_content` with a null beacon violates
  `notification_outbox__beacon_policy_chk`.
- **`AttentionDismissibleSql.prelude` duplicates `AttentionRepository`'s private `_visibleWithSurfaceCte`.** The
  duplication is deliberate — that file is U10's and private — but it is real, and the two must be unified once
  U10 settles, behind the shared name, since the shared copy is the authorization-critical one.

### Out of scope, confirmed untouched

No `attentionDismissAll`, no sweep, no undo, no GraphQL change, no client code. No Hasura tombstone-dismiss path
(it stays parallel until U16). No projection change in `attention_repository.dart`, no contract JSON, no
channel/email path, no obligation identity. The only non-test production file outside a migration is the shared
SQL helper, plus the one-line `ON CONFLICT` arbiter fix m0183 forced in `attention_clear_repository.dart`.

STATUS: complete

---

## UNIT U09a — dismissible foundations · VERIFY (2026-09-19)

**Layer:** verify (read-only). **Base:** `19fd71abd`. **Commits adjudicated:** `68b170d48` · `c3408619d` ·
`83605cd56` · `6d622aa07`.

### Execution

Re-ran the coupled PG suites (U08 clear + U09a predicate/outcome/state + additive schema membership rename):
**74 passed, 0 failed** (~22s). Independently confirmed `InboxRepository.setStatus` has **no** caller under
`packages/server/lib/domain` or `lib/data` except its definition; stance/Restore paths are Hasura `UPDATE
inbox_item` and SQL triggers, covered by `attention_request_state_writer_pg_test.dart`.

### Adjudication notes

1. **m0183 dismissibility vs safety:** DB now permits `tombstone_dismissed_at` on all five outcome statuses
   (tests `attention_outcome_dismissible_pg_test.dart`). Guard still blocks forged stance transitions. **Sweep
   safety** is not the trigger anymore — it is `AttentionDismissibleSql` (`eligible_pinned` exclusion). Residual:
   Hasura can still set `tombstone_dismissed_at` on an unanswered `status=0` row if permissions allow; predicate
   excludes it from Set O; U09b/U16 should route dismiss through server + predicate.
2. **Loosened-predicate method:** Re-executed via `attention_dismissible_predicate_pg_test.dart` — obligation
   (`withoutObligationExclusion`), unanswered forward (`withoutPinnedExclusion`), and defence-in-depth cases all
   pass dual assertions.
3. **ON CONFLICT:** Partial unique indexes require `WHERE receipt_id IS NOT NULL` / `outcome_beacon_id IS NOT
   NULL`; U08 suite green; duplicate capture rejected by `__receipt_once` / `__outcome_once` (additive + outcome
   tests).
4. **`outcome_beacon_id` no FK:** Agree — CASCADE would delete audit members; SET NULL would violate
   `member_target_chk`. Orphan `outcome_beacon_id` after beacon delete is an audit snapshot; U09b apply/U09c
   undo should skip when inbox row or authorization is gone (not a counter lie).
5. **Trigger writer:** m0184 `inbox_item_maintain_attention_request_state_trg`; Restore `2→0` bumps
   `decision_revision` to 2; `tombstone_dismissed_at` does not bump generations.

**Scope hygiene:** `git diff 19fd71abd..HEAD` touches only server migrations, `attention_dismissible_sql.dart`,
`attention_clear_repository.dart` (ON CONFLICT line), and PG tests + journal — no client, contract, channel,
`attention_repository.dart`. Pre-existing untouchable dirt unchanged.

**Verifier verdict:** pass (see structured block below).

---


## UNIT U09a — remediation: unanswered forwards, enforced in the database · INNER (2026-09-19)

**Layer:** inner (remediation). `UNIT_BASE` `6d622aa07`. One defect, one migration, one commit.

**The defect (from U09a's verify, note 1).** m0183 dropped the `status IN (3, 4)` restriction on
`tombstone_dismissed_at` — correctly; that was the original defect. But it also made dismissal legal at the row
level for an **unanswered** forward. After m0183 owner decision A lived only in `AttentionDismissibleSql`'s
`eligible_pinned` exclusion, a *read* predicate. A direct Hasura `update_inbox_item`, or any future caller
composing its own SQL, could hide someone's unanswered request for help without answering it.

**The fix — m0185**, `inbox_item_guard_unanswered_dismissal`, a `BEFORE INSERT OR UPDATE` trigger. It fires only
when `tombstone_dismissed_at` is being *set* (un-dismissal, i.e. U09c undo, and every other write to an
unanswered row are untouched), and refuses only `status = 0` rows outside the viewer's responsibility scope.

`status = 0` is two rows wearing one number: `helping` when the Request is in scope, "still awaiting your
answer" when it is not — exactly the `forward_outcome` CASE in `attention_repository.dart`. The trigger mirrors
the same `scope` definition the predicate uses: `responsibility_scope_base_beacons` (authored, or an open help
offer) **plus** any Request carrying a live unsettled obligation receipt. Using only the base function would
have falsely refused the obligation-scoped `helping` row. m0183 is **not** narrowed: all five answered kinds
stay dismissible, and the migration comment says why the rule is row-level so nobody relaxes it to "the sweep
already filters that".

**Both directions are proved**, because a fix that only proved the refusal could have re-broken m0183:
`watching`, `notInterested`, `closedBeforeResponse`, `deletedBeforeResponse` each still dismissible; `helping`
proved twice over (via help offer and via authorship, since the two legs of scope are different code paths);
`answering the forward first makes it dismissible` shows the refusal is about the state, not the row.

### Tests actually run

```
# RED (migration not yet written)
dart test --tags pg -j 1 attention_outcome_dismissible_pg_test.dart            00:03 +18 -2: Some tests failed.
  - a direct UPDATE on an unanswered forward is refused by inbox_item_guard_unanswered_dismissal
  - an INSERT that arrives already dismissed is refused too
  (both: "emitted []" — the write succeeded, which is the defect)

# GREEN
dart test --tags pg -j 1 attention_outcome_dismissible_pg_test.dart            00:03 +20: All tests passed!
dart test --tags pg -j 1 attention_outcome_dismissible_pg_test.dart \
  attention_clear_operation_pg_test.dart attention_dismissible_predicate_pg_test.dart \
  attention_request_state_writer_pg_test.dart ../database/attention_additive_schema_pg_test.dart \
  attention_activity_stream_pg_test.dart                                       00:22 +101: All tests passed!
dart test --tags pg -j 1 attention_repository_pg_test.dart attention_surface_pg_test.dart \
  attention_request_history_pg_test.dart attention_mark_seen_for_beacon_pg_test.dart \
  my_work_attention_pg_test.dart attention_live_obligations_pg_test.dart \
  attention_retention_pg_test.dart                                             00:17 +58: All tests passed!
./scripts/check-custom-lints.sh packages/server                                total: 0 (baseline: 0) — OK
```

All through `scripts/run_with_test_cleanup.sh`. Full server suite not run — the overseer owns it.

### Findings

- **The new guard immediately caught an over-broad test fixture.** `attention_dismissible_predicate_pg_test`'s
  "an already dismissed outcome is not swept twice" dismissed by `WHERE user_id = …` alone, which also swept
  the fixture's unanswered forward. The database refused it. The UPDATE is now scoped to its beacon — that is
  the guard doing its job on the first real caller it met, one written by this unit's own author.
- **m0183's status-0 test was ambiguous and is now split.** It was named
  `helping / unanswered forward (0)` and asserted both could be dismissed, with a fixture that was in fact the
  *unanswered* case. One assertion covering two opposite meanings is how this defect stayed invisible.
- The trigger runs two `EXISTS` probes per dismissal write, one of them through
  `visible_attention_receipts`. Dismissal is low-frequency, and U09b's sweep writes per Request batch, so this
  was not optimised; if it ever shows up, the scope set can be computed once per statement instead.

STATUS: complete

---

### Manager verdict — U09a · **ACCEPTED** (hard; inner Opus-low ✓ / verify pass / one remediation)

Overseer's full suite: **1676 non-PG**, **909 PG / 24 known skips** (up from 870 — 39 new tests).
Commits `68b170d48` m0183 · `c3408619d` predicate · `83605cd56` m0184 · `6d622aa07` journal ·
`27c2c14bc` m0185 remediation.

**The remediation is the story.** m0183 correctly fixed a real DB defect — `helping`, `watching` and
`notInterested` could not be dismissed at all — but in widening the trigger it also made dismissal legal at the
**row level for an unanswered forward**. The sweep predicate excluded those rows correctly, so nothing would
have gone wrong through `attentionDismissAll`; the protection simply lived only in a read predicate. Owner
decision A says an unanswered forward must never be swept, because hiding one discards somebody's request for
help without answering them — a guarantee that depends on every caller remembering is not a guarantee. m0185
moves it into the database.

**Why the hole existed, and this is the reusable lesson:** m0183's status-0 test asserted **two opposite
meanings under one name** (`helping / unanswered forward (0)`) and was green for both readings. `status = 0` is
two distinct rows under one number — `helping` inside the responsibility scope, an unanswered forward outside
it. The remediation split the test, and had to mirror the predicate's full scope (base beacons **plus** live
unsettled obligation receipts): a base-function-only guard would have falsely refused the obligation-scoped
`helping` row, re-breaking exactly what m0183 repaired. The new trigger then immediately caught an over-broad
fixture in U09a's own predicate suite.

**Test methodology adopted without being asked:** exclusion tests are asserted against a **deliberately
loosened copy** of the predicate, because "the row is absent" passes trivially when the set is empty for
unrelated reasons. That technique found that an obligation *on a Request* is excluded twice over, forcing the
load-bearing case onto a Request-less obligation. The verifier re-ran the method independently.

**Architectural finding I endorse:** the `attention_request_state` writer is a **trigger**, not Dart, because
`InboxRepository.setStatus` has no server-side caller — stance (including Restore) is written through Hasura and
terminal statuses by a beacon trigger in pure SQL. A Dart writer would have missed the exact transition undo
depends on.

**Judgement calls accepted:** `outcome_beacon_id` is deliberately not a foreign key (CASCADE would delete audit
members and skew the operation counters; SET NULL would violate the new CHECK) — U09b/U09c must treat a missing
inbox row as *skip*, not corruption. The two axes stay separate, with one operation spanning both.

**Correction to the record:** `beacon.state` does not exist — the column is `beacon.status`. Both the U09 scout
brief and m0024's comment text say otherwise.

---

## UNIT U09b — the sweep · INNER (2026-09-19)

**Layer:** inner (implementer), tagged **hard** (concurrency + socially visible side effects).
`UNIT_BASE` `1c25b1ade`. Server-side only. Undo is U09c; the client is U16.

### What landed

| Step | Commit | What |
|---|---|---|
| capture | `ef85003aa` | **m0186**; `attention_sweep_models.dart`, `attention_sweep_port.dart`, `attention_sweep_case.dart`, `attention_sweep_repository.dart` (capture half); new PG suite |
| apply / resume | `8b1046d7d` | the batch loop, the per-member re-check, the three races |
| GraphQL | `2b03205d9` | `attentionDismissAll` + `AttentionDismissAllResult` / `AttentionSweepMember` |
| journal | this entry | |

DI is generated (`lib/app/di.config.dart`, gitignored): `AttentionSweepPort` → `AttentionSweepRepository`
(singleton), `AttentionSweepCase` (factory), both written by `build_runner`.

### The difference from U08, which decides everything else

U08 is handed a bounded membership a client could see. This one has no token and takes no list — the mutation's
only arguments are the operation id and an optional batch bound. That is the guarantee, not an omission: a
sweep whose membership came from the caller could only ever cover the pages that caller had loaded, and For You
would never reach zero. `attentionDismissAll takes no membership from the caller` asserts the argument set
itself, so nobody can add a convenience `receiptIds:` later without a test going red.

Capture is one statement composing `AttentionDismissibleSql` — Set R ∪ Set O, both axes, whole surface. What it
finds becomes `attention_clear_operation_member` rows in state `pending`, chunked.

### Owner decision A (addition 1, in my own words)

An unanswered forward is somebody asking me for help and waiting. Hiding it would *answer* them — with a
refusal they never hear about and I never consciously made. No undo window repairs that, because the silence has
already been delivered. So "Dismiss all" is not "clear the surface"; it is "clear the rows that are only a
record of something already decided", and the unanswered forward is the exact row that is not one.

It cannot happen here in four ways, each with a test:

1. **It is never captured.** `NOT IN eligible_pinned` is inside the predicate the capture composes.
2. **It is never captured on a resume either**, because a resume re-enters by operation id and never re-captures
   — `a forward that arrives mid-sweep is not swept up` forwards a brand-new Request to the viewer between two
   bounded calls and then asserts the membership is still exactly the two receipts.
3. **A member that becomes a pinned forward mid-sweep is refused at apply.**
   `a forward answered again mid-sweep is skipped and reported, never swept` captures a `notInterested` outcome,
   presses Restore through a bare `UPDATE` (which is how the client really does it, through Hasura), resumes,
   and gets `skipped` with reason `awaiting_decision` and `tombstone_dismissed_at` still NULL.
4. **A replay cannot reach it**, because a replay answers from stored membership and applies nothing new.

**And the predicate refuses it before the database has to.** That test asserts `failed` is empty — m0185 would
have surfaced as a *failed* member, so an empty `failed` list is the evidence that nothing reached the trigger.
The trigger is proved separately, by name, in the very next test, so both lines are known to hold and neither is
standing in for the other. This matters because m0185 is the last line of defence; a system that only works
because its last line holds has no margin left.

### The three races, each with its outcome stated in advance (addition 2)

| Race | Test | Outcome |
|---|---|---|
| Somebody answers a forward while the sweep runs | `a forward answered again mid-sweep…` | that member is **skipped**, reason `awaiting_decision`, never swept; status `partial` |
| A resumed operation meets a member that went ineligible after capture | `a member that became ineligible after capture is skipped, not cleared`; `a Request that became My Desk work mid-sweep…`; `an outcome decided underneath the sweep is skipped` | **skipped** with `already_cleared` / `responsibility_gained` / `decision_changed`; not cleared; membership **not** extended; the earlier `explicit` clear is not re-stamped |
| The same operation id replayed, concurrently | `a replayed operation id has exactly one effect`; `a concurrently replayed operation id has exactly one effect` (two `TenturaDb` connections, `Future.wait`, `batchSize: 1`) | one operation row, one member set, identical answers, `applied = 5` once; a receipt that arrived after the first run stays uncleared |

**How concurrency is made to give one answer, reusing U08 rather than inventing a rule.** The header insert is
still `ON CONFLICT (id) DO NOTHING`, so a twin blocks on the primary key and never captures its own membership.
What is new is that a sweep is many transactions, so a twin can arrive *mid-flight*. Each batch takes
`FOR UPDATE` on the members it is about to decide: the twin blocks, re-reads, and finds those rows no longer
`pending`, so every member is decided exactly once however many callers are in the loop. Both callers then leave
only when nothing is pending, and both build their answer from **stored membership** rather than from what they
personally did — which is why the caller that did the work, the caller that resumed it and the twin that did
nothing all report the same thing.

### Reporting honestly (addition 3)

**"Applied" means cleared.** Receipts are updated with a guard (`cleared_at IS NULL AND NOT requires_action`)
and then *read back* by `cleared_by_operation_id`; only the rows that came back are reported applied. A row the
sweep did not touch cannot be counted as swept — which is the failure mode that would be worse than failing.

**"Skipped" carries a reason**, and the reasons are different facts: `awaiting_decision`,
`responsibility_gained`, `decision_changed`, `already_cleared`, `obligation`, `not_authorized`, `refused`. Lost
authorization and a vanished row deliberately share one reason, so the sweep does not disclose which. `failed`
is a member the *database* refused — it should never happen, and it is separated from `skipped` precisely so it
is visible when it does.

**Complete vs partial**, U08's rule extended by one case: `complete` only when every member was cleared,
`partial` the moment anything was refused **or is still pending**. A bounded call that has three members and
cleared one says `partial` with `pendingCount: 2`, never `complete`.

### Proving the exclusions can fail (addition 4)

U09a's method, applied to *this* unit's SQL rather than a paraphrase of it: `AttentionSweepRepository.captureSql`
is public so the tests can loosen the exact string the repository runs. Delete `NOT IN eligible_pinned` and the
unanswered forward becomes a member; delete `NOT requires_action` and the obligation becomes a member. Both
halves are asserted in the same test, because "the row is absent" passes just as happily when the set is empty
for some unrelated reason — and an exclusion test that cannot fail is the one defect that lets this feature
reject somebody's offer of help.

### The feed is unchanged, deliberately (addition 6)

No projection was touched. Every assertion is on database or API state — `cleared_at`, `clear_reason`,
`cleared_by_operation_id`, `tombstone_dismissed_at`, member rows, header counters, the mutation's result — and
**none** on "the surface went to zero". `one operation spans both axes` pins the gap explicitly: after a sweep,
`seen_at` is still NULL. `attention_activity_stream_pg_test.dart` (26 tests) passes unchanged, which is the
evidence the feed did not move.

### Tests actually run

```
# RED — capture, with m0186 unregistered from the migration list
dart test --tags pg -j 1 attention_dismiss_sweep_pg_test.dart   00:02 +1 -6: Some tests failed.
  (column "decision_revision" of relation "attention_clear_operation_member" does not exist)

# RED — apply, with the batch loop short-circuited (`while (false && …)`)
dart test --tags pg -j 1 attention_dismiss_sweep_pg_test.dart   00:03 +9 -10: Some tests failed.
  e.g. "one operation spans both axes" Expected: ['Nu09bboth'] Actual: []
       "a concurrently replayed operation id…"  Expected: <5> Actual: <0>

# RED — GraphQL, before the mutation existed
dart test attention_graphql_test.dart                            00:00 +0 -1: compile — No named parameter 'sweep'

# GREEN
dart test --tags pg -j 1 attention_dismiss_sweep_pg_test.dart   00:03 +19: All tests passed!   (x3 runs, races stable)
dart test attention_graphql_test.dart                            00:00 +26: All tests passed!  (was +22)

# GREEN — the unit's TEST_CMD, everything coupled, in one run
dart test --tags pg -j 1 attention_dismiss_sweep_pg_test.dart \
  attention_clear_operation_pg_test.dart attention_dismissible_predicate_pg_test.dart \
  attention_outcome_dismissible_pg_test.dart attention_request_state_writer_pg_test.dart \
  attention_activity_stream_pg_test.dart ../database/attention_additive_schema_pg_test.dart
                                                                 00:27 +120: All tests passed!
dart test --tags pg -j 1 attention_repository_pg_test.dart attention_surface_pg_test.dart \
  my_work_attention_pg_test.dart attention_live_obligations_pg_test.dart
                                                                 00:11 +42: All tests passed!
./scripts/check-custom-lints.sh packages/server                  total: 0 (baseline: 0) — OK
```

All through `scripts/run_with_test_cleanup.sh`, PG with `--tags pg -j 1`. The U08 clear suite ran in every
round (addition 5) — m0183 coupled the two through the member table's partial indexes. Full server suite not
run: the overseer owns it.

### Findings

- **`maxBatches` is a product feature, not a test hook.** I needed a way to interrupt a sweep to test resume,
  and the honest version of that is the one a caller wants anyway: bound the work of one request and resume by
  sending the same operation id. It is on the mutation, and `partial` + `pendingCount` is how a bounded call
  says so. The alternative — a test-only seam — would have tested a code path no caller ever takes.
- **A `UNION ALL` takes its column names from the first branch, and the bug only showed under a race.** The
  re-check query aliases the receipt branch as `member_id`; the outcome branch did not, so a batch containing
  *only* outcomes read a null column. Every happy-path test passed, because those batches always had a receipt
  in them. It was the concurrent-replay and outcome-generation tests — the two where batching is one member at a
  time — that caught it. Two of the three failures in my first green attempt were this one defect.
- **The fixture is more adversarial than it looks.** Forwarding creates the inbox row
  (`inbox_item_on_forward_insert`), so every forwarded Request in this suite starts life as an *unanswered
  forward*. The pinned exclusion is therefore exercised by every test in the file, not only the one that names
  it: the "whole surface" test captures exactly 9 members out of 10 candidate rows, and the tenth is the
  unanswered forward nobody mentions.
- **`undo_deadline` is deliberately still NULL.** The scout brief suggests setting it on first apply. Undo is
  U09c's and so is the window's length; writing a 30-second deadline here would freeze that decision in a unit
  that cannot test it. U09c sets it in the same place it adds the undo path.
- **m0186 exists because a resumable sweep needs three facts m0178/m0183 have nowhere to put:** the `pending`
  state (U08 decides every member inside its capture transaction and never writes one), the skip reason, and
  `decision_revision` next to `outcome_generation` — a Restore moves the revision without necessarily moving
  the generation, and U09c's undo is defined against both.

### Out of scope, confirmed untouched

No undo (U09c), no client code (U16), no channel/email path, no obligation identity, no contract JSON, no
projection change in `attention_repository.dart` (U10), no change to `AttentionDismissibleSql` — this unit
*consumes* the predicate and did not re-derive or edit it. The Hasura tombstone-dismiss path stays parallel
until U16. Pre-existing untracked and modified files belong to other people and were not staged.

STATUS: complete

---

## UNIT U09b — the sweep · VERIFY (2026-09-19)

**Layer:** verify (read-only). **Base:** `1c25b1ade`. **Commits:** `ef85003aa` · `8b1046d7d` · `2b03205d9` ·
`f51adfbba`.

### Execution

Ran sweep + coupled suites + GraphQL locally:

- PG (`--tags pg -j 1`): `attention_dismiss_sweep_pg_test.dart` (19), `attention_clear_operation_pg_test.dart`
  (15), `attention_dismissible_predicate_pg_test.dart` (12), `attention_outcome_dismissible_pg_test.dart` (21,
  incl. m0185), `attention_request_state_writer_pg_test.dart` (7), `attention_activity_stream_pg_test.dart`
  (22) → **95 passed**
- GraphQL: `attention_graphql_test.dart` → **26 passed** (incl. 4 `attentionDismissAll` cases)

Re-read `_eligibleNow` UNION branches: both alias `member_id`; `captureSql` already did. No other sweep SQL
UNION re-check found with first-branch-only aliasing. `_capture` still uses receipt-only `ON CONFLICT` (outcome
capture relies on single-pass insert + partial unique index — same as U09a tests).

**Verifier verdict:** pass.

---

## UNIT U09b — remediation · INNER (2026-09-19)

**Layer:** inner (remediation). `UNIT_BASE` `f51adfbba`. Two gaps from the U09b verify pass, tests first.

### GAP 1 — the asymmetric capture insert: **not a real defect**, and now symmetric anyway

**Observed outcome: it is already safe, by a transaction boundary I can name.** The header insert and `_capture`
share **one** `_database.transaction`. Postgres' `ON CONFLICT DO NOTHING` is a speculative insertion: on a
conflicting *uncommitted* tuple it waits on the inserting transaction's xid rather than returning immediately.
So a twin carrying the same operation id blocks until the winner has committed header **and** membership, then
sees the conflict, gets `inserted == 0`, and returns `false` — never reaching `_capture` at all. The verify
pass's "safe today because capture runs once per operation" is right; what makes it true is that boundary, not
luck.

New test `two concurrent first calls over an outcome-only surface agree` is the sharpest probe available: an
outcome-only surface (two decided inbox items, zero receipts), two `TenturaDb` connections, `Future.wait`, both
first-calls. On real code it passes. To show it is not a test that cannot fail, the gate was mutated
(`if (inserted == 0)` → `if (inserted == -1)`, so both callers capture):

```
# mutant, before the fix — the asymmetry is real if capture ever runs twice
dart test --tags pg -j 1 attention_dismiss_sweep_pg_test.dart -n "outcome-only surface"
  00:02 +0 -1: Some tests failed.
  Severity.error 23505: duplicate key value violates unique constraint
    "attention_clear_operation_member__outcome_once"
    Key (operation_id, outcome_beacon_id)=(OPu09boutconc, Bu09bfwd1) already exists
    at AttentionSweepRepository._capture (:502)

# same mutant, after adding the outcome ON CONFLICT
  00:02 +1: All tests passed!
```

So: the receipt branch absorbed a duplicate, the outcome branch threw, exactly as the brief predicted — under a
condition the current code does not create. The `ON CONFLICT` was added anyway, because it costs nothing and an
insert that is idempotent on one axis and throws on the other is a trap for whoever moves that transaction
boundary. The conflict target is per-axis because m0186 gives each axis its own *partial* unique index; one
clause cannot cover both.

### GAP 2 — the coexistence assertion

`an unanswered forward survives a bounded sweep and its resume` — three receipts plus a decided outcome, a
`maxBatches: 1` call (asserted `partial`, pending non-empty), then a resume on the same operation id to
`complete` (`applied = 4`). At **each** of before / bounded / resumed it asserts the unanswered forward
`Bu09bfwd3` has `tombstone_dismissed_at` NULL, is still pinned (`inbox_item.status = 0`, not tombstoned), and is
not in the operation's membership. The guarantee was previously inferred from "it is never captured"; it is now
asserted along the one path — stop halfway, pick up later — that no other test walks.

### Tests actually run

```
dart test --tags pg -j 1 attention_dismiss_sweep_pg_test.dart
  00:04 +21: All tests passed!     (was +19; both new tests green on unmutated code)

# TEST_CMD — sweep + U08 clear + U09a predicate/outcome
dart test --tags pg -j 1 attention_dismiss_sweep_pg_test.dart \
  attention_clear_operation_pg_test.dart attention_dismissible_predicate_pg_test.dart \
  attention_outcome_dismissible_pg_test.dart
  00:15 +68: All tests passed!
./scripts/check-custom-lints.sh packages/server   total: 0 (baseline: 0) — OK
```

All through `scripts/run_with_test_cleanup.sh`. Full server suite not run: the overseer owns it.

### Out of scope, confirmed untouched

No undo, no `undo_deadline` (U09c). No client code, no contract JSON, no `attention_repository.dart`
projection, no migration (m0186 already has both partial indexes — this only names the second one at the call
site).

STATUS: complete

---

### Manager verdict — U09b · **ACCEPTED** (hard; inner Opus-low ✓ / verify pass / one remediation)

Overseer's full suite: **1680 non-PG**, **930 PG / 24 known skips** (up from 909). Commits `ef85003aa` capture ·
`8b1046d7d` batched apply + m0186 · `2b03205d9` GraphQL · `f51adfbba` journal · `387293f14` remediation.

**Owner decision A is now enforced in depth and proven by falsification.** An unanswered forward survives a
plain sweep, a bounded-then-resumed sweep, a replayed operation id, and becoming answerable mid-sweep — and the
sweep's **own** predicate refuses it before m0185's row-level guard has to, so the guarantee is not resting on
its last line of defence. Both the inner layer and the verifier re-ran the exclusions against deliberately
loosened copies of the predicate to prove those tests can fail.

**The defect this unit caught is a good argument for race tests.** `UNION ALL` takes its column names from its
first branch, and the apply re-check aliased `member_id` only on the receipt branch — so a batch containing
**only outcomes** read a null column. Every happy-path test passed; only the one-member-per-batch race tests
exposed it. The verifier then checked for the same first-branch-aliasing mistake elsewhere in the sweep SQL and
found none.

**The remediation answered a "safe because it cannot happen" claim with a mechanism.** The verify pass called
the missing `ON CONFLICT` on the outcome capture branch safe "because capture runs once per operation". The real
reason is narrower and nameable: capture shares the header insert's transaction, and Postgres' `ON CONFLICT DO
NOTHING` uses **speculative insertion** — a twin with the same operation id *waits* on the uncommitted tuple,
gets `inserted == 0`, and never reaches capture. The worker proved the asymmetry was otherwise real by mutating
that gate, watching the outcome-only concurrency test fail with 23505 on
`attention_clear_operation_member__outcome_once`, then adding the `ON CONFLICT` anyway because it costs nothing.

**Reporting is honest:** `applied` is tied to actual `cleared_by_operation_id` / tombstone writes, every skip
carries a typed reason (`awaitingDecision`, `alreadyCleared`, `responsibilityGained`, `decisionChanged`), and a
bounded call returns `partial` with a real `pendingCount`.

**Deliberate non-work:** `undo_deadline` is still NULL — its length is a product decision belonging to U09c,
and writing it here would have been untestable. Pending prompts remain unmodeled because they have no feed row
yet; the journal records that they will **not** fall out of the predicate by themselves.

---

## UNIT U09c — undo · INNER (2026-09-19)

**Layer:** inner (implementer), tagged **hard**. `UNIT_BASE` `6bed2dfa8`. Server-side only; the client is U16.

### What landed

| Step | Commit | What |
|---|---|---|
| deadline on apply | `a552926d6` | the sweep opens the window it left NULL; `undoDeadline` / `undoToken` on the result |
| undo | `bbd2ece07` | `AttentionSweepPort.undo`, `AttentionSweepCase.undo`, the two guarded restore statements, the refusal reasons, new PG suite |
| GraphQL | `40793d8c1` | `attentionUndo` + `AttentionUndoResult` / `AttentionUndoMember`; `undoToken` / `undoDeadline` on `AttentionDismissAllResult` |
| journal | this entry | |

No migration. U09a's amended member shape and m0186's `state` / `decision_revision` / `skip_reason` already hold
everything undo needs; the only new member state, `undone`, is a value in a free-text column m0186 documented as
free text on purpose.

### The window, and why it is 30 seconds (the deadline justification)

U09b deliberately left `undo_deadline` NULL, on the grounds that the window's length is undo's decision. It is
**30 seconds**, which is D13's number, and the reason to keep it is not that D13 said so:

The undo window is the lifetime of the affordance that offers it. Undo here is a snackbar action, and a window
longer than the snackbar is a promise the interface never makes — the person would have no way to reach it, and
the only visible effect of the extra time would be that some *other* device could still reverse a sweep long
after it looked settled. A window much shorter would expire while the snackbar was still on screen, which is
worse: an offered action that refuses. Thirty seconds is also short enough that "nothing has happened yet" is
usually true, which matters for a conservative undo — a long window would mean most undos refuse most of their
members, and an undo that mostly refuses trains people not to trust it.

**When it opens, and when it moves.** On the first apply that actually *clears* a member, and again on any later
call that clears more. A bounded sweep is one gesture even when it takes four calls, so the window runs from the
last thing the sweep really swept, not from the call that started it — otherwise `maxBatches` would silently
shorten the undo window in proportion to how long the sweep took. `GREATEST` keeps it monotonic and a call that
cleared nothing leaves it exactly where it was, so **a replay cannot buy undo time by asking again**. That last
one has a test by name; without it, a client polling a finished operation would extend its own window forever.

`_applyBatch` now returns `(decided, applied)` rather than a single count, because "this call did work" and
"this call decided something" are different facts and only the first opens a window.

### The refusal rules, each with the reason it exists (overseer addition 1)

`markUnseen` is not reused and nothing here is modelled on it. Its refusal — it will not restore when an unseen
sibling shares the dedup key — existed because receipts were rewritten in place; U05a made them immutable, so
that rule now protects nothing, and in any case it reverses `seen_at`, the *read* axis, which is not the axis a
sweep touched. An undo that silently refuses for an obsolete reason is worse than one that refuses loudly, so
every rule below is stated with what it prevents.

**Whole-operation refusals** (typed, `AttentionUndoRefusal`; nothing is examined, nothing is written):

| Refusal | Rule | Why it exists |
|---|---|---|
| `expired` | server clock is past `undo_deadline` | The bound. Read inside the same transaction that would restore, so a deadline that passes mid-undo refuses rather than half-applying. Never an untyped failure: it is the one refusal a person actually sees. |
| `not_found` | no such operation, **or** it is not the caller's | Authorization, and non-disclosure: the two cases answer identically so undo is not a way to discover which operation ids exist. |
| `never_applied` | the operation exists and is the caller's but `undo_deadline IS NULL` | No window was ever opened because nothing was ever cleared. This is also what a U08 clear gets — U08 opens no window, so its operations are not undoable through this path at all. |

**Per-member refusals** (typed, `AttentionUndoSkipReason`; the rest of the operation still proceeds):

| Reason | Rule | Why it exists |
|---|---|---|
| `not_applied` | member state is `pending`, `skipped` or `failed` | Undo reverses what happened; it does not finish what did not. See the partial-sweep section. |
| `already_restored` | member state is `undone`, or the row is already back | Idempotence, not an error: a second undo inside the window is a double tap, not a conflict. |
| `cleared_by_another_operation` | `notification_outbox.cleared_by_operation_id <> operationId` | **Never reverse another actor's act.** Another device's sweep, or a later explicit × that re-cleared the row, owns that clear state now. |
| `decision_changed` | live `decision_revision` / `outcome_generation` ≠ the member's snapshot | **Never reverse a domain transition, and never restore a member whose object changed since the sweep.** This is the whole purpose of U09a's two counters and the one rule with a *direction* — see below. |
| `not_authorized` | the row is gone, or the viewer may no longer read it | Authorization re-checked at undo time, not trusted from capture. Vanished and forbidden share one answer so the result discloses neither. |
| `refused` | the database refused the write | Never expected. Kept apart from `skipped` precisely so it is visible if it ever happens; each member restores inside its own savepoint so one refusal cannot take the undo down. |

**The rule that is deliberately absent: there is no obligation guard.** A cleared receipt cannot be an
obligation — `notification_outbox__clear_optional_only_chk` says an obligation carries no clear state at all, so
"a member still carrying this operation's clear, which is now `requires_action`" is a state the database will not
represent. I could not construct it to write a failing test for it, and a guard nobody can make fail is
decoration rather than protection; the honest version is this paragraph. The equivalent guard *is* present on the
outcome axis in the form of the readability clause, which is constructible and tested.

### The direction: later intent wins (overseer addition 2)

The conservative rule is not symmetric, and the tests are written as pairs so the boundary is pinned from both
sides — the same scenario where undo must restore and where it must refuse:

| Pair | Restores | Refuses |
|---|---|---|
| receipt, Request untouched vs decided | `restores a receipt whose Request nobody touched` | `refuses a receipt whose Request was decided after the sweep` — the viewer answered the forward afterwards; the dismissed receipt is not put back underneath that answer |
| outcome, untouched vs re-pinned | `restores an outcome nobody touched` | `refuses an outcome the viewer re-pinned after the sweep` — Restore through a bare `UPDATE`, which is how the client really does it through Hasura. **The sweep stands and the re-pin stands; undo changes neither.** |
| its own work vs another's | `restores only members of that operation` | `refuses a receipt another operation cleared in the meantime` |
| inside vs outside the window | `just inside the window restores` | `just outside the window refuses, and says so by name` |

The re-pin case is the one that matters most and the one `markUnseen` would have got wrong: resurrecting the
tombstone would re-hide a forward the person had just deliberately put back in front of themselves.

### Undo of a partially applied sweep (overseer addition 4)

A bounded sweep returns `partial` with pending members, and undo of such an operation does three things and no
others:

1. **Restores the members it applied.** Nothing else is in scope.
2. **Reports every pending member as `not_applied`** and leaves its state `pending`. Restoring a row the sweep
   never cleared would not be an undo, it would be an invention; and *applying* it would be undo quietly
   finishing the operation it was asked to reverse. Both are tested: after the undo, the pending receipts are
   still uncleared and their member rows are still `pending`.
3. **Does not close the operation.** The header keeps saying the operation is unfinished. A member the sweep
   *skipped* is treated the same as a pending one — `a member the sweep skipped is never restored by undo`
   sweeps one receipt, lets another gesture clear the second with `clear_reason = 'explicit'`, resumes (the
   sweep skips it), then undoes: the explicit clear survives untouched.

The header records `status = 'undone'` only when no member of the operation is still `applied`. The sweep's
`applied` / `skipped` / `failed` counters are **not** decremented: they say what the sweep did, and undo does not
change that. One coupling fell out of this — `_summarize` had to learn the `undone` state, because the
`case _:` default would have reported undone members as *pending*, and a later resume would then have claimed
work it was never going to do. They are reported as skipped with the new reason `undone`.

### Proving the refusals can fail (overseer addition 3)

Two layers, because the guards live in two places.

**SQL guards** — each is a separate named constant (`undoReceiptOperationGuard`, `undoReceiptCountersGuard`,
`undoOutcomeCountersGuard`, `undoOutcomeReadabilityGuard`, `undoAppliedStateGuard`) composed into
`undoReceiptSql` / `undoOutcomeSql`, so a test deletes exactly that clause from the *exact text the repository
runs* — U09a's method — and asserts the loosened statement restores the row the real one refused. Five tests,
each naming what the deleted clause would let through. The helper asserts the clause is actually present in the
SQL first, so a rename cannot turn the loosening into a no-op.

**Dart guards** — the whole-operation refusals and the member-state check are not SQL. I loosened them in a
throwaway copy (`false && expired`, `false && never_applied`, dropping the account comparison, `if (false)` on
the member-state branch), ran the suite, and got exactly the five reds those guards protect:

```
00:04 +17 -5: Some tests failed.
  a partially applied sweep a member the sweep skipped is never restored by undo
  a partially applied sweep undo restores what was applied and never completes the rest
  the window an operation that cleared nothing has no window
  the window just outside the window refuses, and says so by name
  the window somebody else's operation and a missing one answer identically
```

The copy was then discarded (`git diff` clean before the commit). Worth noting what *stayed green* under that
loosening: the idempotence test and the counters tests, because the SQL guards caught those independently. That
is the layering working, not a gap.

### The feed is unchanged, deliberately (overseer addition 7)

No projection was touched; U10 owns indicators. Every assertion in this unit is on database or API state —
`cleared_at`, `clear_reason`, `cleared_by_operation_id`, `tombstone_dismissed_at`, member state, header status,
`undo_deadline`, the mutation's result — and none on "the dot came back".
`attention_activity_stream_pg_test.dart` passes unchanged, which is the evidence the feed did not move.

### Tests actually run

```
# RED — step 1, before AttentionSweepResult carried a window
dart test --tags pg -j 1 attention_dismiss_sweep_pg_test.dart   00:00 +0 -1
  compile: The getter 'undoDeadline' isn't defined for the type 'AttentionSweepResult'

# RED — step 2, before the undo SQL constants existed
dart test --tags pg -j 1 attention_undo_pg_test.dart            00:00 +0 -1
  compile: Member not found: 'undoOutcomeSql' / 'undoOutcomeReadabilityGuard' (…)

# RED — step 2, addition 3: the four Dart guards loosened in a throwaway copy
dart test --tags pg -j 1 attention_undo_pg_test.dart            00:04 +17 -5   (the five listed above)

# RED — step 3, before the mutation existed
dart test attention_graphql_test.dart                            00:00 +26 -5
  attentionUndo reverses… / names the refusal… / takes the operation and its token… /
  requires authentication / attentionDismissAll hands back the undo window it opened

# GREEN
dart test --tags pg -j 1 attention_undo_pg_test.dart            00:04 +22: All tests passed!
dart test --tags pg -j 1 attention_dismiss_sweep_pg_test.dart   00:04 +25: All tests passed!  (was +21)
dart test attention_graphql_test.dart                            00:00 +31: All tests passed!  (was +26)

# GREEN — the unit's TEST_CMD, everything coupled, in one run
dart test --tags pg -j 1 attention_undo_pg_test.dart attention_dismiss_sweep_pg_test.dart \
  attention_clear_operation_pg_test.dart attention_dismissible_predicate_pg_test.dart \
  attention_outcome_dismissible_pg_test.dart attention_request_state_writer_pg_test.dart \
  attention_activity_stream_pg_test.dart ../database/attention_additive_schema_pg_test.dart
                                                                 00:31 +148: All tests passed!
./scripts/check-custom-lints.sh packages/server                  total: 0 (baseline: 0) — OK
```

All through `scripts/run_with_test_cleanup.sh`, PG with `--tags pg -j 1`. The U08 clear suite and the U09b sweep
suite ran in every round (addition 6). Full server suite not run: the overseer owns it.

### Findings

- **Drift reads a `customSelect` `timestamptz` as unix seconds** and `int.parse`s the driver's
  `DateTime.toString()`, so `read<DateTime>('undo_deadline')` throws. The repo already had
  `readCustomSelectTimestamptz` for exactly this; the sweep repository now imports it. Every sweep test failed
  on this at once, which is how it was found — it is not specific to undo and will bite the next timestamp
  column someone selects.
- **`_summarize` had a latent hole that only undo could open.** Its `switch` had `applied` / `skipped` /
  `failed` and a default that meant "pending". A member state it did not know — and `undone` is the first one —
  would have been reported as pending, making a resumed sweep promise work it would never do. Adding a state to
  that column is not a local change, which is worth knowing before U10 or U18 adds another.
- **The undo token carries no capability, and saying so is the design.** Authorization is the JWT against
  `attention_clear_operation.account_id`; the window is a server column. What the token carries is *offer*: an
  operation that cleared nothing has no token, so a client cannot show an undo affordance for a sweep that did
  nothing. It is decoded in the use case, not the repository, so a malformed or mis-bound token never reaches
  the database — and a token bound to another operation gets `not_found`, the same answer as a token for an
  operation that does not exist.
- **The obligation guard is unwritable, not forgotten.** See the refusal table. This is the one place I would
  most want a reviewer to disagree with me: I removed a guard the scout brief implied, on the grounds that the
  CHECK constraint makes its failure mode unrepresentable and I could not write a test that fails without it.

### Out of scope, confirmed untouched

No client code (U16), no channel/email path, no obligation identity, no contract JSON, no projection change in
`attention_repository.dart` (U10), no change to `AttentionDismissibleSql` — undo re-asks the outcome
readability question in the same words but does not edit that file. No migration. `markUnseen` untouched and
uncalled. Pre-existing untracked and modified files belong to other people and were not staged.

STATUS: complete

---

## UNIT U09c — undo · VERIFY (2026-09-19)

**Layer:** verify (read-only). **Base:** `6bed2dfa8`. **Commits:** `a552926d6` · `bbd2ece07` ·
`40793d8c1` · `eaf1c3892`.

### Obligation guard removal — adjudication

**Not P0.** On a single `notification_outbox` row, `requires_action = true` and any non-null clear metadata
(`cleared_at`, `clear_reason`, `cleared_by_operation_id`) violate
`notification_outbox__clear_optional_only_chk` (re-ran
`attention_additive_schema_pg_test.dart` — *rejects clear metadata on an obligation*). A sweep cannot clear an
obligation (`NOT requires_action` on apply); flipping `requires_action` after clear without nulling clear fields
fails the CHECK. Undo only runs `UPDATE … SET cleared_* = NULL` on rows still matching
`cleared_by_operation_id = operation` and visible — a live obligation is a different lifecycle (often a different
receipt id after supersede). The absent SQL guard is documented in the inner refusal table with
**`notification_outbox__clear_optional_only_chk`** named explicitly (journal § *The rule that is deliberately
absent*).

### Execution

PG: undo (22) + sweep (27 incl. undo-window + outcome-only race) + clear (15) + predicate (12) + outcome (21) =
**97**; GraphQL **31** (incl. 4 `attentionUndo`). All green (~27s).

**Verifier verdict:** pass.

---

### Manager verdict — U09c · **ACCEPTED** (hard; inner Opus-low ✓ / verify pass, no finisher) — U09 complete

Overseer's full suite: **1685 non-PG**, **956 PG / 24 known skips**. Commits `a552926d6` window ·
`bbd2ece07` restore + refusals · `40793d8c1` GraphQL · `eaf1c3892` journal.

**The inner layer removed a guard and asked to be argued with; the verifier argued and agreed.** The undo path
had an obligation guard that could not be falsified: `notification_outbox__clear_optional_only_chk` makes "a
cleared receipt that is an obligation" unrepresentable, so no test could fail without the guard. The verifier
tried to construct that row through the sweep, direct SQL, and a flip-ordering path, and could not. The guard
stays removed, and the load-bearing constraint's **name** is recorded in the journal's refusal table so the next
reader knows what is actually protecting the invariant. Shipping an unfalsifiable check would have looked like
safety and provided none.

**Falsification was applied to the SQL itself this time.** The verifier loosened one named clause at a time in
`undoReceiptSql` / `undoOutcomeSql` and confirmed each refusal test fails — stronger than the inner layer's Dart
loosening, which layered SQL guards had silently absorbed. That difference is worth remembering: a guard proven
only at the language level may be masked by a constraint underneath it.

**A latent hole only undo could open:** `_summarize`'s `case _:` default meant "pending", so an unknown member
state would have made a **resumed sweep promise work it never does**. Introducing the `undone` state exposed it;
the verifier confirmed it is the only exhaustive switch on member state in this machinery.

**Product semantics I endorse:** the undo window runs from the **last member actually cleared**, not the first
call. A bounded `maxBatches` sweep is one user gesture spread over several calls, `GREATEST` keeps the deadline
monotonic, and a call that cleared nothing cannot buy more time. Refusals are typed — `expired`,
`decisionChanged`, `clearedByAnotherOperation`, `neverApplied`, `notFound` — never an untyped failure.

**Later intent wins, pinned from both sides:** every scenario has a should-restore / must-refuse pair, so
restoring a forward, re-pinning it, or answering it refuses that member instead of resurrecting old state on top
of new.

No migration was needed — m0186's fields already carried undo's needs.

---

## UNIT U10 — Primary projections and ordering · SCOUT BRIEF (2026-09-19)

**Layer:** scout (read-only). **Base:** `6586b056a`. **Tag:** hard (widest blast radius).

### Live baseline — what projections do today

| Area | Live behaviour | U10 target (D02/D08/D09/§6/M1) |
|------|----------------|--------------------------------|
| **Optional “active”** | `seen_at IS NULL` drives dot, `event_unseen_count`, feed `unread` view, `surfaceSummary` activity/myWork unread totals, forward synthetic `seen_at`, watching digest | `requires_action = false AND cleared_at IS NULL` for optional axis; obligations stay `requires_action && settlement_kind IS NULL` |
| **`beacon_activity_stats`** | `MAX(created_at)`, counts all `activity_child_receipts` with unseen = `seen_at IS NULL` | Stats only over **active attention** children; dot/count = uncleared optional (+ outcome axis elsewhere) |
| **Activity feed sort** | `page_stream.created_at` = `GREATEST(latest_forward_at, stats.max_created_at)` for forwards; `requestActivity` uses `stats.max_created_at` | **Bumping key** ≠ **latest-event key**: optionals/tombstones/timeline-only update preview/list only |
| **`activityOffers`** | `effective_activity_at = GREATEST(latest_forward_at, stats.max_created_at)`; cursor on that timestamp + `beacon_id` | Pinned zone: stable `first_entry_at` (then tie-break); obligation creation promotes (separate key) |
| **Grouping eligibility** | Any beacon with activity surface receipts → stats row; `requestActivity` if not in `eligible_representative` | Group only when **active attention** (uncleared optional ∪ live obligation ∪ pending forward/prompt per surface rules) |
| **`myWorkAttention`** | Emits if `unseenCount > 0 \|\| liveObligations.isNotEmpty`; `unseenCount` = all receipts with `seen_at IS NULL`; `latestUnseen` = newest non-obligation unseen | Emit on active optional ∪ live obligations; counts/dot fields aligned with D09; Needs-you **order** input = latest live-obligation `created_at` (server list or documented sort key for U14) |
| **`surfaceSummary`** | `seen_at IS NULL` per surface; `needs_you_total` = live obligation **receipt** count (already correct axis, wrong optional axis) | Same predicates as list/indicator (M1); activity dot semantics ≠ raw unread receipt count |
| **Receipt projection** | `_mapRow` / GraphQL `_mapReceipt` omit `cleared_at`, `clear_reason` | Expose `clearedAt` / `clearReason` on `AttentionReceipt` + GraphQL (U06b verify debt) |
| **Cursors** | `query_attention.dart` JSON `{createdAt, id}` only; no version | Version field when sort keys change; malformed/old cursors rejected; head refresh dedupes by Request id (D08) |
| **U08/U09** | `cleared_at`, sweep, `tombstone_dismissed_at`, `AttentionDismissibleSql` | **Invisible in feed/summary until U10** reads cleared state |

**Client consumers (read-only; U14/U15):** `derive_my_work_sections.dart` buckets by `liveObligations`; desk card order still `compareMyWorkCardsForSort` → tier then **`Beacon.updatedAt`** (D08 wants stable work-entry ordering). `home_attention_state.dart` uses `activityUnreadTotal`, `myWorkUnreadTotal`, `surfaceNeedsYouTotal`, and `unreadBeaconIds` from markers — all will skew until server summaries/markers use active attention.

### `// CHANGES IN U10:` and U02 doomed assertions (server)

**Pure U10 tags** (`attention_activity_stream_pg_test.dart`):

| Location | Current expectation | New expectation (observable) |
|----------|---------------------|------------------------------|
| Test `status event merges into forward and bumps created_at` (comment L539) | Optional status **promotes** forward row: `createdAt ==` status time `2026-08-12T14:00:00Z` | Forward row **sort/display anchor** stays on forward generation (`latest_forward_at` / relay time ~`08:00Z`); status changes **preview/dot/count** only (`eventTotal` / `isUnread` or successor fields reflect **uncleared optional**, not `seen_at` alone) |
| Same test (comment L574) | `forward.isUnread == true` via synthetic `seen_at` null when child unseen | Dot/indicator follows **uncleared optional** predicate (may still be true, but must not depend on coalesced `seen_at` hack) |
| Same test | `eventTotal == 1`; no standalone receipt tiles for beacon | Still grouped; children counted only if **actively** attention-bearing |
| Test `activityOffers orders by effectiveActivityAt not latest_forward_at` (L767) | Status on foreign beacon **reorders** pinned set to `[foreign, closed]` ahead of `closed` with only `latest_forward_at` ordering | Relative pinned order **unchanged by optional status**; sort key becomes **`first_entry_at` (+ tie-break)**, not `GREATEST(forward, max optional created_at)` — expect order as before status insert (fixture: **without** status bump, `closed` sorts above `foreign` on forward time alone → after U10 expect `[_closedBeaconId, _foreignBeaconId]` and previews on the leading row per active optional rules) |
| Same test (L792) | `eventTotal` / `eventsPreview` on **first** pinned row after status-driven reorder | First row per **stable** order; optional preview attaches without reordering |

**U09/U10 joint tags** (same file; U10 owns projection semantics, may coordinate with U09 outcome presentation):

| Test | Current | After U10 (+ U09 where noted) |
|------|---------|-------------------------------|
| `active help offer produces helping forward outcome` | Activity shows `forwardOutcome == helping` while My Work holds obligation | D01/D08: **no duplicate live attention** — helping trace on Activity is dismiss-only tombstone or absent when responsibility is My Work-only |
| `helping forward has zero Activity event children` | `eventTotal == 0`, empty preview | Active-only grouping may attach **uncleared optional** children under outcome row or suppress per eligibility |

**Not tagged but will break or need extension:** `unread_total includes receipts represented by forwards`, `my_work_attention_pg_test` unseen counts, `attention_surface_pg_test` per-surface unread totals, `demoted row above cursor appears on head refetch` (behaviour may change when sort keys change — still required to pass with versioned cursors).

### `first_entry_at` (U09a)

- **Writer:** `inbox_item_maintain_attention_request_state` on first `inbox_item` INSERT (`first_entry_at = now()`, `ON CONFLICT DO NOTHING`).
- **Not bumped** on `latest_forward_at`, decisions, or tombstone dismiss.
- **Sufficient for:** pinned unanswered forwards that have an `inbox_item` row (For You pinned zone per D08).
- **Gaps:** `requestActivity` groups without inbox representative; obligation-only My Work entry; legacy rows until next inbox write — U10 may need **COALESCE(first_entry_at, min_active_receipt_at)** or backfill policy for stable ordering. **Not sufficient alone** for My Desk **Needs you** ordering (D08 #1: **latest live-obligation creation** desc).

### CTE coupling in `attention_repository.dart`

| Fragment | Coupling |
|----------|----------|
| `_visibleWithSurfaceCte` (`visible_raw` / `scope` / `visible`) | **Moves with everything** — surface split + obligation union |
| `_activityGroupingCtes` (`eligible_*`, `activity_child_receipts`, `beacon_activity_stats`) | **Single unit** — eligibility filters and stats must agree |
| `_activityPageStreamCte` (`page_stream` unions) | **Must move with** `activityOffers` ranked query and `activityAttention` stats join |
| `attentionFeed` summary CTE + `surfaceSummary` | **Must share one SQL/Dart predicate** with page `unread`/dot semantics (M1) — not independent |
| `myWorkAttention` Dart aggregation | Same optional/obligation definitions as SQL; can land in separate commit only if extracted shared predicate first |
| `_loadActivityChildReceipts` | Tied to stats/preview; filter must match active optional axis |
| `AttentionDismissibleSql.prelude` | **Duplicate today** — U10 should unify **behind dismissible predicate name** or shared CTE module to avoid sweep vs feed drift |

### Pagination / head-refresh risks

| Risk | Mechanism |
|------|-----------|
| **Vanish** | Request sort key jumps **above** cursor position (new obligation promotes) → absent from tail page and maybe missing from head if client only appends |
| **Duplicate** | Same Request on head refresh **and** tail page when keys change but cursor unversioned |
| **Pinned zone shuffle** | Replacing `effective_activity_at` with `first_entry_at` reorders existing users’ pins |

**Existing tests that help:** `cursor paging across receipts and forwards has no duplicates or gaps`; `demoted row above cursor appears on head refetch`; `attention_surface_pg_test` cursor under activity filter; `attention_repository_pg_test` composite cursor stability; `attention_request_history_pg_test` feed-aligned history cursors.

**Gaps (plan-required):** explicit **“group moves above cursor must not vanish”** on **activityOffers** / activity grouped feed after sort-key change; **versioned cursor** rejection test; **M1** test that summary totals match filtered page cardinality for each surface/view.

### Split recommendation

**Yes — do not single-pass U10.** Suggested slices:

1. **U10a — Shared active-attention predicate** (extract from repository + align `AttentionDismissibleSql.prelude`; unit test M1 hook).
2. **U10b — Indicators & `beacon_activity_stats`** (`cleared_at`, outcome-aware dot where needed; `myWorkAttention` + `surfaceSummary`).
3. **U10c — Activity ordering & grouping** (`page_stream`, `activityOffers`, bump vs latest-event split, `first_entry_at`).
4. **U10d — Receipt projection & cursors** (`clearedAt`/`clearReason`, cursor version, pagination/head tests).
5. **Card provenance** (implementation-plan § blocking) is **separate** from U10 steps but gates U14/U16 — do not fold into U10a–d.

### Risks (explicit)

- **Silent disappearance:** clearing optional without U10-aware stats removes last receipt from `beacon_activity_stats` while inbox forward remains → group vanishes or dot/list disagree.
- **Count vs list:** `surfaceSummary` / feed `summary` still counting `seen_at` while page uses `cleared_at` → tab lights, default filter empty (M1 failure).
- **My Work marker:** `unreadBeaconIds` vs `surfaceNeedsYouTotal` diverge if optional axis moves to cleared without client change (server must ship consistent summaries; client still untouchable this unit).
- **Helping forward:** cross-surface duplicate until projection applies scope — wrong row on Activity after help offer.
- **Seen-but-cleared optionals:** still in `visible_attention_receipts` (retention) — must not count as active without `cleared_at` filter.
- **Predicate drift:** refactoring `_visibleWithSurfaceCte` without updating `AttentionDismissibleSql` breaks sweep eligibility vs feed (U09a warned).

### Approach summary

Introduce a **single authoritative active-attention predicate** (optional + obligation + surface-specific forward/prompt rules per §6/D09) used by stats, grouping, summaries, and feed views. Split **sort keys**: `latest_event_at` for previews/history expansion vs `list_position_at` (`first_entry_at`, obligation-promotion timestamp). Version cursors; on head refresh merge by `beacon_id`. Extend `AttentionReceipt` and GraphQL mapping with clear fields. Rewrite U02-tagged tests to pin new behaviour; add pagination promotion tests.

STATUS: complete

---

## UNIT U10a — One predicate source · INNER (2026-09-19)

**Layer:** inner (implementer), tagged hard. **Base:** `a46c6b536`. Scope: the U10 scout brief's step 7
(CTE coupling — `AttentionDismissibleSql.prelude` is a duplicate), promoted to run first by the U10 split.

### Addition 1 — were the two definitions already identical?

**Yes, in membership.** Proven before unifying, not asserted after.
`attention_predicate_unification_pg_test.dart` freezes both texts verbatim from `a46c6b536` and runs them over
one fixture set (owned Request in the responsibility-scope base, forwarded Request in the pinned decision zone,
a Request pulled into scope by a live obligation, a profile-scoped receipt), comparing `visible` + `surface`,
`scope`, and `eligible_pinned` row by row. All six PG comparisons were green at base.

The one textual difference was `authorized.tombstone_copy`, present only on the repository side. It is a
**projected column, not a row filter** — `visible_raw.*` widens, membership does not — so it moved into the
shared text and the sweep simply never reads it. No divergence to report, and therefore no pre-existing defect.

### A third copy the brief did not name

`markAllSeen` carried its own inline `visible_raw` / `scope` / `visible` CTE — same rows, projecting only
`id`, `seen_at`, `surface`. It was found by the structural guard in the new test (`attention_repository.dart`
must not spell `visible_raw AS (` out), not by reading, which is the argument for that guard existing. It now
composes `AttentionDismissibleSql.visibleWithSurface` like everything else. Four copies → one.

### Shape after the unification

| Constant | Contents | Consumers |
|----------|----------|-----------|
| `AttentionDismissibleSql.visibleWithSurface` | `visible_raw` / `scope` / `visible` | repository `_visibleWithSurfaceCte`, `markAllSeen`, sweep |
| `AttentionDismissibleSql.eligiblePinned` | the pinned decision zone | repository `_activityGroupingCtes`, sweep |
| `AttentionDismissibleSql.prelude` | `'$visibleWithSurface,\n$eligiblePinned'` | sweep capture / apply / refusal reasons |

`_visibleWithSurfaceCte` survives as an alias so U10b/U10c diffs stay legible; it is now one line pointing at
the shared constant.

### Addition 2 — load-bearing for **both** consumers

Loosening the shared surface split (`THEN 'myWork'` → `THEN 'activity'`) in a throwaway copy, asserted in the
same file:

- **sweep** — `activity_optional_dismissible` gains the My Desk receipt `Nu10aunifown`; a Request the viewer is
  responsible for becomes sweepable from For You. Test: *loosening it changes the sweep member set*.
- **feed** — per-surface counts move, `myWork` drops to zero. Test: *loosening it changes the feed per-surface
  counts*.

Both notice. The name and the logic are shared, not just the name.

### Deliberately not done (U10b/U10c)

The predicate still reads `seen_at` for indicators — the axis move is U10b, and the whole point of the split is
that it now lands on one definition. Ordering, cursors, `effectiveActivityAt` and `clearedAt`/`clearReason`
exposure untouched.

### Commits

| Hash | Subject |
|------|---------|
| `5e298b767` | `test(server): prove the sweep prelude and the repository CTE already agree` |
| `078d0cc82` | `refactor(server): one visible/surface predicate for the sweep and the feed` |

### Test evidence

Equivalence proof at base (`5e298b767`), before any production change — 6 green, 1 red by design (the
structural guard, which the unification turns green):

```
$ dart test --tags pg -j 1 test/data/repository/attention_predicate_unification_pg_test.dart
00:01 +6 -1: Some tests failed.
Failing tests:
  test/data/repository/attention_predicate_unification_pg_test.dart: one source, structurally
  attention_repository.dart no longer spells the CTE out
```

After the unification, the scout's PG list plus `attention_mark_seen_for_beacon_pg_test.dart` (added because
`markAllSeen`'s copy turned out to be in scope):

```
$ ../../scripts/run_with_test_cleanup.sh --timeout 30m -- dart test --tags pg -j 1 \
    attention_activity_stream / clear_operation / dismiss_sweep / dismissible_predicate /
    outcome_dismissible / predicate_unification / repository / request_history / surface / undo /
    mark_seen_for_beacon / my_work + api/controllers/graphql/attention_graphql
00:41 +170: All tests passed!

$ ../../scripts/run_with_test_cleanup.sh --timeout 10m -- dart test -j 1 \
    test/api/controllers/graphql/attention_graphql_test.dart \
    test/api/controllers/graphql/query_attention_payload_test.dart
00:00 +35: All tests passed!

$ ./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server
── tentura_lints: packages/server ──
total: 0 (baseline: 0)
check-custom-lints: packages/server OK
```

**No existing test was edited.** The refactor-with-no-behaviour-change contract held; nothing asserted the
duplication itself, so there was no exception to claim.

---

## UNIT U10a — One predicate source · VERIFY (2026-09-19)

**Layer:** verify (read-only). **Range:** `a46c6b536..9b622af3d` (`5e298b767` · `078d0cc82` · `9b622af3d`).

### Refactor contract (existing tests edited?)

`git diff a46c6b536..9b622af3d -- packages/server/test` touches **only** the new file
`attention_predicate_unification_pg_test.dart` (+433). **No existing assertion was rewritten** to absorb a
behaviour change.

### Equivalence

Re-ran `attention_predicate_unification_pg_test.dart` (7 PG tests): legacy sweep vs legacy repository on
`visible`+`surface`, `scope`, `eligible_pinned`; live `AttentionDismissibleSql` matches both frozen texts.
Pre-unification copy count at `a46c6b536`: **2** `visible_raw` in `attention_repository.dart` (inline CTE +
`markAllSeen`) + **1** in `attention_dismissible_sql.dart` + duplicate `eligible_pinned` in grouping → **four
copies**; at HEAD **one** definition in `attention_dismissible_sql.dart` only (`rg` on `lib/`).

**Note:** committed fixture exercises owned / forwarded / obligation / profile receipts and forward edges; it
does **not** insert `inbox_item`, so `eligible_pinned` equivalence is empty-set on both sides. Tombstone +
unanswered-forward membership was not re-proven in a separate verifier script (disposable-PG one-off failed to
resolve packages from `/tmp`); regression PG suites including dismissible/outcome predicates still green.

### Structural guard

`one source, structurally` asserts `attention_repository.dart` lacks `visible_raw AS (` and
`eligible_pinned AS (` — passes at HEAD; would fail at `a46c6b536` (two inline `visible_raw` blocks present).

### Load-bearing (both consumers)

In-file loosening (`THEN 'myWork'` → `'activity'`) changes **both** `activity_optional_dismissible` membership
and per-surface `visible` counts (tests *loosening it changes the sweep member set* / *feed per-surface counts*).
Verifier did **not** mutate production `AttentionDismissibleSql` to force failures in
`attention_dismiss_sweep_pg_test` / `attention_surface_pg_test` (read-only); those suites import the shared
constant via `attention_sweep_repository` / `AttentionRepository`.

### Axis / scope boundaries

`git diff a46c6b536..9b622af3d` on `packages/server/lib`: no `cleared_at` indicator move; `markAllSeen` still
filters `seen_at IS NULL`; no `effective_activity_at`, cursor codec, or `clearedAt` GraphQL exposure changes
(`query_attention.dart` / `attention_models.dart` diff empty).

### Regression counts

- `attention_predicate_unification_pg_test.dart` — **7 passed**
- Inner PG list (12 files, same paths as scout minus obligation_identity/channel/dispatch/additive) — **170 passed**
- `attention_graphql_test.dart` + `query_attention_payload_test.dart` (no `@Tags(['pg'])`) — **35 passed**

### Worktree

Pre-existing modified/untracked paths unchanged by U10a commits; no secrets in diff.

**Verifier verdict:** pass — pure refactor; equivalence + structural guard hold; no existing test nudged.

---

## UNIT U10a — Equivalence fixture non-vacuity · INNER (remediation) (2026-09-19)

**Layer:** inner (remediation). **UNIT_BASE:** `9b622af3d`. Test-only; no production file touched.

### TEST_RED — what the vacuous sets were

The U10a verify flagged that `attention_predicate_unification_pg_test.dart` inserts no `inbox_item` and no
tombstone `access_policy`, so the `eligible_pinned` comparison — owner decision A's guarantee that an
**unanswered forward** stays out of the sweep — ran over empty sets on both sides.

**The gap was real but not quite as described.** `eligible_pinned` was *not* empty: m0014's
`inbox_item_on_forward_insert` trigger materialises an `inbox_item` row for every `beacon_forward_edge`, so
the fixture's two forward edges already produced two rows and the pinned zone already held
`Bu10auniffwd`. What was genuinely missing:

- nothing in the file **asserted** that, so the set could have silently become empty at any time;
- no dismissed tombstone, no restricted `access_policy`, no Request-less obligation — the edge rows;
- no clause of `eligible_pinned` other than "scope" had a witness row.

### What the fixture now holds

| Row | Isolates |
|-----|----------|
| `inbox_item` on `Bu10auniffwd`, status 0, undismissed | the member — an unanswered forward |
| `inbox_item` on `Bu10aunifobl` (live obligation receipt) | the `NOT IN scope` exclusion |
| `inbox_item` on `Bu10aunifdel` (beacon status 2) | the `beacon_can_read_content` exclusion |
| `inbox_item` on `Bu10aunifans`, status 4 + `tombstone_dismissed_at` | the status / dismissal exclusions — an answered forward whose outcome is a dismissible tombstone |
| receipt `Nu10auniftmb`, `access_policy = 'beacon_tombstone'` | a tombstone-only-readable receipt reaching `visible` |
| receipt `Nu10aunifoblp`, `requires_action`, `beacon_id IS NULL` | scope's `beacon_id IS NOT NULL` — the clause a Request-bearing obligation cannot isolate, since it is already in scope |

Tombstone statuses are written through `tentura.allow_inbox_tombstone_transition` in one transaction, and every
`inbox_item` write is an upsert over the forward trigger's row rather than a competing insert.

### Non-vacuity guards

`_expectNonVacuous` now runs inside **every** helper the file compares with — `_visibleRows`, `_scopeRows`,
`_pinnedRows`, `_dismissibleReceipts`, `_surfaceCounts` — so a comparison cannot be added later without one.
Two assertions beyond the guard: `eligible_pinned` is exactly `[Bu10auniffwd]` (membership named, not just
agreement), and a new test *the restricted tombstone and the Request-less obligation are visible* proves the
two new receipts actually reach `visible` instead of being inert fixture.

### TEST_GREEN

Membership **still matches** with the richer fixture — U10a did not collapse two definitions that differ on
these rows.

```
$ ./scripts/run_with_test_cleanup.sh --timeout 30m -- dart test --tags pg -j 1 \
    attention_predicate_unification / dismiss_sweep / dismissible_predicate /
    outcome_dismissible / surface
00:15 +79: All tests passed!

$ ./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server
total: 0 (baseline: 0)
check-custom-lints: packages/server OK
```

Unification file alone: **8 passed** (7 before, plus the reachability test).

### Manager verdict — U10a · **ACCEPTED** (hard; inner Opus-low ✓ / verify pass / one remediation)

Overseer's full suite: **1685 non-PG**, **964 PG / 24 known skips**. Commits `5e298b767` equivalence proof ·
`078d0cc82` unification · `9b622af3d` journal · `f88db051d` remediation.

**A pure refactor, and it stayed one: no existing test was edited.** That was the acceptance question, and the
diff answers it.

**There were four copies of the predicate, not two.** Besides the sweep's prelude and the repository CTE, a
third lived inline in `markAllSeen` and a fourth duplicated `eligible_pinned` in the grouping CTEs — found by
the new structural guard rather than by reading. The guard now fails if anyone reintroduces a copy, which is the
only thing stopping U10b and U10c from re-forking the definition they are about to change.

**Equivalence was proven before the merge, not assumed**: both texts frozen verbatim from `a46c6b536` and run
over one fixture set, matching row for row. The only textual difference was a projected column, not a row
filter. And loosening the merged definition breaks **both** consumers — the sweep gains a My Desk receipt *and*
the feed's per-surface count collapses — so what was merged is logic, not a name.

**The remediation corrected the verifier, and that is worth recording.** The verify pass reported the
`eligible_pinned` comparison as vacuous — empty on both sides. It was not: m0014's
`inbox_item_on_forward_insert` trigger materialises an `inbox_item` for every forward edge, so the fixture
already had a pinned row. The real gap was narrower and still worth fixing — **nothing asserted non-emptiness**,
and the edge rows were missing. The fixture now carries a dismissed tombstone, a restricted `access_policy`
row, an account-scoped receipt and a Request-less obligation, every compared set asserts it has something to
compare, and `eligible_pinned` resolves to exactly the one unanswered forward with the other three inbox rows
each excluded by a **different clause**. That is a stronger proof than the original diagnosis would have
produced.

Three layers, three corrections, in three directions: the U05a inner corrected its scout, the U05c verifier
corrected its inner, and here the remediation corrected the verifier. No layer in this plan has been infallible;
the value is that each claim passes through someone with no stake in defending it.

---

---

## UNIT U10b — The axis move · INNER (2026-09-19)

**Layer:** inner (implementer), tagged hard. **UNIT_BASE:** `8545d580a`.
Scope: indicators, counts, summaries and grouping eligibility move from `seen_at` to *active attention*;
`clearedAt` / `clearReason` exposed; M1. Ordering, cursors and `effectiveActivityAt` deliberately untouched.

### What was actually invisible

U08 wrote `cleared_at`, U09 swept, U09c unwound — and **no read path looked at any of it**. Every dot, count and
default list in the read projection asked `seen_at IS NULL`. A user who cleared a Request watched nothing happen;
a swept For-you card kept its dot. The whole of U08 and U09 was write-only until this commit.

### Addition 1 — the definition moved in U10a's single source

`AttentionDismissibleSql` gained three **functions** (not constants) — `activeOptional`, `liveObligation`,
`activeAttention` — taking the caller's alias. Functions because that is what M1 asks for: the indicator's rule
and its list's rule are the same rule called twice, not two strings that happen to agree today. No CTE was
forked; `visibleWithSurface` / `eligiblePinned` are still the single copies U10a left. Three constants became
getters (`dismissibleReceipts`, `cte`, `AttentionSweepRepository.captureSql`) because interpolating a function
is not a constant expression — mechanical, no behaviour.

Callers moved onto them, including two the brief did not name: `AttentionClearRepository._eligibleReceipts` and
its apply re-check each spelled out "not an obligation, not yet cleared" in their own words. *What a clear may
touch* and *what a dot counts* are now literally one predicate. A dot the viewer has no way to extinguish is the
M1 failure seen from the other side, and it was one edit away.

### Addition 2 — the `// CHANGES IN U10:` assertions

**None were touched, and that is the finding.** All four markers in `attention_activity_stream_pg_test.dart`
(L539, L574, L767, L792) are *ordering* assertions — forward `createdAt` anchoring and pinned-zone position under
`effectiveActivityAt`. They belong to **U10c**, not U10b, and all four still pass unchanged. The scout's table
predicted L574 (`forward.isUnread` via the coalesced `seen_at` hack) would move; it did not have to — the
synthetic dot now derives from `activeOptional` instead of `seen_at`, and the assertion's *value* is the same on
this fixture, so the expectation stands while its cause changed.

Two other expectations did change. Both are behaviour, both are justified in place:

| File / test | Asserted before | Asserts now | Why this is the intended behaviour |
|---|---|---|---|
| `my_work_attention_pg_test.dart` · *aggregates news and obligations…* | `unseenCount == 5` — three optional receipts **plus** two obligations, all unseen | `unseenCount == 3` | The field summed two axes D09 keeps independent: the **dot** is optional, the **number** is obligations. Nothing is lost — the same two obligations are still counted by `liveObligations`, asserted two lines below. A field that summed both could only ever drive one indicator correctly. |
| `attention_repository_pg_test.dart` · *markSeen and markAllSeen…* | after `markAllSeen`, unread feed `unreadTotal == 0`, page empty | `unreadTotal == 2`, page is exactly `{Nvisible, Nvisible2}`, and `unreadTotal == page.length` | D02: reading is not clearing. `markAllSeen` moves the **read** axis; the default list and its total now read active attention. This is precisely the behaviour U10b exists to produce — and the assertion was strengthened rather than relaxed, because the M1 equality (number == list) is now stated explicitly where it previously held by accident. |

### Addition 3 — the three silent failures, and proof each test can fail

Each was loosened or tightened in a throwaway copy of `attention_repository.dart` (reverted; nothing committed):

| Failure | Test | Throwaway mutation | Result |
|---|---|---|---|
| A Request **silently disappears** | *clearing the optional children does not unpin the forward* | `activityOffers` ranked CTE gains `WHERE COALESCE(stats.event_total,0) > 0` — eligibility narrowed one clause too far | `Expected: ['Baxisforeign'] Actual: []` — the unanswered forward vanishes when its noise is cleared. Owner decision A breached by an eligibility edit. |
| A **count disagrees with its list** | *M1 — an Activity dot implies a non-empty Activity default list* | `surfaceSummary`'s activity filter reverted to `v.seen_at IS NULL` while the page kept the new axis | `Expected: <0> Actual: <1>` — the tab lights, the list is empty. |
| The **pinned zone reorders** | *an optional event does not reorder the pinned zone* | `beacon_activity_stats.max_created_at` given the same active-attention FILTER as the counts | `Expected: ['Baxisother','Baxisforeign'] Actual: ['Baxisforeign','Baxisother']` — *clearing* an event reshuffles the zone. |

The third probe is the design decision worth naming: `max_created_at` is an **ordering input** and U10c owns
ordering, so the eligibility narrowing was applied to the counts and to group emission but deliberately **not**
to the aggregate that feeds `effective_activity_at`. Filtering it looks natural and is wrong.

### Addition 4 — ordering not touched, and one live defect reported not fixed

No change to `effective_activity_at`, cursor codecs, `ORDER BY` keys or head reconciliation. No ordering test
failed as a result of the eligibility change.

**Reported, not fixed:** an optional event *arriving* on a pinned Request still moves it up the For-you zone,
because the sort key is still `GREATEST(latest_forward_at, max child created_at)`. §6 says an optional update
never changes a position. The test *an optional event does not reorder the pinned zone* pins the live (wrong)
order explicitly with that reasoning written into the `reason:`, so U10c has to change that expectation on
purpose rather than inherit it. What U10b owed — that its own narrowing of what counts as an event does not
move the zone — is the assertion next to it, and it holds.

### Addition 5 — the round trip, end to end

*a real clear moves the feed and the summary together*: two optional receipts on an owned Request →
`surfaceSummary.myWorkUnreadTotal == 2` and the unread feed has 2 items → real `AttentionClearRepository`
`captureEligible` + `apply` (not a hand-written `UPDATE`) → summary `0`, feed empty, feed's own summary `0`,
`myWorkAttention` emits nothing. Plus *History still reaches a cleared receipt*: retired from the surface, still
in the record — §6's "whatever is counted must be reachable", and its converse.

### M1, asserted four ways

1. **Behavioural identity** — the My Desk number equals the My Desk default list, and the feed's own summary
   equals its page.
2. **Biconditional on the grouped surface** — the Activity list groups, so cardinality cannot match; what is
   asserted instead is the property that matters: dot > 0 ⟺ list non-empty, before and after a clear.
3. **Divergence probe** — loosening `activeOptional` in a throwaway copy moves the count and the list ids in
   lockstep, so they cannot be separately maintained.
4. **Structural guard** — `attention_repository.dart` and `attention_clear_repository.dart` must not contain the
   string `cleared_at IS NULL`. It caught the clear command's apply re-check, which reading had missed.

### Deliberately not done

Ordering keys, `first_entry_at`, cursor versioning, head reconciliation, `Needs you` ordering (**U10c**). Card
provenance (separate, gates U14/U16). Client `lib/` (U14/U15/U16) — read-only this unit.

### Commits

| Hash | Subject |
|---|---|
| `fb8b024ea` | `test(server): pin the active-attention axis, M1 and the three failure modes` |
| `03bbc40be` | `refactor(server): the active-attention axis becomes one function` |
| `ed555669b` | `feat(server): expose clearedAt and clearReason on the receipt projection` |
| `8ea9a95f1` | `feat(server): dots, counts and grouping eligibility read active attention` |
| `5d6530f68` | `test(server): rewrite the two expectations the axis move invalidates` |
| `c19baf990` | `test(server): make the requestActivity retirement fixture reachable` |

### Test evidence

**RED** — the new suite before any production change (`fb8b024ea`), a compile failure naming exactly the
symbols the unit owes:

```
$ dart test --tags pg -j 1 test/data/repository/attention_active_attention_axis_pg_test.dart
Error: The getter 'activeOptional' isn't defined for the class 'AttentionDismissibleSql'
Error: The getter 'clearedAt' isn't defined for the type 'AttentionReceipt'
Error: The getter 'clearReason' isn't defined for the type 'AttentionReceipt'
Error: The getter 'isActiveOptional' isn't defined for the type 'AttentionReceipt'
00:00 +0 -1: Some tests failed.
```

**RED, behavioural** — after the predicate and projection commits, before the axis move landed in the
repository, and after it while the old expectations stood:

```
00:03 +15 -3: Some tests failed.
  … M1 — an Activity dot implies a non-empty Activity default list
  … clearing every child retires the synthetic requestActivity row
  … the repository never spells the axis out by hand

00:34 +133 -4: Some tests failed.       # scout PG list, before expectation updates
  attention_dismiss_sweep_pg_test.dart: loading …            (const evaluation)
  attention_undo_pg_test.dart: loading …                     (const evaluation)
  attention_repository_pg_test.dart: markSeen and markAllSeen …   Expected: <0> Actual: <2>
  my_work_attention_pg_test.dart: aggregates news and obligations …  Expected: <5> Actual: <3>
```

**GREEN** — the scout's PG list plus the new axis suite (baseline at `8545d580a` was `+182`; `+200` here is
those 182 plus the 18 new tests, none lost):

```
$ ./scripts/run_with_test_cleanup.sh --timeout 30m -- bash -c 'cd packages/server && dart test --tags pg -j 1 \
    attention_activity_stream / surface / repository / my_work / request_history / clear_operation /
    dismiss_sweep / undo / dismissible_predicate / outcome_dismissible / live_obligations / retention /
    predicate_unification / mark_seen_for_beacon / active_attention_axis'
00:46 +200: All tests passed!

$ … dart test -j 1 test/api/controllers/graphql/attention_graphql_test.dart \
      test/api/controllers/graphql/query_attention_payload_test.dart
00:00 +35: All tests passed!

$ ./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server
total: 0 (baseline: 0)
check-custom-lints: packages/server OK
```

**Client suites named by the scout** — `test/features/inbox`, `test/features/my_work`, `test/domain/attention`,
`work_activity_nav_indicators_test.dart`, `my_work_navbar_item_test.dart`:

```
$ … flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env …
00:12 +340: All tests passed!
```

**No client expectation needed updating.** Client `lib/` was not touched and the client suites drive their own
fixtures rather than the server projection, so the axis move is invisible to them until U14/U15 consume the new
fields. Named here because the brief asked for the list, and the list is empty.

STATUS: complete

---

## UNIT U10b — The axis move · VERIFY (2026-09-19)

**Layer:** verify (read-only). **Range:** `8545d580a..b6150cc3a`.

Axis move verified: indicators/summaries/default `unread` lists use `AttentionDismissibleSql.activeAttention`;
clear capture/apply uses `activeOptional`; `clearedAt`/`clearReason` on projection; two rewritten expectations
forced by D02/D09 (not weakened). §6 pinned-zone defect documented in axis test for U10c. **Gaps:** sweep/undo
not asserted against feed/summary; sweep apply `UPDATE` still inline optional predicate; failure-mode mutations
1/3 not re-run to assertion in verify (mutation 2 reproduced). Client 407 tests green on fakes — not server-path
evidence.

**Verifier verdict:** pass (with gaps named above).

---

## UNIT U10b — Sweep/undo round trip & the fourth spelling · INNER (remediation) (2026-09-19)

**Layer:** inner (remediation). **UNIT_BASE:** `b6150cc3a`. Two gaps from the U10b verify.

### GAP 1 — the fourth spelling, and a guard that is no longer a list

`attention_sweep_repository.dart`'s apply `UPDATE` hand-wrote `cleared_at IS NULL AND NOT requires_action`. It
now composes `AttentionDismissibleSql.activeOptional('receipt')`; the statement gained an alias
(`UPDATE public.notification_outbox AS receipt`) so the fragment has something to qualify.

**Did unifying change behaviour? No.** The hand-written pair and `activeOptional` are the same two conjuncts in
the other order — `NOT requires_action AND cleared_at IS NULL` — over the same row. No third clause was present
in either, no surface or `relay_received` filter was implied, and the `AS receipt` alias does not change which
rows the `account_id` / `id IN (…)` clauses select. The sweep, undo, clear and predicate suites all pass
unchanged, including the six exclusion tests written specifically to loosen this apply path.

The guard was the point of the gap, not the copy. It named two files; the copy lived in a third. It now scans
`lib/data/repository/attention_*.dart` as a **directory**, excluding only the predicate's home, so a fifth
spelling fails in a file that does not exist yet:

```
$ dart test -j 1 -N "no attention repository spells the axis out by hand" …axis_pg_test.dart
  Expected: empty
    Actual: ['lib/data/repository/attention_sweep_repository.dart']
00:00 +0 -1: Some tests failed.
```

### GAP 2 — the other two thirds of the circuit

Three tests in the axis suite, all driving the real `AttentionSweepRepository` (`dismissAll` / `undo`), each
reading all three shapes together via one `_activityShape` helper — the surface summary (the dot), the default
unread feed (the list) and `activityOffers` (the cards) — so a leg cannot be asserted on one shape and silently
skipped on the others:

| Test | Asserts |
|---|---|
| *a sweep empties the summary, the feed and the grouping together* | summary 2 → 0, feed non-empty → empty, pinned card's `eventUnseenCount` 1 → 0, and My Desk's row **untouched** at 1 (Set R excludes it) |
| *undo brings the summary, the feed and the grouping back* | after `undo`, all three shapes equal their pre-sweep values, and `restoredReceiptIds` is exactly the swept set |
| *neither the sweep nor its undo touches the pinned zone* | `appliedOutcomeBeaconIds` and `restoredOutcomeBeaconIds` both empty, and the two pinned cards keep their order and `totalCount` across both operations — owner decision A |

### Each new assertion proven able to fail

Four throwaway mutations, all reverted, nothing committed:

| Mutation (throwaway) | Test that went red | Output |
|---|---|---|
| grouping `event_unseen_count` FILTER reverted to `child.seen_at IS NULL` | *a sweep empties…* | `Expected: <0> Actual: <1>` — the card keeps a swept count |
| `activity_unread_total` FILTER reverted to `v.seen_at IS NULL` | *a sweep empties…* / *undo brings…* | `Expected: <0> Actual: <2>` — the tab lights after its own sweep |
| `activityOffers` ranked CTE drops any pinned beacon that has a cleared receipt | *neither the sweep nor its undo…* | `Expected: ['Baxisforeign','Baxisother'] Actual: ['Baxisother']` — sweeping a pinned card's noise deletes the question |
| `undoReceiptSql` re-stamps `cleared_at = now()` instead of `NULL` | *undo brings…* | `Expected: <2> Actual: <0>` — an undo window that does not undo |

The two mutations that were *also* tried and rejected as probes are worth naming: removing
`NOT IN eligible_pinned` from `dismissibleOutcomes`, and dropping `cleared_at = NULL` from the undo, both make
the sweep machinery throw `25P01 ROLLBACK TO SAVEPOINT` before any assertion is reached. Red, but red for a
mechanical reason — they prove nothing about the assertion, so they were replaced with the two above.

### Commits

| Hash | Subject |
|---|---|
| `d3c3db092` | `refactor(server): the sweep's apply composes the shared axis, and the guard covers the directory` |
| `b4d3b484e` | `test(server): assert the sweep and undo legs of the round trip, and the pinned zone` |

### Test evidence

```
$ ./scripts/run_with_test_cleanup.sh --timeout 30m -- bash -c 'cd packages/server && dart test --tags pg -j 1 \
    active_attention_axis / dismiss_sweep / undo / clear_operation / dismissible_predicate /
    predicate_unification / outcome_dismissible / surface / my_work / activity_stream'
00:35 +165: All tests passed!          # axis suite is 21, was 18 before this remediation

$ … dart test -j 1 test/api/controllers/graphql/attention_graphql_test.dart \
      test/api/controllers/graphql/query_attention_payload_test.dart
00:00 +35: All tests passed!

$ ./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server
total: 0 (baseline: 0)
check-custom-lints: packages/server OK
```

### Not touched

Ordering keys, `effectiveActivityAt`, `first_entry_at`, cursors, head reconciliation — **U10c**. The §6
pinned-reorder defect stays documented and unfixed, and its expectation is unchanged.

STATUS: complete

### Manager verdict — U10b · **ACCEPTED** (hard; inner Opus-low ✓ / verify pass / one remediation)

Overseer's gate: **1685 non-PG**, **985 PG / 24 known skips**, **423 client**. Commits `fb8b024ea` ·
`03bbc40be` · `ed555669b` · `8ea9a95f1` · `5d6530f68` · `c19baf990` · `b6150cc3a` · `d3c3db092` · `b4d3b484e` ·
`463d24752`.

**Indicators now read active attention, so everything U08 and U09 built is finally visible.** The round trip is
asserted for all three operations — clear, sweep and undo each reflected in the feed, the per-surface summary
and the grouping, with the pinned zone proven invariant across sweep and undo. The sweep and undo legs were
missing after the inner pass; the remediation added them.

**The predicate-duplication count reached six, and is now stopped structurally rather than by repair.** U10a
unified two known copies and discovered a third (`markAllSeen`, inline) and fourth (`eligible_pinned`,
duplicated in grouping). U10b found a fifth in the clear command's capture and apply re-check. The verifier
found a sixth in the sweep's apply. **Every one was found by the next layer, never the previous, and never by
reading.** The remediation extended the structural guard to scan the whole repository directory, so a
hand-written spelling fails the build even in a file nobody has touched yet — which matters because U10c and
U13 are about to change this same definition. The sixth copy, incidentally, did not differ in meaning: the
guard's blindness was the defect, not the copy.

**All three silent-failure modes were proven able to fail** by mutation: narrowed pinned eligibility makes the
unanswered forward vanish; a summary reverted to `seen_at` lights the tab over an empty list; a filtered
`max_created_at` reshuffles the pinned zone on clear.

**A methodological point worth keeping:** the remediation **discarded two of its own mutations as non-proofs** —
removing `NOT IN eligible_pinned` and dropping `cleared_at = NULL` from undo both crash the sweep with
`25P01 ROLLBACK TO SAVEPOINT` *before any assertion runs*. A mutation that kills the code before the assert
proves nothing about the assert. Replaced with four that fail on the assertion itself.

**Two rewritten expectations, both forced rather than weakened:** `my_work_attention_pg_test`'s `unseenCount`
5 → 3 (optional-only; obligations still asserted separately), and `attention_repository_pg_test` after
`markAllSeen` now expects 2 items with `unreadTotal == page.length` instead of 0 — which *strengthens* M1 and
encodes D02's read ≠ clear.

**Known product defect, deliberately carried to U10c:** the pinned zone **does** reorder when an optional event
arrives — a live §6 violation. The test pins today's behaviour with an explicit `reason:` naming it a defect,
because ordering is U10c's scope. **U10c must** replace `effective_activity_at` pinned ordering with stable
keys and rewrite that expectation so optional arrival cannot change relative pin order.

**Honest limit recorded:** the 423 green client tests are regression evidence only — they drive their own fakes
and stubbed summaries, and do not exercise the server's `cleared_at` axis or the new GraphQL fields until
U14/U15 consume them.

---
