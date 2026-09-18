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
