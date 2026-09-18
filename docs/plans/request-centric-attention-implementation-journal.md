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
