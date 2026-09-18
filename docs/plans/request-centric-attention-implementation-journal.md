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
