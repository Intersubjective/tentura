# Issue 162/180 implementation journal

Plan: `docs/plans/issue-162-180-review-package-state-plan.md` (revision 3)
Issues: #162 (package state invisible → HUD/checklist loop), #180 (leaver reviews block send)
Objective: make the reviewer's package state the UI's primary variable; optional = formerCommitter; drop auto-close on last send; notify author once when required packages are in; announce reopen.

## Run identity

- Repository: `/home/vader/MY_SRC/tentura`
- Branch: `fix/162-180-review-package-state`
- Starting HEAD: `ba996a3a82b01ad3487e9e62887105fecb3f8174` (`docs(review): plan the review package state and optional reviewers`)
- Overseer started: 2026-09-18T00:14:33+02:00
- Plan revision 3, decisions D1–D19 acknowledged.
- Escalation path at start: Astra (`gpt-6-astra` via `codex` 0.154.0) is installed; **rationed** (see below). Substitute if Astra unavailable: Opus 5 `--effort high`. Do not probe Astra until a rationed slot is spent.

## Baseline (verbatim, UNIT 00)

```
ba996a3a82b01ad3487e9e62887105fecb3f8174
fix/162-180-review-package-state
```

```
m0174.dart
m0175.dart
_migrations.dart
5:version: 7.15.0
flutter_bootstrap.js?v=7.15.0
67:const kDefaultMinClientVersion = '7.10.0';
```

Drift vs plan §3: **none**. `m0176` absent. `_autoCloseReviewWindow` still present at `evaluation_case.dart:1494` and `:1500`. Stop conditions not tripped.

## Pre-existing worktree (UNTOUCHABLE — never stage, reset, stash, or overwrite)

Modified:
- `.serena/project.yml`
- `docs/plans/constellation-pin-badge-zoom-lod-implementation-journal.md`

Untracked (non-exhaustive; all `??` at start): `CLAUDE.local.md`, `dart-defines`, many `docs/plans/*` (other plans/reviews/journals), `graph-ego-neighbors-layout-issue.md`, `key.fb`, `leo.key`, `out.key` (treat as secrets), `packages/image_cropper_for_web/build/`, `product_testing_*.md`, `tg_style_research.md`.

This plan's journal is the only new file UNIT 00 may add.

## Astra ration (user constraint)

Quota: ~3–4 uses until 06:00 CEST 2026-09-18, then ~3–4 more after reset. Usual fallback (Opus-high substitute, then overseer) still applies if a spent slot fails closed.

**Spend as inner executor, not as default solver.** Composer scout/verify still wrap every unit.

| Slot | When | Unit | Why |
|------|------|------|-----|
| A1 | current quota | UNIT 05 inner | transactional last-send nudge, idempotent `sourceEventKey`, concurrency PG — races + attention boundary |
| A2 | current quota | UNIT 10 inner | checklist is #162's primary surface: local skip, post-send stay+refresh, Flutter list at 360px×2.0 |
| A3 | current quota | UNIT 12 inner | HUD/banner nine-state × role × `allRequiredSent` matrix; deleting the getters that caused the loop |
| A4 | hold | emergency remediation of A1–A3 only | do not spend on 03/09/13 |
| B1–B3 | after 06:00 | Astra *review* of 10, 12, 05 (then 03) if already landed; else remaining ASTRA-inner units first | independent second look at the error-prone units |
| B4 | hold | UNIT 16 e2e/closeout defect inner | only if web e2e or PG closeout is red |

Opus-low inner for: 01, 02, 03, 04, 06, 07, 08, 09, 11, 13, 14, 15.
UNIT 03 is semantically hard (#180) but the plan ships literal code; Opus implements, overseer reads the diff line-by-line, Astra reviews after reset if the unit looked messy.
UNIT 11 is hard-class (D12 ambiguous error); Opus inner, overseer reads closely.
If Opus is unavailable: routine units degrade to Composer-only implement+verify; park hard units.

## Unit checklist

- [x] UNIT 00 journal and baseline — routine — overseer — complete
- [x] UNIT 01 drop auto-close — hard (close paths) — Opus inner — verify pass 2026-09-18
- [x] UNIT 02 m0176 `sent_at` + context — hard (many hops, PG) — Opus inner — verify pass 2026-09-18
- [x] UNIT 03 optional targets / counters — hard (D6/D7) — Opus inner — verify pass 2026-09-18
- [x] UNIT 04 GraphQL + client schema — routine — Opus inner — verify pass 2026-09-18
- [x] UNIT 05 author nudge — hard (races, idempotency) — **ASTRA inner** A1 — verify pass 2026-09-18 — overseer accepted (`d98a2e50b`)
- [x] UNIT 06 reopen announces — hard (tx order) — Opus inner — verify pass 2026-09-18 — overseer accepted (`4577edd2d`)
- [x] UNIT 07 l10n keys — routine — Opus inner — verify pass 2026-09-18 — overseer accepted (`f6da84625`)
- [x] UNIT 08 `ReviewPackageState` — routine — Opus inner — verify pass 2026-09-18 — overseer accepted (`996724eec`)
- [x] UNIT 09 client data/role/context — hard (DTO hops, codegen) — Opus inner (quota stop; overseer finished step 4) — verify pass 2026-09-18 — overseer accepted (`432d2839d`)
- [x] UNIT 10 checklist UI — hard (Flutter, #162) — Opus-high substitute (Astra A2 quota miss) — verify pass 2026-09-18 — overseer accepted (`0b27c5885`)
- [x] UNIT 11 paused/closed classify — hard (D12) — Opus inner — verify pass 2026-09-18 — overseer accepted (`d2876e587`)
- [x] UNIT 12 HUD + banner — hard (#162 loop) — **ASTRA inner** A3 — verify pass 2026-09-18 — overseer accepted (`2d3bdfeed`)
- [ ] UNIT 13 My Work cards — hard — Opus inner
- [x] UNIT 14 author dialogs + Updates — medium — Opus inner — verify pass 2026-09-18 — overseer accepted (`cc99f6d21`)
- [ ] UNIT 15 release 7.16.0 — routine — Opus inner
- [ ] UNIT 16 closeout — hard (PG + web e2e) — overseer matrix; Astra only if red

Never parallelize 02/03/04 or 09/10. Never skip or merge.

## Verification commands (plan)

See each unit's Verify block. All local `dart test` / `flutter test` / `check-custom-lints.sh` go through `scripts/run_with_test_cleanup.sh`. Do not wrap `run_client_integration_web_local.sh`. Do not use `flutter analyze` for custom lints. Generated files (`*.g.dart`, `_g/`) are never committed (D18).

## Unresolved decisions / blockers

None at start. Product decisions D1–D19 are frozen.

## UNIT 00 — complete — 2026-09-18T00:15:00+02:00

COMMITS: `d34fb0a9f docs: start issue 162/180 journal`
TESTS: n/a — journal + baseline only; commands recorded above
FILES: `docs/plans/issue-162-180-review-package-state-journal.md`
FINDINGS: baseline matches §3; `_autoCloseReviewWindow` still live; no `m0176`; client dirty files from an earlier snapshot (`beacon_fact_composer_sheet.dart`, `test_ids.dart`, `basic_chat_body.dart`) are **not** dirty now — current `git status --short -- packages/client packages/server` is empty
REMAINING: none for UNIT 00; next is UNIT 01 sandwich

---

## UNIT 01 — complete (verify pass 2026-09-18)

UNIT_BASE: `d34fb0a9f`
Inner: Opus-low (not Astra)
Owns (exclusive): `evaluation_case.dart`, `evaluation_case_test.dart`, `e2e_test_helpers.dart`, `beacon_hierarchy_child_independence_pg_test.dart`, `docs/beacon-evaluation-principles.md`

### scout — 2026-09-18

STATUS: complete

BRIEF: Remove the `evaluationFinalize` tail that calls `_autoCloseReviewWindow` when `_canCloseNow` is true, then delete `_autoCloseReviewWindow` entirely (~lines 1493–1553 in live `evaluation_case.dart`). Observable acceptance: (1) a successful package send before deadline leaves beacon `reviewOpen`, review window row `status == 0`, and does not invoke `ReviewFinalizationPort.closeAndFinalize`; (2) `reviewWindowStatus(author).canCloseNow == true` once all required author/committer packages are sent (status 2) while the window stays open; (3) `closeNow` still gates on `_canCloseNow` and calls `closeAndFinalize` with `authorCloseNow` — unchanged (`closeNow` group ~2610); (4) `evaluationFinalize` still calls `_ensureExpiredClosed` first — when `AttentionExpiryRepositoryPort.lockExpiredReviewWindowBeaconIds` returns the beacon, sweep closes via `closeAndFinalize` with `reviewExpired` (D2); (5) `grep -rn "_autoCloseReviewWindow" packages/server/lib packages/server/test` is empty post-edit.

Approach: Literal plan edits. Callers of `closeAndFinalize` from evaluation paths after delete: `closeNow` (~543), `AttentionExpirySweepCase.runDue` (~43). Only caller of `_autoCloseReviewWindow` was `evaluationFinalize` (~1494). Do not touch `_canCloseNow`, `closeAndFinalize`, or add a close flag to `evaluationFinalize`.

STEPS (commit-sized):
1. **Tests (red)** — `evaluation_case_test.dart` `group('evaluationFinalize')`: add four tests per plan; mirror `closeNow` fixture (`participantsResult`, `reviewStatusesResult`, `_TransactionStubBeaconRepo` with `BeaconStatus.reviewOpen`, `openWindow()`). Red meaningful: yes — today last-send triggers `closeAndFinalize` via auto-close. `canCloseNow` test: `_FakeEvaluationRepository.setReviewUserStatus` does **not** update `reviewStatusesResult`; after helper `evaluationFinalize`, set map to `{author: 2, helper: 2}` before `reviewWindowStatus` (real DB would already be 2). Deadline test: reuse `attention_expiry_sweep_case_test.dart` `_ExpiryRepository` pattern (`due = [beaconId]`), wire into `AttentionExpirySweepCase` in a local `buildTestEvaluationCase`; assert `closeAndFinalizeCalls` includes `reviewExpired` — `_FakeReviewFinalization` does not mutate beacon/window, so do not expect `_requireLiveReview` to throw unless you add a mutating fake. `author closeNow still closes`: optional duplicate of `closeNow` group test or one-line pointer — plan lists it; minimal `closeNow` call in finalize group is fine. Red meaningful for deadline: partial (sweep invocation is the behavior under test).
2. **Production delete** — `evaluation_case.dart`: remove `if (await _canCloseNow...) { _autoCloseReviewWindow... }` block; delete `_autoCloseReviewWindow` method + doc comment. Red meaningful: n/a (makes step 1 green). Run grep gate.
3. **E2E helper** — `e2e_test_helpers.dart` `triggerCloseNow` (~1015–1058): remove doc/behavior that treats `finishedArchive` as success without explicit close; drop `finishedArchive` from `_awaitMyWorkDeskAction` predicate; always tap My Work close or HUD `closeNow` before waiting for Archive; update comment at ~872 if it still implies auto-close-only navigation. Red meaningful: no (integration; not in UNIT verify).
4. **PG lifecycle shape** — `beacon_hierarchy_child_independence_pg_test.dart` `runGenericLifecycle`: after last `evaluationFinalize`, read real beacon/window status (expect `reviewOpen`), call `evaluationCase.closeNow(owner)`, then build `LifecycleOutcomeShape` from actual close outcome. Red meaningful: yes on PG after step 2 (today constants hide regression). Verify separately: `dart test ... beacon_hierarchy_child_independence_pg_test.dart` (pg tag).
5. **Docs** — `docs/beacon-evaluation-principles.md` line 28: replace “timeout, early close, or auto-close” with author close-now + deadline; keep unsent-rows-discarded sentence. Red meaningful: no.

TEST_CMD:
```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/domain/evaluation/evaluation_case_test.dart --exclude-tags pg
```
```bash
cd /home/vader/MY_SRC/tentura && grep -rn "_autoCloseReviewWindow" packages/server/lib packages/server/test
```
(Optional PG owns file: `cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/domain/use_case/beacon_hierarchy_child_independence_pg_test.dart`)

UNTOUCHABLE: journal pre-existing dirty/untracked list (`.serena/project.yml`, constellation journal, other `docs/plans/*`, keys, `image_cropper_for_web/build`, etc.); generated files; files outside UNIT 01 Owns.

RISKS:
- Live line numbers match plan (~1445 finalize, ~1497 auto-close, ~499 closeNow, ~148 `_ensureExpiredClosed`) — no blocker.
- Plan prose “closeNow and expiry sweep call `closeAndFinalize` directly” is correct; `_autoCloseReviewWindow` doc falsely claims shared path with author close-now — `closeNow` never called it.
- Historical quirk: `_autoCloseReviewWindow` used `authorCloseNow` reason with the **reviewer’s** `userId` as actor when triggered from last send — deleted with method.
- `_requireLiveReview` does not check `closesAt`; only `evaluationSubmit` throws `reviewWindowExpired`. Deadline close on finalize is **only** via `_ensureExpiredClosed` sweep, not in-finalize `_canCloseNow`.
- `triggerCloseNow` currently waits on Archive without tapping close when auto-close already happened — must change or e2e flakes after step 2.
- `nested-requests-implementation-plan.md` still names `_autoCloseReviewWindow` — out of Owns; do not edit in UNIT 01.

## Manager notes

Workers: read this journal fully before inspecting or editing. Append a checkpoint after meaningful progress. Append a final entry tagged `scout` / `inner` / `verify` / `finisher` before exit. Do not touch UNTOUCHABLE paths. Do not push. Do not invent user-facing strings. Owns lists in the plan are exclusive.

Prompt/log scratchpad (outside repo): `/tmp/overseer-162-180/`

### inner — 2026-09-18 — Opus 5 low

STATUS: complete

COMMITS (UNIT_BASE `d34fb0a9f`):
- `a17b5a773 fix(server): stop closing the review window on the last send`
- `4b34b5282 test(e2e): require an explicit author close after the last review send`
- `9862a4759 test(server): assert the real close outcome in the PG lifecycle shape`
- `7723de02e docs(evaluation): close paths are author close-now or the deadline`

TESTS:
- step 1/2 `dart test test/domain/evaluation/evaluation_case_test.dart --exclude-tags pg` — RED `+71 -3` (the three behavioural tests; the deadline-sweep test passes as a guard) → GREEN `+74`.
- grep gate `grep -rn "_autoCloseReviewWindow" packages/server/lib packages/server/test` — empty (exit 1).
- step 3 red n/a (integration wiring, not in unit Verify); `dart analyze integration_test/support/e2e_test_helpers.dart` — no errors.
- step 4 `dart test test/domain/use_case/beacon_hierarchy_child_independence_pg_test.dart` — GREEN `+2`.
- step 5 red n/a (docs).

FILES: `packages/server/lib/domain/use_case/evaluation_case.dart`, `packages/server/test/domain/evaluation/evaluation_case_test.dart`, `packages/client/integration_test/support/e2e_test_helpers.dart`, `packages/server/test/domain/use_case/beacon_hierarchy_child_independence_pg_test.dart`, `docs/beacon-evaluation-principles.md`.

FINDINGS:
- The four new tests live in a nested group `no auto-close on the last required send` inside `group('evaluationFinalize')`, so full names are `evaluationFinalize no auto-close on the last required send <name>`.
- Scout's fake-gap warning confirmed: `_FakeEvaluationRepository.setReviewUserStatus` does not touch `reviewStatusesResult`, so the group's `setUp` seeds `{author: 2, helper: 2}` (what a real DB would read inside the send) — that is what makes the red meaningful.
- `ReviewWindowStatusResult.windowComplete` is `bool?`, not `bool`; the PG shape needs `?? false`.
- PG shape now derives `finalizeStatus` from `closeNow(...).status` and `finalizeDidClose` from a post-close `reviewWindowStatus`; `finalizeTrustPairCount` stays the literal `0` (no outcome field carries it).
- `nested-requests-implementation-plan.md` still mentions `_autoCloseReviewWindow` — out of Owns, untouched.

REMAINING: none for UNIT 01.

### verify — 2026-09-18

STATUS: pass

TEST_OUTPUT:
- `dart test test/domain/evaluation/evaluation_case_test.dart --exclude-tags pg` (via `run_with_test_cleanup.sh`, 20m) — **+74, −0** (all passed).
- `grep -rn "_autoCloseReviewWindow" packages/server/lib packages/server/test` — **no matches** (exit 1).
- `dart test test/domain/use_case/beacon_hierarchy_child_independence_pg_test.dart` (via wrapper, 20m) — **+2, −0** (all passed).

RANGE: `d34fb0a9f..e136ba450` (6 commits: production+unit tests `a17b5a773`, e2e `4b34b5282`, PG `9862a4759`, docs `7723de02e`, journal inner `e136ba450`). Worktree: only pre-existing UNTOUCHABLE dirty/untracked; no uncommitted UNIT 01 code.

SCOPE: Diff touches only Owns files + this journal. No generated files; `_canCloseNow`, `closeNow`, and `closeAndFinalize` unchanged in production. No deleted or skipped tests; PG assertions tightened. `nested-requests-implementation-plan.md` still references removed symbol (out of Owns).

COMMITS: Steps 3–5 one commit each; unit tests folded into `a17b5a773` — **acceptable** (inner recorded RED `+71 −3` before delete in same session; four behavioural tests are real).

ACCEPTANCE: all plan UNIT 01 + scout criteria met (see user-facing verify summary in chat).

GAPS: none material (`reviewOpen` not named on stub beacon in unit test; PG `finalizeTrustPairCount` still literal 0).

### manager — UNIT 03 accepted — 2026-09-18T00:45:00+02:00

Overseer independently re-ran `evaluation_case_test.dart --exclude-tags pg` → `+82 All tests passed!`. Finalize loop matches plan literal. Both participant endpoints fill isOptional/rowStatus. `_canCloseNow` body unchanged. Follow-up: `a7feea820` ratchets the UNIT 01 attention-inventory count 4→3.

---

## UNIT 04 — in progress

UNIT_BASE: `a7feea820`
Inner: Opus-low (not Astra)

## UNIT 05 — in progress

UNIT_BASE: `9b98de071`
Inner: **ASTRA** (slot A1 of current quota). Fallback: Opus-high if Astra unavailable.

### scout — 2026-09-18 — UNIT 05

STATUS: complete

BRIEF: D14 — when the **last required** reviewer send makes `_canCloseNow` flip false→true, notify the **author once per window** via new `AttentionEventType.reviewAllPackagesIn` (not `reviewOpened`). Live `evaluationFinalize` (`evaluation_case.dart:1515–1575` at `9b98de071`) only writes `setReviewUserStatus(..., status: 2, markSent: true)` and calls `settleReviewerObligationOnPackageSend` **outside** any `TransactionalAttentionCase` boundary — no nudge exists yet. Wrap finalize’s status write + intent in `_attention!.runAction` (same pattern as `beaconClose` `:169` and `closeNow` `:508`). **Inside the transaction:** (1) `wasCloseableBefore = await _canCloseNow(beaconId)` **before** readiness loop + status write; (2) existing readiness loop unchanged; (3) if `st != 2`, `setReviewUserStatus` with `markSent: true`; (4) `isCloseableNow = await _canCloseNow(beaconId)` **after** write; (5) if `!wasCloseableBefore && isCloseableNow`, load `getReviewWindow` + `getBeaconById`, then `transaction.record(await _attentionIntents!.reviewAllPackagesIn(...))` with `authorUserId: beacon.author.id`, `beaconTitle: beacon.title`, `sourceEventKey: 'review_all_in:$beaconId:${window.openedAt.toUtc().toIso8601String()}'`, `actorUserId` = author (via builder’s `BeaconNotificationIntent.actorUserId`). Keep `settleReviewerObligationOnPackageSend` **after** the transaction (plan ties crash-safety to the nudge, not settlement). **Policy:** six switches follow `reviewOpened` branches except `_suppression → standard` (not mandatory), `_requiresAction → false`, `_presentationKey → 'review_all_packages_in'`; `_category → unblocksMe`; `_accessPolicy` + `_destination → review` like `:160`/`:231`. **Intent:** plan-literal `reviewAllPackagesIn` in `attention_intent_case.dart` — `NotificationPriority.normal`, `admittedUserIds: [authorUserId]`, `resolveContext: false`. **Contract:** append `eventTypes` row + matching `_expectedEventTypes` entry in `updates_event_contract_test.dart`; use `producer: 'EvaluationCase.evaluationFinalize'`, `recipientCategory: 'beacon_author'` (contract test does not validate category vocabulary — plan literal), `destinationFamily: 'review'`, `muteability: 'standard'`. Add a **second** `producers[]` row for `packages/server/lib/domain/use_case/evaluation_case.dart` with `eventType: reviewAllPackagesIn` (file already has one row for `reviewOpened`; coverage test only enforces uniqueness for `coordination_item/`). **Idempotency:** transition guard prevents redundant work on `st == 2` retries when already closeable; same `sourceEventKey` per window dedups edit→re-send (`attention_dispatch_repository.dart:40–65`). Former committers excluded from `_canCloseNow` (`:594–609`) — last required send is author + active committers only (UNIT 03).

STEPS (commit-sized):
1. **Attention surface** — `attention_models.dart`: insert `reviewAllPackagesIn` immediately after `reviewOpened`. `attention_policy.dart`: add the new enum to all six switches per BRIEF (exhaustive compile gate). `attention_intent_case.dart`: add `reviewAllPackagesIn` builder (plan block ~866–883).
2. **Contract** — `updates-event-contract.json` `eventTypes` + `producers`; mirror row into `updates_event_contract_test.dart` `_expectedEventTypes` (insert after `reviewOpened` row ~99–105).
3. **Tests (red)** — new group in `evaluation_case_test.dart` (reuse `no auto-close on the last required send` fixture: `requiredParticipants()`, `openWindow()`, `reviewStatusesResult` seeding). Four plan-named tests asserting `attention.recorded` filtered by `AttentionEventType.reviewAllPackagesIn`: single intent, correct `sourceEventKey` from `evalRepo.reviewWindowResult!.openedAt`, recipient author only, no `requiresAction`/no last-sender in payload (inspect `recipients` + stable fields only). **Fake fix (in Owns):** teach `_FakeEvaluationRepository.setReviewUserStatus` to set `reviewStatusesResult[userId] = status` so in-transaction `_canCloseNow` works without manual post-hoc map patches; optional `Map<String,int>? reviewUserStatusByUser` override for author-as-last-sender (`getReviewUserStatus` is currently one global `reviewUserStatusResult` for all users — author-last test needs per-user status or a dedicated fake subclass in-test).
4. **Production** — `evaluationFinalize`: refactor body into `_attention!.runAction(actorUserId: userId, action: (transaction) async { ... })`; null `_attention`/`_attentionIntents` must not ship in prod — match existing `_attention!` discipline. Red meaningful: steps 3 fails with zero `reviewAllPackagesIn` intents before step 4.
5. **PG concurrency (overseer widen)** — plan requires `two simultaneous last sends emit one notification` tagged `pg`; **not** in strict Owns. Add to `evaluation_repository_review_status_pg_test.dart` or sibling, cloning `review_obligation_settlement_pg_test.dart` `_buildEvaluationCase` + real `AttentionDispatchRepository`, two writers/serial transactions, count `attention_occurrence` rows for `event_type = 'reviewAllPackagesIn'` and matching `source_event_key`. Skip if disposable DB unreachable (same harness as UNIT 02).

TEST_CMD:
```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/domain/evaluation/evaluation_case_test.dart test/architecture/updates_event_contract_test.dart --exclude-tags pg
```
```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/data/repository/evaluation_repository_review_status_pg_test.dart --tags pg
```
(second command only after overseer widens Owns for PG file + test is written)

UNTOUCHABLE: pre-existing dirty/untracked; generated; **client**; do not push.

RISKS:
- **Owns vs CI (attention_policy_test):** `attention_policy_test.dart` iterates every contract `eventTypes` row and `_fixtureFor` throws on unknown names — **not** in UNIT 05 Owns. Adding `reviewAllPackagesIn` to the contract without a fixture breaks `dart test test/domain/attention/attention_policy_test.dart` on full-package CI even when unit Verify passes. **Overseer must widen Owns** for a `'reviewAllPackagesIn'` fixture (reason `authorOfBeacon`, role `_baseRole`) or authorize a minimal cross-file fix before merge.
- **Owns vs PG concurrency:** PG test file absent from Owns — `BLOCKED` on strict plan until widened; scenario matrix row 13 depends on it.
- **Plan `producers` JSON shape:** live `producers[]` uses `useCase` file paths; plan snippet uses `"producer": "EvaluationCase.evaluationFinalize"` in `eventTypes` only — mirror **`eventTypes`** six-field shape in Dart; add **`producers`** row with `useCase: packages/server/lib/domain/use_case/evaluation_case.dart`, `eventType: reviewAllPackagesIn`, same `recipientCategory`/`destinationFamily`/`muteability`/`coveringTest`.
- **`recipientCategory`:** plan says `beacon_author` (not an existing token in `_expectedEventTypes`); contract test accepts any non-empty string — use plan literal and journal the choice.
- **Fake `getReviewUserStatus`:** single scalar breaks multi-actor finalize tests unless widened; `_canCloseNow` already uses `reviewStatusesResult` map — keep map authoritative and align `setReviewUserStatus` writes (scout-recommended).
- **`st == 2` retry:** no status write; if map already all-2, `wasCloseableBefore` true → no second intent (transition guard).
- **Edit after nudge:** `canCloseNow` false again; re-send triggers transition true again but **same** `sourceEventKey` → DB/idempotent record; unit harness `_RecordingDispatch` may append duplicates unless test filters by key or simulates dispatch dedup — assert **one** intent with the window key or count distinct keys.
- **Author-as-last-sender:** include author in `requiredParticipants` with role 0; seed `{author: 1, helper: 2}` statuses, finalize as author — recipient must still be author (`admittedUserIds: [authorUserId]`).
- **Line drift:** `evaluationFinalize` ~1515; `_canCloseNow` ~594; `reviewOpened` intent ~322; policy switches ~65/120/160/231/274/312 — OK.
- **Inventory test:** no new `requestStatusChanged` site expected; do not add `.reviewAllPackagesIn` to `transactional_attention_producer_inventory_test.dart` migrated list unless overseer widens (optional hygiene, not in Verify).

### scout — 2026-09-18 — UNIT 04

STATUS: complete

BRIEF: Expose UNIT 03 domain fields on the V2 GraphQL types and hand-sync `packages/client/lib/data/gql/schema.graphql` (D18). **Participant:** add `isOptional`, `rowStatus`, `committedAt`, `offerMessage`, `forwarderDisplayName` on `gqlTypeEvaluationParticipant` (`custom_types.dart` ~924) and in `evaluationParticipantToGqlMap` (`gql_v2_dto_maps.dart` ~103). **Window status:** add the nine UNIT 03 counters/flags + `sentAt` on `gqlTypeReviewWindowStatus` (~971) and in `reviewWindowStatusToGqlMap` (~130). Date fields: `committedAt` / `sentAt` → `dto.x?.toUtc().toIso8601String()` (same pattern as `openedAt`/`closesAt`). **Compile gap:** `EvaluationParticipantResult` at `a7feea820` has `isOptional`/`rowStatus` only — **not** `committedAt`/`offerMessage`/`forwarderDisplayName`. Data already lives on `BeaconEvaluationParticipantRecord` / `EvaluationParticipantDraft` and is filled at DB/graph (UNIT 02) but never copied into the gql_public DTO or `evaluation_case.dart` participant constructors (~703, ~816). Strict UNIT 04 Owns cannot compile `dto.committedAt` in the mapper. **Overseer must widen Owns** (recommended minimal slice, literal) before or in the same commit as GraphQL: `evaluation_participant_result.dart` — add `DateTime? committedAt`, `String offerMessage` (default `''`), `String? forwarderDisplayName`; `evaluation_case.dart` — pass `row.committedAt`, `row.offerMessage`, `row.forwarderDisplayName` in **both** `evaluationParticipants` and `evaluationDraftParticipants` (`row` types already expose the three fields). Without that widen, write `BLOCKED` per plan §0 — do not stub constants in the mapper. `ReviewWindowStatusResult` already carries all nine fields + `sentAt`; mapper-only work suffices for window status.

STEPS (commit-sized):
1. **(If widened)** DTO + case wire — three participant context fields on `EvaluationParticipantResult` and both participant endpoints (see BRIEF). Red meaningful: compile of `gql_v2_dto_maps.dart` after step 3.
2. **`custom_types.dart`** — append plan-literal `field(...)` entries to `gqlTypeEvaluationParticipant` and `gqlTypeReviewWindowStatus` (nullability exactly as plan §UNIT 04 steps 1–2: participant `isOptional`/`rowStatus`/`offerMessage` non-null; `committedAt`/`forwarderDisplayName` nullable `graphQLString`; status ints/bools nullable like existing `reviewedCount`/`canCloseNow`; `sentAt` nullable `graphQLString`).
3. **`gql_v2_dto_maps.dart`** — extend both map functions with matching keys; ISO only on `committedAt` and `sentAt`.
4. **`schema.graphql`** — on `v2_EvaluationParticipant` (~7756) and `v2_ReviewWindowStatus` (~8028), add the same fields with GraphQL nullability mirroring step 2 (use `Boolean!` / `Int!` / `String!` where server uses `.nonNullable()`). Keep alphabetical field order within each type to match file style. Do **not** edit any `packages/client/**/*.graphql` query documents (UNIT 09).
5. **Grep acceptance** — second Verify command must hit all three symbol names in `schema.graphql`.

TEST_CMD:
```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --exclude-tags pg
```
```bash
cd /home/vader/MY_SRC/tentura && grep -n "viewerPackageOptional\|unsentStartedPackages\|rowStatus" packages/client/lib/data/gql/schema.graphql
```

UNTOUCHABLE: pre-existing dirty/untracked; generated `*.g.dart` / `_g/`; client `.graphql` documents; do not `git add -f` generated; do not push.

RISKS:
- **Owns vs compile (primary):** mapper references `dto.committedAt`/`offerMessage`/`forwarderDisplayName` — requires overseer-widened DTO + `evaluation_case.dart` fills or `BLOCKED`.
- **`offerMessage` non-null on wire:** GraphQL map must always emit a string (`''` when empty); DTO default `''` matches `BeaconEvaluationParticipantRecord`.
- **Draft vs live source:** draft path reads `EvaluationParticipantDraft`; live path reads `BeaconEvaluationParticipantRecord` from `listParticipants` — same three property names.
- **`query_evaluation_test.dart`:** contract test only asserts ack-tag additive fields (`containsAll`); no change required unless someone tightens it — new fields are additive.
- **No manual map constructors** elsewhere — only `evaluationParticipantToGqlMap` / `reviewWindowStatusToGqlMap` in `query_evaluation.dart`; no test map literals listing all participant keys.
- **Full-package `dart test --exclude-tags pg`:** mandatory per plan; journal UNIT 03 noted a pre-existing inventory red — **re-checked at scout:** `transactional_attention_producer_inventory_test.dart` is **green** (`evaluation_case.dart` expects 3 `requestStatusChanged` sites, live count 3). Full suite should be viable for first green; if red, likely unrelated architecture/pg-less drift — fix only if this unit’s diff caused it.
- **Client codegen:** ferry not run in this unit; only `schema.graphql` hand edit — UNIT 09 runs documents + codegen.

### verify — 2026-09-18 — UNIT 04

STATUS: pass

TEST_OUTPUT:
- `dart test --exclude-tags pg` (via `run_with_test_cleanup.sh`, 20m) — **+1638, −0** (~10.3s).
- `grep -n "viewerPackageOptional\|unsentStartedPackages\|rowStatus" packages/client/lib/data/gql/schema.graphql` — lines **7773** (`rowStatus`), **8051** (`unsentStartedPackages`), **8053** (`viewerPackageOptional`).

RANGE: `a7feea820..9b98de071` (3 commits: `c289b3e2f` DTO+case context, `6cbe53dec` GraphQL+schema, `9b98de071` journal). Worktree: only pre-existing UNTOUCHABLE dirty/untracked; no uncommitted UNIT 04 code.

SCOPE: Commits touch plan Owns (`custom_types.dart`, `gql_v2_dto_maps.dart`, `schema.graphql`) plus scout-authorised widen (`evaluation_participant_result.dart`, `evaluation_case.dart`, `evaluation_case_test.dart`). No `packages/client/**/*.graphql` query documents; no `*.g.dart` / `_g/` in range. `evaluationParticipantToGqlMap` adds all five participant fields; `reviewWindowStatusToGqlMap` adds all nine window fields; `committedAt`/`sentAt` use `?.toUtc().toIso8601String()` matching `openedAt`/`closesAt`. `gqlType*` nullability matches plan (participant `isOptional`/`rowStatus`/`offerMessage` non-null; context strings nullable except `offerMessage`).

ACCEPTANCE (plan UNIT 04):
- **Server tests green** — **met** — +1638 non-pg.
- **Grep prints new fields from client schema** — **met** — three symbols present on `v2_EvaluationParticipant` / `v2_ReviewWindowStatus`.
- **Both participant endpoints pass context fields** — **met in production** (`evaluationParticipants` ~731–733, `evaluationDraftParticipants` ~843–845); **tests** — `participants carry the commitment context fields` (`evaluationParticipants`), `draft participants carry the commitment context fields` (`evaluationDraftParticipants`).
- **No client `.graphql` documents yet** — **met** — only `schema.graphql` (+14 lines).

GAPS:
- **No API-layer test** asserts GraphQL resolver maps emit ISO strings for `committedAt`/`sentAt` (domain DTO tests only).
- **Widen beyond strict Owns** — DTO/case/tests in `c289b3e2f`; required for mapper compile (scout-predicted); acceptable.
- **Client ferry codegen / query field selection** — deferred UNIT 09 (inner REMAINING).

### manager — UNIT 02 accepted — 2026-09-18T00:32:00+02:00

Overseer independently re-ran `dart test test/domain/evaluation --exclude-tags pg` → `+120 All tests passed!`. Verifier PG `+3`. Demotion SQL still `status = 1, updated_at = now()` only. `markSent: true` only on finalize. Extra Owns files are +14 signature lines. Legacy context columns still written. No generated files committed.

---

## UNIT 03 — complete (verify pass 2026-09-18)

UNIT_BASE: `700bc8b2c`
Inner: Opus-low (not Astra); overseer will read the optionality/finalize diff line-by-line. Astra review after 06:00 if messy.

### manager — UNIT 01 accepted — 2026-09-18T00:24:00+02:00

Overseer independently re-ran `evaluation_case_test.dart --exclude-tags pg` → `+74 All tests passed!` (4.2s). Grep empty. Production diff is a 59-line delete of the auto-close tail + `_autoCloseReviewWindow`; `closeNow` / `_canCloseNow` / `closeAndFinalize` untouched. Untouchables preserved. Tests-folded-into-fix is a process miss, not a product miss — red was recorded before the delete.

### scout — 2026-09-18 — UNIT 03

STATUS: complete

BRIEF: D6/D7 — `formerCommitter` (db role `3`) is optional for package send and for progress counters; required targets still gate `evaluationFinalize`. Add `isOptional` + `rowStatus` to `EvaluationParticipantResult` (leave `isSubmitted`). Fill both in `evaluationParticipants` (~612) and `evaluationDraftParticipants` (~762, ctor ~813): `isOptional` ⇔ `EvaluationParticipantRole.fromDb(role) == formerCommitter` (draft: `row.role == formerCommitter`); `rowStatus` ⇔ `ev?.status ?? -1` (live participants: use full `ev`, not draft-only `useEv`). Replace `evaluationFinalize` readiness loop (~1471–1482) with the plan’s literal block (`listParticipants` + skip `formerCommitter` + skip stale vis without participant). Extend `ReviewWindowStatusResult` with nine fields; implement in `reviewWindowStatus` (~1017): viewer-scoped split counters mirror today’s `reviewedCount`/`totalCount` loop but partition by participant role from `listParticipants`; `reviewed*` = visible target has **any** stored eval row (`evByTarget[id] != null`); keep legacy `reviewedCount`/`totalCount` unchanged. `viewerPackageOptional` = viewer’s participant row role is `formerCommitter`. Beacon-scoped: `allRequiredSent` = `_canCloseNow(beaconId)` (do **not** edit `_canCloseNow` ~594); `unsentStartedPackages` / `sentReviewerCount` from `listReviewStatusesForBeacon` counting status `1` / `2` for enrolled reviewers (same participant list semantics as close). **Do not** touch `_requiredPackagesAllSentLocked` (lives in `evaluation_repository.dart:820`, not `evaluation_case.dart`).

STEPS (commit-sized):
1. **DTOs** — `evaluation_participant_result.dart`: add `required bool isOptional`, `required int rowStatus` + fields on ctor. `review_window_status_result.dart`: add nine nullable fields (`int?`/`bool?`/`String?` for `sentAt`, matching existing `reviewedCount` style).
2. **Tests (red)** — seven named tests in `evaluation_case_test.dart` per plan. Fixture notes: default `_FakeEvaluationRepository` has **empty** `visibilityResult` — today’s `evaluationFinalize` tests pass without eval rows; new finalize tests **must** set `visibilityResult`, `participantsResult`, and `listEvaluationsForEvaluatorResult` (draft/submitted rows for required targets only). Reuse `no auto-close` group patterns (`requiredParticipants()`, `openWindow()`, status maps). `a softened committer is optional`: build commitment history with `CommitmentEventKind.acknowledgementSoftened` (see `commitment_state_test.dart` / graph builder withdraw fixture) + active offer → `evaluationParticipants` or `evaluationDraftParticipants` on open beacon. `counters split…`: 3 visibility rows (2× role 1, 1× role 3), eval rows on all three, assert `reviewWindowStatus` split fields **and** legacy counts still `reviewedCount == 3`, `totalCount == 3`. `draft participants carry…`: open-beacon `evaluationDraftParticipants` with graph builder + commitment repo (copy `beaconClose everHadCommitter` setup ~2499).
3. **Production** — `evaluation_case.dart`: participant endpoints + `reviewWindowStatus` + finalize loop literal. For `hasWindow: false` early return, new status fields stay null (no behavior change for absent window).
4. **sentAt gap** — Plan field `sentAt` needs DB `beacon_review_status.sent_at`, but `EvaluationRepositoryPort` has no read API (only `getReviewUserStatus` → `int?`). **Not in UNIT 03 Owns.** Implementer: add `sentAt` to `ReviewWindowStatusResult` and wire `null` in production until overseer widens Owns for `getReviewPackageSentAt` (port + repo + mock) **or** write `BLOCKED` if tests require non-null. Plan’s UNIT 03 test list does **not** name a `sentAt` test; user acceptance omits it — nullable stub is acceptable for this unit if documented in journal inner.

TEST_CMD:
```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/domain/evaluation/evaluation_case_test.dart --exclude-tags pg
```

UNTOUCHABLE: journal pre-existing dirty/untracked; generated files; client; GraphQL (UNIT 04); `evaluation_repository.dart` / port unless overseer widens for `sentAt` read; do not change `_canCloseNow` or `_requiredPackagesAllSentLocked`.

RISKS:
- **Line drift (OK):** `evaluationParticipants` 612, `evaluationDraftParticipants` 762/813, `reviewWindowStatus` 1017, `evaluationFinalize` 1448, `_canCloseNow` 594 — plan §636 line refs are ~3 lines early.
- **Plan symbol drift:** `_requiredPackagesAllSentLocked` is **not** in `evaluation_case.dart` (plan §636 “:591” pairs it with `_canCloseNow`); real symbol is `evaluation_repository.dart:820` — constraint still “do not change”.
- **Finalize loop delta:** Live loop (~1471) iterates `vis` only, no `listParticipants`, no stale-vis skip; replacement is plan-literal — verify diff matches block exactly.
- **`rowStatus` vs `isSubmitted`:** Live `isSubmitted` is true for draft/submitted/final_; `rowStatus` is raw `ev?.status ?? -1` (can be `3` responded) — do not conflate.
- **`evaluationDraftParticipants`:** `rowStatus` should use `ev?.status ?? -1` even when `useEv` nulls draft-only display fields (plan: “draft row it already loads”).
- **Fake `setReviewUserStatus`:** ignores `markSent` — irrelevant unless `sentAt` read is added to fake later.

---

## UNIT 02 — complete (verify pass 2026-09-18)

UNIT_BASE: `e136ba450`
HEAD: `700bc8b2c`
Inner: Opus-low (not Astra)
Owns: m0176 + Drift tables + port/mapper/repo/draft/graph builder/evaluation_case + pg test (see plan UNIT 02)

### scout — 2026-09-18

STATUS: complete

BRIEF: Add migration `m0176` (`beacon_review_status.sent_at`; participant `committed_at`, `offer_message`, `forwarder_display_name`), Drift columns + local codegen (not committed). `setReviewUserStatus(..., markSent: true)` sets `sent_at` once on finalize (`evaluationFinalize` ~1481 when `st != 2`); demotion SQL at `evaluation_repository.dart:392–398` and all other status writes must not touch `sent_at`. Graph builder still writes legacy `contributionSummary` / `causalHint` (incl. ` — participation ended`); new draft fields from `offer.createdAt`, `offer.message`, forwarder display name. Observable acceptance: SQL can read non-null `sent_at` after send while status may be `1` after edit; participant rows carry structured columns; legacy text columns still populated on close.

Approach: Plan literals match live code (no `m0176`; latest `m0175`; `sentAt` absent from `beacon_review_statuses.dart`; port/repo `setReviewUserStatus` has no `markSent`; `insertParticipant` six-arg only; `BeaconEvaluationParticipantRecord` four fields; `_committerParticipant` ~173–196 builds English legacy strings only). Follow `m0175` migration shape; register `part` + list entry after `m0175`. PG harness: clone `evaluation_repository_submit_atomic_pg_test.dart` (`DisposablePgTarget`, `setUpDisposablePgWriter`, `openDisposablePgDatabase`, per-test SQL seed).

STEPS (commit-sized):
1. **Migration + register** — `m0176.dart` (plan SQL verbatim); `_migrations.dart` `part 'm0176.dart';` after `m0175`, `m0176,` after `m0175,`. Red meaningful: no (schema only until Drift/code paths land).
2. **Drift tables + codegen** — `beacon_review_statuses.dart` `sentAt`; `beacon_evaluation_participants.dart` three columns; `cd packages/server && dart run build_runner build --delete-conflicting-outputs` (do not commit `*.g.dart`). Red meaningful: no.
3. **Port + repo `sent_at`** — `evaluation_repository_port.dart` `bool markSent = false`; `evaluation_repository.dart` `setReviewUserStatus` `sentAt: markSent ? Value(PgDateTime(...)) : const Value.absent()`; `evaluation_case.dart` finalize call `status: 2, markSent: true`. Confirm demotion `UPDATE` stays `status` + `updated_at` only. Red meaningful: PG test `finalize stamps sent_at` (after step 6) — yes.
4. **Participant context round trip** — `evaluation_participant_draft.dart` three fields; `_committerParticipant` sets `committedAt: offer.createdAt`, `offerMessage: offer.message`, `forwarderDisplayName`; forwarder/author drafts per plan; `insertParticipant` + repo companion; `beacon_evaluation_record.dart`; `evaluation_mapper.dart`; `beaconClose` loop ~294 passes draft fields; `evaluation_repository_mock.dart`. Red meaningful: graph builder tests (step 5) — yes.
5. **Unit tests (non-pg)** — `evaluation_participant_graph_builder_test.dart`: four named tests per plan (`committedAt` vs `updatedAt` for former committer with `withdrawAfterAck` + stale `updatedAt`; empty message; forwarder `committedAt` null). Red meaningful: yes before step 4.
6. **PG tests** — new `evaluation_repository_review_status_pg_test.dart` `@Tags(['pg'])`, own `TENTURA_*_TEST_DB` prefix: (a) `setReviewUserStatus(status: 2, markSent: true)` or thin `EvaluationCase.evaluationFinalize` → `sent_at` not null; (b) seed `status=2` + `sent_at`, open window, `submitEvaluationAtomic` → `status=1`, `sent_at` unchanged; (c) seed status row + window, `deleteReviewScaffoldingForBeacon` → no `beacon_review_status` row (reopen path). Red meaningful: yes before steps 3–4 for (a)(b); (c) after repo method exists. Optional commit split: schema+drift | domain+repo+case | tests.

TEST_CMD:
```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/domain/evaluation --exclude-tags pg
```
```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/data/repository/evaluation_repository_review_status_pg_test.dart --tags pg
```

UNTOUCHABLE: journal pre-existing dirty/untracked (`.serena/project.yml`, constellation journal, other `docs/plans/*`, keys, `image_cropper_for_web/build`, etc.); generated `*.g.dart` / `_g/`; client; GraphQL; UNIT 03+ files.

RISKS:
- **Owns vs compile:** `dart test test/domain/evaluation` compiles `evaluation_case_test.dart`, whose `_FakeEvaluationRepository` / `_ParticipantPkeyEnforcingEvaluationRepository` override `setReviewUserStatus` and `insertParticipant` — must add new optional params or verify fails analyze. File is **not** in UNIT 02 Owns; strict plan ⇒ `BLOCKED` until overseer widens Owns for signature-only fake updates (or allows minimal cross-file compile fix). Other `EvaluationRepositoryPort` fakes (coordination, commitment_gates) not compiled by this Verify but break full `dart test`.
- **Finalize idempotency:** When `st == 2`, finalize skips `setReviewUserStatus` (~1480) — `sent_at` not rewritten on retry (intended).
- **`clearOne` / `evaluationSubmit`** call `setReviewUserStatus(status: 1)` without `markSent` — must not clear `sent_at` (Drift absent + demotion SQL unchanged).
- **Backfill:** m0176 sets `sent_at = updated_at` for legacy `status = 2` only; new sends use `markSent` timestamp.
- **Former-committer date test:** assert `committedAt == offer.createdAt`, not `offer.updatedAt` (reopen/grace scenario).
- **insertOnConflictUpdate:** new participant columns must be in `BeaconEvaluationParticipantsCompanion.insert` or reopen rematerialization drops structured fields.
- Live `evaluationFinalize` readiness loop unchanged in this unit (optional-target skip is UNIT 03).

### inner — 2026-09-18 — Opus 5 low

STATUS: complete

COMMITS (UNIT_BASE `e136ba450`):
- `c5e01afe4 feat(server): add m0176 for review sent_at and participant context`
- `fcd9a25a2 feat(server): add Drift columns for sent_at and participant context`
- `d5a0a2336 test(server): pin structured participant context on evaluation drafts`
- `697f43160 feat(server): fill structured participant context on evaluation drafts`
- `c88674d5c feat(server): stamp sent_at on package send and persist participant context`
- `c86667048 test(server): pin sent_at stamping, demotion and reopen deletion on PG`

TESTS:
- step 1 (migration) red n/a — schema only, unreachable from Dart until Drift lands; `dart analyze _migrations.dart` clean.
- step 2 (Drift + codegen) red n/a — generated code only; `build_runner build --delete-conflicting-outputs` wrote 636 outputs, `sentAt` present in `tentura_db.g.dart` (not committed, gitignored).
- step 3 `dart test test/domain/evaluation --exclude-tags pg` — RED `+111 -1` (graph-builder test file failed to *load*: `EvaluationParticipantDraft` had no `committedAt`/`offerMessage`/`forwarderDisplayName`) → GREEN `+120`.
- step 4 same TEST_CMD — GREEN `+120`; `dart analyze lib test` has zero errors/warnings after the signature-only fake widening.
- step 5 `dart test test/data/repository/evaluation_repository_review_status_pg_test.dart --tags pg` — GREEN `+3`. Red proven by temporarily forcing `sentAt: const Value.absent()` in `setReviewUserStatus`: `+1 -2` (`finalize stamps sent_at`, `editing a card after send demotes status to 1 and keeps sent_at`). Implementation restored byte-for-byte before commit (`git diff -- packages/server/lib` empty).

FILES:
- new: `packages/server/lib/data/database/migration/m0176.dart`, `packages/server/test/data/repository/evaluation_repository_review_status_pg_test.dart`
- `packages/server/lib/data/database/migration/_migrations.dart`, `.../table/beacon_review_statuses.dart`, `.../table/beacon_evaluation_participants.dart`
- `packages/server/lib/domain/port/evaluation_repository_port.dart`, `.../domain/entity/evaluation/beacon_evaluation_record.dart`, `.../data/mapper/evaluation_mapper.dart`, `.../data/repository/evaluation_repository.dart`, `.../data/repository/mock/evaluation_repository_mock.dart`
- `packages/server/lib/domain/use_case/evaluation/evaluation_participant_draft.dart`, `.../evaluation_participant_graph_builder.dart`, `.../domain/use_case/evaluation_case.dart`
- `packages/server/test/domain/evaluation/evaluation_participant_graph_builder_test.dart`
- signature-only widening (overseer-authorised, D17): `packages/server/test/domain/evaluation/evaluation_case_test.dart`, `packages/server/test/domain/use_case/coordination_case_revert_test.dart`, `packages/server/test/support/commitment_gates_harness.dart`

FINDINGS:
- **Widening was narrower than the scout predicted.** Only three extra files needed the new optional params. `query_evaluation_test.dart`, `beacon_hierarchy_visibility_pg_support.dart` and the Mockito `extends Fake` classes did **not** need overrides — the analyzer accepted them unchanged. Inside `evaluation_case_test.dart` two classes needed `insertParticipant` widened (`_FakeEvaluationRepository` and `_ParticipantPkeyEnforcingEvaluationRepository`) but only `_FakeEvaluationRepository` needed `setReviewUserStatus`. Total widening: **+14 lines, all parameter declarations**; no assertion, no body, no behaviour touched.
- `beacon_evaluation_participants.dart` had no `drift_postgres` import (it had no timestamp column before) — adding `committedAt` required adding `import 'package:drift_postgres/drift_postgres.dart';`. `beacon_review_statuses.dart` already imported it.
- The graph builder already resolved the forwarder's display name for the legacy `causalHint`; `_committerParticipant` now also stores it as `forwarderDisplayName`, so no new repository round trip was introduced.
- `offer.createdAt` is the only date on the offer that survives a withdraw/reopen; `offer.updatedAt` moves. The former-committer test asserts `committedAt == offer.createdAt` **and** `isNot(offer.updatedAt)` with a 9-day gap, so a future switch to `updatedAt` cannot pass silently.
- Confirmed the two non-finalize `setReviewUserStatus` call sites (`evaluation_case.dart:989` clear-one, `:1366` submit) both write `status: 1` with `markSent` defaulted false, and the `2 → 1` demotion SQL at `evaluation_repository.dart:392–398` is untouched — `sent_at` survives both paths.
- `deleteReviewScaffoldingForBeacon` already deleted `beacon_review_status` rows wholesale, so the reopen acceptance needed no production change; the PG test now pins it.
- The PG suite uses its own `TENTURA_EVAL_REVIEW_STATUS_TEST_DB` env var / `tentura_test_eval_review_status` prefix, and its `setUpAll` asserts `sent_at` exists in `information_schema` — the disposable target runs the full migration list, which is the only automated proof that m0176 is reachable.
- No generated file was committed; `*.g.dart` is gitignored in this package, so `git add` of the source tables staged sources only.

REMAINING: none for UNIT 02. `markSent` reaches the DB but is not yet exposed over GraphQL (UNIT 04) and the structured participant columns have no reader yet (UNIT 09) — both are later units by design.

### verify — 2026-09-18

STATUS: pass

TEST_OUTPUT:
- `dart test test/domain/evaluation --exclude-tags pg` (via `run_with_test_cleanup.sh`, 20m) — **+120, −0** (all passed, ~4.1s).
- `dart test test/data/repository/evaluation_repository_review_status_pg_test.dart --tags pg` (via wrapper, 20m) — **+3, −0** (all passed, ~6.3s). First run printed `All tests passed!` then exited **255** with a post-suite `PathNotFoundException` copying `dart_test.kernel.*` into `.dart_tool/test/` (test-cleanup race); immediate re-run exited **0** with the same **+3**.

RANGE: `e136ba450..700bc8b2c` (7 commits: `c5e01afe4` … `c86667048`, journal `700bc8b2c`). Worktree: only pre-existing UNTOUCHABLE dirty/untracked; no uncommitted UNIT 02 code.

SCOPE: Diff touches plan Owns + journal + three signature-only test fakes (`evaluation_case_test.dart`, `coordination_case_revert_test.dart`, `commitment_gates_harness.dart`); no `*.g.dart` in commit range (`**.g.dart` gitignored). Demotion SQL at `evaluation_repository.dart:404–408` still `SET status = 1, updated_at = now()` only. `setReviewUserStatus` uses `Value.absent()` for `sentAt` unless `markSent`; no code path sets `sent_at` null. `_committerParticipant` still builds `contributionSummary` / `causalHint`; `beaconClose` still passes them to `insertParticipant`.

ACCEPTANCE:
- **DB can answer “was this package ever sent, and when”** — **met** — `m0176` adds `sent_at`; `evaluationFinalize` passes `markSent: true`; PG tests stamp, demote-with-preserved-`sent_at`, and assert column via disposable migrations.
- **Legacy context columns still written** — **met** — graph builder unchanged English legacy strings (+ participation-ended suffix); four new unit tests assert structured fields alongside legacy columns; `insertParticipant` persists both.

GAPS: none material. PG first-run exit 255 is environmental/flaky teardown, not a test failure — re-run green. API exposure of `sentAt` / structured participant fields deferred to UNIT 04/09 (by design).

### inner — 2026-09-18 — Opus 5 low — UNIT 03

STATUS: complete

COMMITS (UNIT_BASE `700bc8b2c`):
- `8a2165cf2 test(server): pin optional former-committer targets and split counters`
- `4a520e422 feat(server): make former-committer targets optional and split counters`

TESTS:
- RED before the fix: `dart test test/domain/evaluation/evaluation_case_test.dart --exclude-tags pg` → `+0 -1`, load failure (`Required named parameter 'isOptional' must be provided` at `evaluation_case.dart:703` and `:813`) — the new DTO fields and the new assertions did not exist in production.
- GREEN after the fix: same TEST_CMD → **+82, −0** (baseline was +74; eight new tests).
- `dart analyze lib test` → zero errors/warnings (2204 `info` lints, all pre-existing style).
- Whole-package sweep `dart test --exclude-tags pg` → `+1635 -1`; the single failure is **pre-existing**, see FINDINGS.

FILES:
- `packages/server/lib/domain/entity/gql_public/evaluation_participant_result.dart` — `required bool isOptional`, `required int rowStatus`.
- `packages/server/lib/domain/entity/gql_public/review_window_status_result.dart` — the nine new nullable fields, matching the existing `reviewedCount` style.
- `packages/server/lib/domain/use_case/evaluation_case.dart` — both participant endpoints fill the two new fields; `evaluationFinalize` uses the plan's literal readiness loop; `reviewWindowStatus` computes the nine fields.
- `packages/server/lib/domain/port/evaluation_repository_port.dart`, `.../data/repository/evaluation_repository.dart`, `.../data/repository/mock/evaluation_repository_mock.dart` — `getReviewSentAt` (overseer-authorised widening).
- `packages/server/test/domain/evaluation/evaluation_case_test.dart` — two new groups, eight tests, plus `reviewSentAtResult` on the fake.
- `packages/server/test/domain/use_case/coordination_case_revert_test.dart` — signature-only `getReviewSentAt` stub (returns null).

FINDINGS:
- **Pre-existing red, not UNIT 03.** `test/architecture/transactional_attention_producer_inventory_test.dart` → `all interactive and time-driven status transition sites are covered` expects 4 `.requestStatusChanged(` sites in `evaluation_case.dart` but finds 3. `git show 700bc8b2c:…evaluation_case.dart | grep -c` prints **3** as well, so the count was already wrong at UNIT_BASE — UNIT 01's auto-close deletion removed a site without updating the inventory. UNIT 03's diff adds no `requestStatusChanged` call. Needs an owner (UNIT 01 remediation or the closeout unit); the UNIT 03 TEST_CMD does not compile that file, which is why it went unnoticed.
- Only **one** extra `implements EvaluationRepositoryPort` fake needed widening for `getReviewSentAt` (`coordination_case_revert_test.dart`); the other nine either `extends Fake` or already use `noSuchMethod`.
- `reviewWindowStatus` previously called `_canCloseNow` lazily inside the `canCloseNow` `&&` chain. `allRequiredSent` needs it unconditionally, so it is now computed once up front and `canCloseNow` reuses that local. `_canCloseNow`'s body is untouched; the only behaviour delta is that the query runs even when the window is already finalized or the beacon is no longer `reviewOpen` — one extra read, same answer.
- `rowStatus` is the raw `ev?.status ?? -1` and deliberately diverges from `isSubmitted`: on the draft endpoint the existing `useEv` gate nulls display fields for non-draft rows, but `rowStatus` still reports the real stored status (test `draft participants carry isOptional and rowStatus` pins `submitted` = 1 through that gate, and a third test pins `-1` with no row).
- `unsentStartedPackages` / `sentReviewerCount` count every entry in `listReviewStatusesForBeacon` at status 1 / 2 — that map is already beacon-scoped to enrolled reviewers, so no participant join is needed.
- The `a softened committer is optional` fixture reuses the `beaconClose everHadCommitter` shape (`acknowledgedCommitterCommitmentRepo(withdrawAfterAck: 30h)` + a withdrawn `HelpOfferEntity`) against an **open** beacon, so the role really comes out of the graph builder rather than being hand-fed as `role: 3`.

REMAINING: none for UNIT 03. The nine `ReviewWindowStatus` fields and the two participant fields are not on the GraphQL surface yet (UNIT 04) and have no client reader (UNIT 09), both by design. The pre-existing producer-inventory red above is unowned.

### verify — 2026-09-18 — UNIT 03

STATUS: pass

TEST_OUTPUT:
- `dart test test/domain/evaluation/evaluation_case_test.dart --exclude-tags pg` (via `run_with_test_cleanup.sh`, 20m) — **+82, −0** (~4.2s).

RANGE: `700bc8b2c..6cbf6789d` (3 commits: tests `8a2165cf2`, production `4a520e422`, journal `6cbf6789d`). Worktree: only pre-existing UNTOUCHABLE dirty/untracked; no uncommitted UNIT 03 code.

SCOPE: Plan Owns + overseer-authorised widening (`getReviewSentAt` on port/repo/mock; `coordination_case_revert_test.dart` fake stub). No generated files committed. `_canCloseNow` body byte-identical to `700bc8b2c`; `_requiredPackagesAllSentLocked` unchanged in `evaluation_repository.dart`. `evaluationFinalize` readiness loop matches plan revision 3 literal (participant lookup, stale-vis skip, `formerCommitter` skip, same ready predicate and error). `reviewedCount` / `totalCount` still emitted (`reviewed` loop + `vis.length`). `getReviewSentAt` is a single Drift read of `sentAt` on the review-status row.

ACCEPTANCE (plan UNIT 03 + user criteria):
- **Package with untouched leaver can be sent** — **met** — `finalize succeeds with an untouched former committer`; production skips `formerCommitter` in readiness loop.
- **Untouched current committer cannot** — **met** — `finalize still fails with an untouched current committer`.
- **Both participant endpoints return `isOptional` and `rowStatus`** — **met in production** (`evaluationParticipants` ~728–730, `evaluationDraftParticipants` ~838–839); **tests** cover `evaluationDraftParticipants` (+ softened/rowStatus/-1); **no dedicated test** calls `evaluationParticipants` for the two new fields on a live review window.
- **Counters split required/optional** — **met** — `counters split required and optional` asserts split fields and legacy `reviewedCount`/`totalCount` preserved.
- **`viewerPackageOptional` true only for former committer** — **met** — named test for author/committer/former viewer roles.
- **Plan tests (7 named)** — **met** — all seven present; inner added an eighth (`a draft target without a stored row reports rowStatus -1`) — acceptable tightening.
- **`former committer finalize does not change canCloseNow`** — **met** — named test asserts `canCloseNow` and `allRequiredSent` stay false when required committer still unsent.

GAPS:
- **Test coverage:** `evaluationParticipants` `isOptional`/`rowStatus` not asserted (implementation present).
- **`a softened committer is optional`:** uses withdraw-after-grace graph fixture, not `acknowledgementSoftened` event — still yields `formerCommitter` per D6; minor oracle gap vs plan prose.
- **`sentAt` DTO type:** domain entity uses `DateTime?` (UNIT 04 GraphQL will ISO-string); wired via `getReviewSentAt` (outside strict Owns, justified).
- **Pre-existing:** `transactional_attention_producer_inventory_test` still expects 4 `requestStatusChanged` sites (3 since UNIT 01); not in UNIT 03 TEST_CMD — unowned leftover.

## UNIT 04 — Server: GraphQL surface and the client schema

### inner — 2026-09-18 — Opus 5

STATUS: complete

COMMITS (UNIT_BASE `a7feea820`):
- `c289b3e2f feat(server): carry commitment context on evaluation participants`
- `6cbe53dec feat(server): expose review package state on the V2 GraphQL surface`

STEPS:
1. **DTO + case wire (overseer-authorised widening).** `EvaluationParticipantResult` gained `committedAt` (`DateTime?`), `offerMessage` (`String`, default `''`), `forwarderDisplayName` (`String?`). Both endpoints in `evaluation_case.dart` pass them from the row they already hold — `evaluationParticipants` from `BeaconEvaluationParticipantRecord`, `evaluationDraftParticipants` from `EvaluationParticipantDraft`. No stubbed constants.
   - **Red first:** two new tests — `participants carry the commitment context fields` (in the optional-targets group; also the first test that calls `evaluationParticipants` on a live window for the new-field surface, closing part of the UNIT 03 gap) and `draft participants carry the commitment context fields` (in the softened-committer group, asserting the real `'helped out'` offer message flows through the graph builder). RED: compile errors on all three getters → GREEN `+84`.
2. `custom_types.dart`: five fields on `gqlTypeEvaluationParticipant` (plan literal — `isOptional`/`rowStatus` non-nullable, `committedAt` nullable String, `offerMessage` non-nullable String, `forwarderDisplayName` nullable String).
3. `gql_v2_dto_maps.dart`: both maps mirror every field; `committedAt` and `sentAt` as `dto.x?.toUtc().toIso8601String()` like `openedAt`/`closesAt`.
4. `schema.graphql`: same fields on `v2_EvaluationParticipant` and `v2_ReviewWindowStatus`, inserted in the file's alphabetical field order, nullability matching steps 2–3. No client `.graphql` document touched (UNIT 09 owns those).

TESTS:
- `dart test --exclude-tags pg` (full server suite, via `run_with_test_cleanup.sh`) — **+1638, −0**.
- `dart analyze` on both edited GraphQL files — no issues.
- Grep gate `grep -n "viewerPackageOptional\|unsentStartedPackages\|rowStatus" packages/client/lib/data/gql/schema.graphql` — prints `7773: rowStatus: Int!`, `8051: unsentStartedPackages: Int`, `8053: viewerPackageOptional: Boolean`. **Acceptance met.**

FILES: `packages/server/lib/domain/entity/gql_public/evaluation_participant_result.dart`, `packages/server/lib/domain/use_case/evaluation_case.dart`, `packages/server/test/domain/evaluation/evaluation_case_test.dart`, `packages/server/lib/api/controllers/graphql/custom_types.dart`, `packages/server/lib/api/controllers/graphql/mappers/gql_v2_dto_maps.dart`, `packages/client/lib/data/gql/schema.graphql`.

FINDINGS:
- `ReviewWindowStatusResult` already carried all nine UNIT 03 fields, so step 2/3 for `ReviewWindowStatus` was purely additive — no domain change needed there.
- `offerMessage` is non-nullable `String!` on the wire but the DTO defaults it to `''`, matching `contributionSummary`/`note`; a participant with no offer row serialises as `""`, never `null`. Client code must treat empty-string as "no offer message".
- `committedAt` is only populated for rows written since m0176 (UNIT 02). Pre-m0176 participant rows return `null` — the client must tolerate a missing timestamp on old beacons, though per the no-legacy-data posture this is only a local-dev concern.
- Both `v2_` types in `schema.graphql` keep fields alphabetically sorted; the new fields were interleaved rather than appended to preserve that (the file is hand-synced, D18, so nothing regenerates the order).

REMAINING:
- Client `.graphql` query documents still do not select any of the new fields — deliberate, UNIT 09.
- The UNIT 03 gap "`evaluationParticipants` `isOptional`/`rowStatus` not asserted" is now only partly closed: the new test asserts the three context fields on that endpoint but still does not assert `isOptional`/`rowStatus` there.
- Pre-existing `transactional_attention_producer_inventory_test` leftover noted in UNIT 03 is not reproducing in the full suite run (all 1638 green) — no action taken.


### checkpoint — UNIT 05 — 2026-09-18 — Astra inner

HEAD confirmed `9b98de071`. Journal read fully; pre-existing changes preserved. Scope includes user-authorized policy fixture, stateful evaluation fake, and PG concurrency test. Step 1 adds the event, six policy cases, and plan-literal author-only builder; compilation/lint verification follows. No push.

### checkpoint — UNIT 05 — 2026-09-18 — Astra inner

Steps 1–2 committed: `3c769e4d3`, `66ffb2d7a`. Contract expectation RED before JSON additions; contract + policy GREEN (+23). Policy fixture caught a mistakenly duplicated mandatory suppression branch; removed in step 2. Four evaluation tests RED (+85 -4), all missing notification assertions, before production wrap. Fake status writes now update the status map; per-user reads enabled for the new group. Step 4 implementation underway. SDK wrapper/cache and analyzer plugin setup need sandbox escalation; no application environment settings changed.

### checkpoint — UNIT 05 — 2026-09-18 — Astra inner

Production and required focused gates are green. `f3f557f70` implements the transaction plus the four regression tests; `d16c98b8d` adds real PG concurrency, changed-last-sender replay, and dispatch-failure rollback proof. `_canCloseNow` is byte-identical to UNIT_BASE. Focused evaluation + contract: +89. Contract + policy: +23. PG: +5; disabling the nudge temporarily makes the named concurrency test fail (expected 1 occurrence, actual 0), then production restored byte-for-byte. Server custom-lint gate passes at 0/0.

Full non-PG server run: +1642 -1, sole failure `attention_intent_case_test.dart: every non-pending compact-contract type has a migrated fixture`. This additional test inventory was absent from scout/user widening. Plan §0 explicitly forbids edits outside Owns. Requested user authorization to add one 11-line `reviewAllPackagesIn` builder fixture; patch prepared at `/tmp/unit05-intent-fixture.patch`, file not edited pending approval.

Live-code finding: the plan-literal builder initially yielded zero recipients because `BeaconNotificationRecipientResolver` always excludes the actor. Fixed within owned `attention_intent_case.dart`: only `reviewAllPackagesIn` resolves its author actor explicitly with `authorOfBeacon`. Builder stays plan-literal, stable author actor, no triggering sender/time in source facts. New unit and real PG receipt assertions cover this case.

### inner — UNIT 05 — 2026-09-18 — Astra

STATUS: partial / BLOCKED on one additional fixture ownership approval; UNIT 05 implementation and all explicitly requested gates pass.

STEPS / COMMITS (UNIT_BASE `9b98de071`):
1. `3c769e4d3` — enum, all six policy cases, plan-literal intent builder; compile/custom-lint gate green.
2. `66ffb2d7a` — contract eventTypes + producers, exact event expectation, policy fixture. Contract RED first; contract/policy GREEN +23. Fixture exposed and corrected the mistakenly duplicated mandatory suppression branch.
3–4. `f3f557f70` — four plan-named tests RED (+85 -4, missing notification), then transactional finalize and author self-recipient exception GREEN (+89). Red tests committed together with the green implementation, not as a failing commit.
5. `d16c98b8d` — PG simultaneous sends, real occurrence/author receipt, re-send with a different last sender, and status/sent_at rollback when dispatch fails. GREEN +5. Mutation RED: disabled nudge produced 0 instead of 1 occurrence; source restored exactly.

TESTS (all test/analyzer invocations through cleanup wrapper; SDK/cache/network access required sandbox escalation):
- `cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/domain/evaluation/evaluation_case_test.dart test/architecture/updates_event_contract_test.dart --exclude-tags pg` — GREEN +89, final repeat green.
- `cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- dart test test/architecture/updates_event_contract_test.dart test/domain/attention/attention_policy_test.dart --exclude-tags pg` — GREEN +23.
- `cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/data/repository/evaluation_repository_review_status_pg_test.dart --tags pg` — GREEN +5, disposable database proof logged, no skips.
- `cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test --exclude-tags pg` — +1642 -1; only missing migrated-intent fixture listed below.
- `./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/server` — GREEN, 0 custom violations / baseline 0. Existing analyzer warnings remain outside changed lines.
- `git diff --check` — clean; `_canCloseNow` compared byte-for-byte with UNIT_BASE, unchanged.

FILES:
- `packages/server/lib/domain/attention/attention_models.dart`
- `packages/server/lib/domain/attention/attention_policy.dart`
- `packages/server/lib/domain/use_case/attention_intent_case.dart`
- `packages/server/lib/domain/use_case/evaluation_case.dart`
- `docs/contracts/updates-event-contract.json`
- `packages/server/test/architecture/updates_event_contract_test.dart`
- `packages/server/test/domain/attention/attention_policy_test.dart`
- `packages/server/test/domain/evaluation/evaluation_case_test.dart`
- `packages/server/test/data/repository/evaluation_repository_review_status_pg_test.dart`
- this journal (append-only session entries; pre-existing journal edits preserved unstaged).

FINDINGS:
- Actor exclusion in the legacy recipient resolver would suppress every plan-literal nudge; new event-specific branch in the owned intent file explicitly addresses the author. No shared resolver behavior changed.
- PG proof uses concurrent actions serialized on the shared Drift database connection, as requested; it does not claim cross-process/multiple-connection serialization.
- Dispatch settlement remains after the transaction. New event is standard/unblocksMe/review, requiresAction false, author-only, source key uses window openedAt, no last-sender/time payload.
- Full-suite migrated-intent fixture inventory needs an additional owned file beyond the explicit widening. Proposed patch is `/tmp/unit05-intent-fixture.patch` (+11 lines); no edit to that file yet.
- Four implementation/test commits are local. No push. No generated/client/environment/UNTOUCHABLE files changed by this executor.

REMAINING: approve widening to `packages/server/test/domain/attention/attention_intent_case_test.dart`, apply the prepared author-recipient builder fixture, rerun full non-PG server suite and lint, commit green. Scope approval requested asynchronously under plan §0 ("Never edit a file outside the current unit’s Owns"). Do not mark UNIT 05 fully accepted until this gate is green.

### checkpoint — UNIT 05 — 2026-09-18 — overseer

Astra inner `STATUS: partial` on fixture Owns only. Production wrap inspected line-by-line: `evaluationFinalize` records `wasCloseableBefore` before status 2, emits only on `!wasCloseableBefore && isCloseableNow`, `sourceEventKey` uses window `openedAt`, settlement stays after `runAction`, `_canCloseNow` untouched, `requiresAction` false, payload is generic envelope plus beacon id/title (no last-sender, no send timestamp). Policy six switches match the plan. Actor-exclusion bypass is event-specific in `fromBeaconNotification`.

Astra's `/tmp/unit05-intent-fixture.patch` would have duplicated `sourceEventKey` inside the `reviewOpened` fixture. Overseer-applied D17 widen instead: insert a separate `reviewAllPackagesIn` fixture after `reviewOpened` in `attention_intent_case_test.dart`, recipient `actor`. Independent TEST_CMD + that inventory test running next.

### verify — 2026-09-18 — UNIT 05

STATUS: pass

TEST_OUTPUT:
- `dart test test/domain/evaluation/evaluation_case_test.dart test/architecture/updates_event_contract_test.dart --exclude-tags pg` (via wrapper, 20m) — **+89, −0** (~3.2s).
- `dart test test/data/repository/evaluation_repository_review_status_pg_test.dart --tags pg` (via wrapper, 20m) — first run **+5** then post-suite `PathNotFoundException` exit **255** (test-cleanup race, same class as UNIT 02); immediate re-run **+5, −0**, exit **0** (~5.2s).
- `dart test test/domain/attention/attention_intent_case_test.dart --exclude-tags pg` (via wrapper, 10m) — **+33, −0** (~3.8s).
- Supplemental (not in scout TEST_CMD): `attention_policy_test.dart` — **+22**; `transactional_attention_producer_inventory_test.dart` — **+5** — both green.

RANGE: `9b98de071..d98a2e50b` (6 commits: `3c769e4d3`, `66ffb2d7a`, `f3f557f70`, `d16c98b8d`, `f326b74fa`, `d98a2e50b`). Worktree: only pre-existing UNTOUCHABLE dirty/untracked; **no** uncommitted UNIT 05 code.

SCOPE: 11 paths in range (+726/−57 lines): plan Owns + overseer D17 widen (`attention_intent_case_test.dart` +11). No `packages/client/**`; no `*.g.dart` / generated. No deleted `test(` lines in `evaluation_case_test.dart` diff. PG file extended (+214) with concurrency, rollback, and prior UNIT 02 tests retained.

COMMITS: Six focused commits match inner steps 1–5 + overseer fixture (`d98a2e50b`). **Process:** `f3f557f70` folds four RED notification tests with production (same pattern as UNIT 01) — inner recorded RED +85 −4 before green; not a separate failing commit.

ACCEPTANCE (plan UNIT 05 + scout):
- **Author nudge when all required packages in (D14)** — **met** — `evaluationFinalize` wraps in `_attention!.runAction`; `reviewAllPackagesIn` intent + four named unit tests + PG occurrence count.
- **Exactly once per window** — **met** — transition guard + deterministic `sourceEventKey`; tests `the last required package notifies the author exactly once`, `an edit and re-send…`, PG `two simultaneous last sends emit one notification`.
- **Transactional with status write** — **met** — `wasCloseableBefore` at `:1533` before `setReviewUserStatus` `:1567–1573`; `transaction.record` inside same `runAction` before return.
- **Emit only on closeable transition** — **met** — `:1575–1576` `!wasCloseableBefore && isCloseableNow`.
- **sourceEventKey uses window openedAt** — **met** — `:1588–1589`; unit tests assert against `reviewWindowResult!.openedAt`.
- **requiresAction false, not reviewOpened** — **met** — policy `:280`; enum `reviewAllPackagesIn`; presentation `review_all_packages_in`.
- **Author recipient including author-as-last-sender** — **met** — `fromBeaconNotification` event-specific author branch `:901–909`; test `the author as last sender still gets the notification`.
- **Payload: beacon id/title only (no last-sender, no send time)** — **met** — intent uses stable author actor + generic projector envelope; PG/unit receipt assertions per inner.
- **Settlement after transaction** — **met** — `settleReviewerObligationOnPackageSend` at `:1597–1600` after `runAction` closes.
- **_canCloseNow unchanged** — **met** — `sed -n '594,610p'` identical `9b98de071` vs `HEAD`.
- **Contract** — **met** — `updates-event-contract.json` + `_expectedEventTypes` row; contract test +1 in +89 run.
- **Do not reuse reviewOpened / no generation id** — **met**.

GAPS:
- **Process:** RED tests not isolated in their own commit (`f3f557f70`) — acceptable product-wise (inner documented RED first).
- **PG teardown:** intermittent exit 255 after green suite — environmental; re-run confirms **+5**.
- **None material** for UNIT acceptance after `d98a2e50b`.

### overseer — UNIT 05 accepted — 2026-09-18

Verdict: **accepted**. Astra inner (slot A1) + overseer D17 fixture widen `d98a2e50b` + Composer verify pass. Independent overseer tests: evaluation+contract+intent+policy `--exclude-tags pg` **+144**. Line-by-line review of `evaluationFinalize` wrap and policy switches matches D14. Process miss (red tests folded into `f3f557f70`) does not affect product. Remaining Astra slots: A2 UNIT 10, A3 UNIT 12, A4 emergency.

## UNIT 06 — Server: reopen announces itself

UNIT_BASE: `d98a2e50b`
Inner: Opus 5 low. Not Astra.
Live-code note: `reopenFromReview` currently builds `requestStatusChanged` then `downgradeSubmittedReviewsToDraft` → `deleteReviewScaffoldingForBeacon` → `supersedeReviewObligationsOnReopen`. Status list must be read **before** the delete.

### scout — 2026-09-18 — UNIT 06

STATUS: complete

BRIEF: **D15** — when the author calls `reopenFromReview`, every **enrolled** reviewer (`beacon_review_status` row via `listReviewStatusesForBeacon`) gets an informational `AttentionEventType.reviewWindowCancelled` Updates card; the acting author does not. Observable acceptance: (1) with two enrolled reviewers (one sent `status==2`, one not), `TestAttentionHarness.recorded` contains exactly one `reviewWindowCancelled` intent whose `recipients` are both reviewer ids; (2) if the author is also enrolled, they are not among those recipients; (3) `supersedeReviewObligationsOnReopen` still runs (outstanding `reviewOpened` obligation cleared — today a no-op fake returns `0`, test should use a counting fake and assert one call / non-zero return when wired); (4) existing reopen scaffolding behavior unchanged (`downgradeSubmittedReviewsToDraft`, `deleteReviewScaffoldingForBeacon`, status transition to `open`). Policy: `requiresAction false`, `presentationKey review_window_cancelled`, `NotificationCategory.unblocksMe`, `AttentionSuppressionClass.standard`, `_accessPolicy` same branch as `reviewOpened`; **destination** per plan is `AttentionDestinationKind.beacon` + `role.beaconId` (not `review` — differs from `reviewOpened` / `reviewAllPackagesIn`). Intent builder: copy `reviewOpened` (`attention_intent_case.dart:323–341`) — `Set<String> recipientUserIds`, `NotificationPriority.high`, `resolveContext: false`. **Do not** add a `fromBeaconNotification` special case like UNIT 05: actor is the author, recipients are other enrolled ids; `BeaconNotificationRecipientResolver` already skips `userId == actor` (`beacon_notification_recipient_resolver.dart:33–34`), so explicitly subtracting `userId` from the enrolled set is sufficient and safer for tests.

**Live `reopenFromReview`** (`evaluation_case.dart:396–478` at `6a1306bbe`): inside `_runStatusAction` → `runInBeaconStateTransaction`; after reopen-cap check, builds `requestStatusChanged` intent (not yet recorded); then downgrade → delete → `supersedeReviewObligationsOnReopen` → `recordBeaconStatusTransition` → `incrementReviewReopenCount`; **only** `transaction.record(requestStatusChanged)` at `:469–471`. Insert **after** cap check, **before** `downgradeSubmittedReviewsToDraft`: `statuses = await listReviewStatusesForBeacon(beaconId)`; `recipientUserIds = statuses.keys.where((id) => id != userId).toSet()`; build `reviewWindowCancelled` intent when `transaction != null`; at end `record` **both** intents (mirror `beaconClose` two-record pattern at `:329–337`). Plan “Read first” omits the existing `requestStatusChanged` prelude — live order is intent build → mutations → dual record.

**`sourceEventKey`:** plan silent; recommend deterministic
`'review_window_cancelled:$beaconId:${w.openedAt.toUtc().toIso8601String()}'`
(window row `w` already loaded) — journal choice for idempotent retry, analogous to UNIT 05 `review_all_in:…:openedAt`.

**Contract:** append `eventTypes` row + `producers[]` row (`useCase: packages/server/lib/domain/use_case/evaluation_case.dart`, `eventType: reviewWindowCancelled`, `producer: EvaluationCase.reopenFromReview` in `eventTypes`, `destinationFamily: beacon`, `muteability: standard`, `coveringTest: evaluation_case_test.dart`); mirror into `_expectedEventTypes` after `reviewAllPackagesIn`. **`recipientCategory`:** plan does not fix a token — use `review_participant` (enrolled reviewers) or `admitted_participants` (parallel to `reviewOpened`); contract test only requires non-empty string.

**Actor / resolver:** confirmed — no UNIT 05-style bypass. `reviewAllPackagesIn` branch at `:901–909` must remain untouched.

**Tests (existing):** `group('reopenFromReview')` (`evaluation_case_test.dart:2558`) has scaffolding + reopen-limit only; no attention assertions. Seed `evalRepo.reviewStatusesResult` (fake `:497–498`; **not** cleared by `deleteReviewScaffoldingForBeacon`, which only nulls `reviewWindowResult`). Reuse top-level `attention` `TestAttentionHarness` like `beaconClose` (`:2899` expects 2 events). For supersede: local `buildTestEvaluationCase(..., attentionSystemSettlement: countingFake)` pattern from finalize settlement test (`:948–970`); extend or sibling fake with `supersedeCalls` — default `_RecordingPackageSendSettlement.supersedeReviewObligationsOnReopen` returns `0` without counting.

**Owns vs CI (same class as UNIT 05):** `attention_policy_test.dart` `_fixtureFor` throws on unknown contract names; `attention_intent_case_test.dart` inventory `every non-pending compact-contract type has a migrated fixture` — **not** in UNIT 06 Owns. Overseer must widen for `'reviewWindowCancelled'` fixture in both (policy: `reviewParticipant` reasons + `_baseRole`; intent: clone `reviewOpened` fixture block ~145–156 with `reviewWindowCancelled` builder, single `target` recipient).

STEPS (commit-sized, Opus 5 low inner):
1. **Attention surface** — `attention_models.dart`: `reviewWindowCancelled` after `reviewAllPackagesIn`. `attention_policy.dart`: six switches per BRIEF (`_suppression` with `reviewAllPackagesIn` standard group; `_destination` **new** `beacon` case, do not extend `review` pair at `:235–239`). `attention_intent_case.dart`: `reviewWindowCancelled` builder (plan step 2 literal shape = `reviewOpened` + new enum). Red meaningful: **no** (compile-only until contract/tests).
2. **Contract** — `updates-event-contract.json` + `updates_event_contract_test.dart` `_expectedEventTypes` insert. Red meaningful: **yes** — contract test fails until JSON + Dart row land together.
3. **Tests (red)** — `evaluation_case_test.dart` `group('reopenFromReview')`: three plan-named tests + policy projections optional but UNIT 05 pattern asserts `presentationKey` / `destination.kind` / `requiresAction` on cancel intent. Expect `attention.recorded` length **2** (`requestStatusChanged` + `reviewWindowCancelled`) for happy path. Red meaningful: **yes** — zero `reviewWindowCancelled` before step 4.
4. **Production** — `reopenFromReview` list + dual `record` as BRIEF. Keep `supersedeReviewObligationsOnReopen` after delete, unchanged. Red meaningful: step 3 green.

**Overseer widen (D17, after step 2 or with step 4 green):** `attention_policy_test.dart` + `attention_intent_case_test.dart` fixtures; then full non-PG server suite if desired (not in mandatory TEST_CMD).

TEST_CMD:
```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test test/domain/evaluation/evaluation_case_test.dart test/architecture/updates_event_contract_test.dart --exclude-tags pg
```
```bash
cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- dart test test/domain/attention/attention_policy_test.dart test/domain/attention/attention_intent_case_test.dart --exclude-tags pg
```
(second command after overseer widens fixture Owns)

UNTOUCHABLE: journal pre-existing dirty/untracked (`.serena/project.yml`, constellation journal, other `docs/plans/*`, keys, `image_cropper_for_web/build`, etc.); generated files; **client**; UNIT 05 `fromBeaconNotification` author branch; do not push.

RISKS:
- **Plan Read first vs live:** reopen order includes `requestStatusChanged` intent build before downgrade — not contradicted by steps 3–4, but don’t drop it.
- **Destination family:** UNIT 06 explicitly `beacon` not `review` — client UNIT 14 maps `review_window_cancelled` to request copy; aligns with `AttentionDestinationKind.beacon`.
- **Dual record timing:** intents can be built pre-mutation and recorded post-mutation inside the same `runAction` transaction (current `requestStatusChanged` pattern) — statuses must be **read** pre-delete, not **recorded** pre-delete.
- **Empty enrolled set:** only author in status map → cancel intent with zero recipients; not covered by the three named tests.
- **Policy `_suppression`:** `reviewOpened` is `mandatory` in the shared OR-group (`:65–67`); new event must **not** join that group — use `reviewAllPackagesIn` / `standard` branch (`:82–84`).
- **Full CI without fixture widen:** `attention_policy_test` + intent inventory red despite passing UNIT TEST_CMD — same gap UNIT 05 hit; overseer widen required before merge.
- **Supersede test oracle:** production uses `?.` — null settlement port skips; test must inject a fake to prove call happens (return `1` to match “one outstanding obligation” wording).
- **Line refs:** `reopenFromReview` `:396`; `reviewOpened` intent `:323`; policy switches `:65–319`; `listReviewStatusesForBeacon` in `_canCloseNow` `:595` — stable at `6a1306bbe`.

### inner — 2026-09-18 — UNIT 06 (Opus 5 low)

STATUS: complete

STEPS:
1. `cffaa7652` — `reviewWindowCancelled` enum value after `reviewAllPackagesIn`; six `attention_policy.dart` switches (`standard` suppression joined to the `reviewAllPackagesIn`/`deadlineChanged` branch — **not** the `reviewOpened` mandatory OR-group; `unblocksMe`; `reviewOpened` access-policy branch; **new** `AttentionDestinationKind.beacon` case, `review` pair untouched; `requiresAction false`; `'review_window_cancelled'`); intent builder cloned from `reviewOpened` (`Set<String> recipientUserIds`, `NotificationPriority.high`, `resolveContext: false`). RED n/a (compile-only); `dart analyze lib` zero errors.
2. `95589a22d` — contract `eventTypes` + `producers` rows (`recipientCategory: review_participant`, `destinationFamily: beacon`, `muteability: standard`, producer `EvaluationCase.reopenFromReview`) + `_expectedEventTypes` row after `reviewAllPackagesIn` + `attention_policy_test.dart` `_fixtureFor` fixture (`reviewParticipant` + `_baseRole`). **TEST_RED** `+0 -1` (Dart row added before JSON) → GREEN `+24`.
3+4. `4fc40f415` — three plan-named tests in `group('reopenFromReview')` folded with production (tree never left red; **TEST_RED recorded first: `+90 -2`**). Production: `listReviewStatusesForBeacon` + `recipientUserIds = keys.where(id != userId).toSet()` inserted after the reopen-cap check and **before** `downgradeSubmittedReviewsToDraft`; `reviewWindowCancelled` intent built when `transaction != null`; dual `transaction.record` at the end (mirrors `beaconClose`). `supersedeReviewObligationsOnReopen` left after the delete, unchanged. GREEN `+92`.
5. `83a9ac601` — `attention_intent_case_test.dart` inventory fixture (separate record cloned from `reviewOpened`, `recipient: target`). Second TEST_CMD GREEN `+57`.

`sourceEventKey` (overseer choice, plan silent): `review_window_cancelled:$beaconId:${w.openedAt.toUtc().toIso8601String()}` using the already-loaded window row `w`; asserted in the first test.

TESTS:
- TEST_CMD 1 (`evaluation_case_test` + `updates_event_contract_test`, `--exclude-tags pg`): **+92**.
- TEST_CMD 2 (`attention_policy_test` + `attention_intent_case_test`): **+57**.
- Final combined four-file run: **+149**, all passed.
- `dart analyze` on `evaluation_case.dart` + `evaluation_case_test.dart`: zero errors.

FILES:
- `packages/server/lib/domain/attention/attention_models.dart`, `.../attention_policy.dart`
- `packages/server/lib/domain/use_case/attention_intent_case.dart`, `.../evaluation_case.dart`
- `docs/contracts/updates-event-contract.json`
- `packages/server/test/architecture/updates_event_contract_test.dart`
- `packages/server/test/domain/attention/attention_policy_test.dart`, `.../attention_intent_case_test.dart`
- `packages/server/test/domain/evaluation/evaluation_case_test.dart` (+ `_CountingReopenSettlement` fake subclassing `_RecordingPackageSendSettlement`)

FINDINGS:
- The plan-named test *"reopen still supersedes the one outstanding obligation"* was **green on first run** — production already called `supersedeReviewObligationsOnReopen`; the injected `_CountingReopenSettlement` (returns `1`, records calls) turns it into a genuine regression guard rather than a no-op assertion against the default fake's uncounted `0`.
- `AttentionDispatchIntent` recipients carry `reasons`/`role`, not projections, so the policy assertions go through `const AttentionPolicy().project(...)` (UNIT 05 pattern) rather than reading fields off the recipient.
- One `reviewWindowCancelled` intent with two recipients (not two intents), per BRIEF; happy path `attention.recorded` length **2**.
- Untouched as required: `_canCloseNow`, `requestStatusChanged`, UNIT 05 `fromBeaconNotification` `reviewAllPackagesIn` author branch, client, generated files, pre-existing dirty/untracked files.

REMAINING:
- Empty-enrolled-set case (only the author in the status map → cancel intent with zero recipients) still uncovered by the three named tests — scout-flagged risk, no plan requirement.
- Nothing pushed; no PG-tagged coverage added for this unit.

### verify — 2026-09-18 — UNIT 06

STATUS: pass

TEST_OUTPUT:
- `dart test test/domain/evaluation/evaluation_case_test.dart test/architecture/updates_event_contract_test.dart --exclude-tags pg` (via `run_with_test_cleanup.sh`, 20m) — **+92, −0** (~3.2s).
- `dart test test/domain/attention/attention_policy_test.dart test/domain/attention/attention_intent_case_test.dart --exclude-tags pg` (via wrapper, 10m) — **+57, −0** (~3.2s).
- Combined four-file set (evaluation + contract + policy + intent): **+149, −0** (matches inner/overseer).

RANGE: `6a1306bbe..4577edd2d` (5 commits: `cffaa7652`, `95589a22d`, `4fc40f415`, `83a9ac601`, `4577edd2d`). Worktree: only pre-existing UNTOUCHABLE dirty/untracked; **no** uncommitted UNIT 06 code beyond committed range.

SCOPE: 10 paths in range (+280/−1 lines): plan Owns + D17 fixture widen (`attention_policy_test.dart` in `95589a22d`, `attention_intent_case_test.dart` in `83a9ac601`). No `packages/client/**`; no `*.g.dart` / generated. No deleted `test(` lines in `evaluation_case_test.dart` diff — three additions only in `reopenFromReview`. Production `evaluation_case.dart` +19 lines on `reopenFromReview` only; `_canCloseNow` body **byte-identical** `6a1306bbe` vs `HEAD` (Python extract compare).

COMMITS: Five focused commits match inner steps 1–5 + journal. **Process:** `4fc40f415` folds three RED notification tests with production (inner recorded `+90 −2` first); same acceptable pattern as UNIT 01/05.

ACCEPTANCE (plan UNIT 06 + scout + hard-unit checks):
- **D15 — reopen announces cancellation to enrolled reviewers** — **met** — `reopen notifies every enrolled reviewer`: one `reviewWindowCancelled` intent, recipients `{helper1, helper2}` with statuses 2 and 0; `attention.recorded` length 2 with `requestStatusChanged`.
- **Acting author not notified** — **met** — `reopen does not notify the acting author`: author in status map, sole recipient `helper1`.
- **Supersede outstanding obligation** — **met** — `reopen still supersedes the one outstanding obligation`: `_CountingReopenSettlement` records `supersedeCalls == [beaconId]`; production call remains after `deleteReviewScaffoldingForBeacon` (`evaluation_case.dart:471–475`).
- **`listReviewStatusesForBeacon` before delete** — **met** — read at `:443–447`, delete at `:471–473`.
- **Dual record + keep `requestStatusChanged`** — **met** — both intents built pre-mutation; `record` at `:485–490` (status then cancel).
- **Policy: `requiresAction false`, `review_window_cancelled`, `unblocksMe`, standard suppression, beacon destination** — **met** — `attention_policy.dart` switches; unit test projects per recipient.
- **Same access as `reviewOpened`** — **met** — `_accessPolicy` groups `reviewWindowCancelled` with `reviewOpened` (`:163–167`).
- **No UNIT 05 `fromBeaconNotification` bypass** — **met** — only `reviewAllPackagesIn` branch at `attention_intent_case.dart:922–929`; `reviewWindowCancelled` uses default resolver + explicit `keys.where(id != userId)`.
- **Contract** — **met** — `updates-event-contract.json` `eventTypes` + `producers`; `_expectedEventTypes` row; contract test in +92 run.
- **Existing reopen scaffolding** — **met** — prior tests `downgrades submitted reviews…` and reopen-limit unchanged in behavior.
- **Plan acceptance (“nobody’s completed work disappears silently”)** — **met** at server boundary (notification + supersede); client copy deferred UNIT 14.

GAPS:
- **Process:** RED tests not isolated in own commit (`4fc40f415`) — acceptable (inner documented RED first).
- **Coverage:** empty enrolled set (author-only status map) still untested — scout risk, not plan-named.
- **None material** for UNIT acceptance.

### overseer — UNIT 06 accepted — 2026-09-18

Verdict: **accepted**. Opus-low inner + Composer verify pass. Independent overseer four-file run **+149**. Line-by-line: statuses listed before delete, dual-record keeps `requestStatusChanged`, supersede after delete, author excluded, destination `beacon`, UNIT 05 author branch untouched. Process miss (red tests folded into `4fc40f415`) same as UNIT 01/05, product OK. Empty-enrolled-set uncovered — deferred, not plan-named.

## UNIT 07 — Client: l10n keys

UNIT_BASE: `4577edd2d`
Inner: Opus 5 low. Not Astra.

### scout — 2026-09-18 — UNIT 07

STATUS: complete

BRIEF: **D17 additive l10n only** — add every §2 copy-table key to `packages/client/l10n/app_en.arb` and `app_ru.arb` with plan-literal RU/EN (authoritative RU; user-facing **запрос** / **оценк***, never product-noun beacon/room). **35 new keys**, **3 changed** (`evaluationSubmitFinish`, `beaconHudActReviewContributions`, `beaconReviewReopenBody`). None of the new symbols exist in the repo yet (`grep` clean). **Live changed values** (must match §2 after edit):

| Key | Current EN | Target EN |
|-----|------------|-----------|
| `evaluationSubmitFinish` | `Submit and finish` | `Send reviews` |
| `beaconHudActReviewContributions` | `Review contributions` | `Review contributions` (unchanged EN; RU `Проверить вклад` → `Оценить вклад`) |
| `beaconReviewReopenBody` | no placeholders | `{sent}` int + new copy; add sibling `beaconReviewReopenBodyNoSent` |

**Placeholder metadata:** mirror `evaluationProgress` (`app_en.arb:4077–4086`): string keys get `@key` with `"placeholders": { "name": {"type": "String"} }`; ints use `"type": "int"`. Keys needing metadata: `evaluationPackageSentAt` (`date`), `evaluationProgressSplit` (`req`, `reqTotal`, `opt`, `optTotal`), `evaluationContextCommitted` / `Via` / `Offer`, `beaconHudActEffectReviewProgress` (`count`, `total`), `beaconReviewCloseNowDiscardNote` (`count`), `beaconReviewReopenBody` (`sent`), `updatesFallbackBodyReviewAllIn` / `ReviewCancelled` (`title`). **No** `@beaconReviewReopenBody` exists today.

**Regenerate:** `cd packages/client && flutter gen-l10n` → `lib/ui/l10n/**` per `l10n.yaml` (`output-dir: lib/ui/l10n`). **`packages/client/.gitignore:65`** ignores `/lib/ui/l10n/*` — do not commit generated dart (D18); CI/local tests need gen-l10n before `flutter test`.

**D17 compile hazard (primary):** sole consumer `beacon_view_status_bottom_sheet.dart:302` calls `l10n.beaconReviewReopenBody` with **no args**. Adding `{sent}` changes generated API to `beaconReviewReopenBody(int sent)` → **analyzer error** until call site updates. `sentReviewerCount` is on `schema.graphql` only (UNIT 09); `ReviewWindowInfo` / menu snapshot do not expose it yet. **Overseer must widen Owns** for a one-file compile bridge in the same commit as the arb change, e.g. `Text(l10n.beaconReviewReopenBodyNoSent)` until UNIT 14 plumbs count + conditional, or pass a stub `0` to `beaconReviewReopenBody(0)` (wrong copy when senders exist — avoid). Value-only changes to `evaluationSubmitFinish` / `beaconHudActReviewContributions` are safe (`review_contributions_screen.dart:149`, `beacon_hud_author_action.dart:182`).

**Terminology gates:** `scripts/check-user-facing-terminology.sh` scans arb values (beacon/room/входящие). §2 strings use request/запрос — should pass. `packages/client/test/l10n/request_terminology_contract_test.dart` asserts en/ru **key parity**, bans beacon/room in values, snake_case values — run as smallest arb proof (`flutter test test/l10n/...`); plan Verify `test/ui` does not cover l10n dir but is still required regression.

**Insertion hints (style):** keep JSON valid; place `evaluation*` block near existing evaluation strings (~4075+); `beaconHud*` / `beaconReview*` near `beaconHudActReviewContributions` (~4657) and `beaconReviewReopen*` (~4590); four `updatesFallback*Review*` after `updatesFallbackBodyReviewOpened` (~5839).

STEPS (commit-sized):
1. **`app_en.arb` + `app_ru.arb` — evaluation package copy** — add all `evaluation*` keys from §2 except defer reopen/HUD/updates clusters if splitting; update `evaluationSubmitFinish` values; each placeholder key + `@` block in both locales.
2. **Same files — HUD + author dialog copy** — add `beaconHudActEffectReviewProgress`, `beaconHudReviewSent`, `beaconHudReviewEdit`, `beaconHudWaitingFor*`, `beaconReviewCloseNowBody`, `beaconReviewCloseNowDiscardNote`, `beaconReviewReopenBodyNoSent`; change `beaconHudActReviewContributions` (RU); change `beaconReviewReopenBody` + `@beaconReviewReopenBody` (`sent`).
3. **Same files — Updates fallbacks** — `updatesFallbackTitle/BodyReviewAllIn` and `ReviewCancelled` with `title` placeholder; verify en/ru key sets still identical.
4. **Codegen + D17 bridge** — `flutter gen-l10n`; **(widened)** fix `beacon_view_status_bottom_sheet.dart` reopen dialog body to compile; journal inner records widen. Red meaningful: `dart analyze` / `flutter test test/l10n` fails on step 2 without step 4.

TEST_CMD:
```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/ui --dart-define=ENV=test --dart-define-from-file=env/test.env
```
```bash
bash scripts/check-user-facing-terminology.sh
```
```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test test/l10n/request_terminology_contract_test.dart --dart-define=ENV=test --dart-define-from-file=env/test.env
```
(third line: smallest proof of arb parity/terminology — not in strict plan Verify but recommended)

UNTOUCHABLE: pre-existing dirty/untracked; generated `lib/ui/l10n/*` (gitignored — regenerate locally only); no hand-edit `l10n_*.dart`; no consumer/UI wiring beyond overseer-approved compile bridge; other units; keys/secrets; do not delete any arb key (D17).

RISKS:
- **Owns vs D17:** `beaconReviewReopenBody` placeholder without sheet fix → **BLOCKED** compile; widen `beacon_view_status_bottom_sheet.dart` or defer reopen-body change to a unit that owns UNIT 14 entry points (plan assigns change to UNIT 07 — widen expected).
- **Interim reopen copy:** using only `beaconReviewReopenBodyNoSent` at the sheet until UNIT 14 misstates reopen when `sentReviewerCount > 0` — acceptable short window if documented in inner.
- **Curly quotes:** §2 `evaluationContextOffer` / updates bodies use typographic quotes — paste literally; terminology script does not validate quote style.
- **RU «Помогал(а)»** gender-neutral parenthetical — plan literal; do not paraphrase.
- **`beaconHudActReviewContributions` EN** unchanged text — only RU changes per §2; do not "improve" EN.
- **gen-l10n omitted:** `flutter test` imports `package:tentura/ui/l10n/l10n_en.dart` — missing gen step fails entire client test suite.
- **UNIT_BASE:** journal header still `4577edd2d`; live `git rev-parse --short HEAD` is `5b3f4f6b9` (post–UNIT 06 journal commit) — inner should record actual base.


### inner — 2026-09-18 — UNIT 07 (Opus 5 low)

STATUS: complete

UNIT_BASE (actual): `5b3f4f6b9` (journal header says `4577edd2d`, the pre-announcement commit — scout-flagged).

STEPS:
1–3 (merged into one commit `b9c269598`, arb JSON cannot be left valid-but-half-written across separate edits, and the `{sent}` placeholder breaks compilation until the D17 bridge lands with it): all 35 new §2 keys added to **both** `app_en.arb` and `app_ru.arb` — 23 `evaluation*`, 7 HUD/close-now, `beaconReviewReopenBodyNoSent`, 4 `updatesFallback*Review{AllIn,Cancelled}` — plus the 3 changed keys (`evaluationSubmitFinish` EN `Submit and finish` → `Send reviews`, RU → `Отправить оценки`; `beaconHudActReviewContributions` RU `Проверить вклад` → `Оценить вклад`, EN untouched; `beaconReviewReopenBody` new copy + `{sent}`). `@key` blocks mirror `evaluationProgress` style; `date`/`name`/`message`/`title` `String`, `count`/`total`/`sent`/`req`/`reqTotal`/`opt`/`optTotal` `int`. Typographic quotes (`«»`, `“”`) and `Помогал(а)` pasted literally. **Additive — no key deleted.**
4. `flutter gen-l10n` run; `lib/ui/l10n/*` is gitignored and **not** committed; no `l10n_*.dart` hand-edited.

**D17 widen (overseer-authorized, documented here):** `packages/client/lib/features/beacon_view/ui/widget/beacon_view_status_bottom_sheet.dart:302` called `l10n.beaconReviewReopenBody` with no args; after `{sent}` the generated API is `beaconReviewReopenBody(int sent)`. RED captured: `dart analyze` on that file → `error … The argument type 'String Function(int)' can't be assigned to the parameter type 'String'`. Bridged to `l10n.beaconReviewReopenBodyNoSent` (**not** a stub `0`, which would misstate the reopen when senders exist). **UNIT 14 must plumb `sentReviewerCount` and restore the conditional** — until then the reopen dialog always shows the no-sent copy. No other UI wiring touched.

TESTS:
- `flutter test test/l10n/request_terminology_contract_test.dart` (via `run_with_test_cleanup.sh`, 10m) — **+4, −0** (key parity, no beacon/room nouns, no snake_case values, Request/запрос core labels).
- `bash scripts/check-user-facing-terminology.sh` — `ok`, exit 0.
- `flutter test test/ui` (via wrapper, 15m) — **+314, −0**.
- `dart analyze` on the bridged sheet — 0 errors (pre-existing warning/info untouched).
- Post-edit parity check: both arb files contain all 35 new keys; the only en/ru key asymmetry is the pre-existing set of unrelated `@…` metadata blocks.

COMMITS: `b9c269598 feat(client): add review package state copy to the arb files`

FILES: `packages/client/l10n/app_en.arb`, `packages/client/l10n/app_ru.arb`, `packages/client/lib/features/beacon_view/ui/widget/beacon_view_status_bottom_sheet.dart`.

FINDINGS:
- Steps 1–3 could not be split into separate green commits without leaving the client uncompilable mid-way (placeholder change). Red was still captured explicitly on the analyzer before the bridge.
- No name collisions: none of the 35 new keys existed; nearby lookalikes (`evaluationSectionAuthor`, `beaconHudReviewOpen`, `beaconReviewCloseNowAction/Success/Blocked`, `beaconHudWaitingForReviews`) are distinct keys and were left alone.
- The old `beaconReviewReopenBody` EN/RU copy ("Returns to Open. Review notes are kept as drafts…") is fully replaced per §2, not kept as a variant.

REMAINING:
- **UNIT 14 owes the reopen-body restore** (`sentReviewerCount` → `beaconReviewReopenBody(sent)` when `sent > 0`, else `…NoSent`).
- All 35 keys are unreferenced by UI so far — consumers land in UNIT 08–14. Nothing pushed.

### verify — 2026-09-18 — UNIT 07

STATUS: pass

TEST_OUTPUT:
- `flutter test test/l10n/request_terminology_contract_test.dart` (via `run_with_test_cleanup.sh`, 10m) — **+4, −0** (~4.2s).
- `bash scripts/check-user-facing-terminology.sh` — **ok**, exit **0**.
- `flutter test test/ui` (via wrapper, 15m) — **+314, −0** (~27s).

RANGE: `5b3f4f6b9..f6da84625` (2 commits: `b9c269598` arb + D17 sheet bridge, `f6da84625` journal). Worktree: only pre-existing UNTOUCHABLE dirty/untracked outside this range; **no** uncommitted UNIT 07 product code.

SCOPE: `git diff 5b3f4f6b9..HEAD` touches exactly `app_en.arb`, `app_ru.arb`, `beacon_view_status_bottom_sheet.dart` (+ journal). **No** `lib/ui/l10n/*` in commit range. Sheet diff is one line: `beaconReviewReopenBody` → `beaconReviewReopenBodyNoSent` at `:302`.

ACCEPTANCE (plan UNIT 07 + overseer checks):
- **§2 keys in both locales with placeholders** — **met** — Python parity: 35 new keys present in EN/RU; en/ru message key sets identical (1944 each); `@beaconReviewReopenBody` `{sent}` and other `@` blocks present.
- **Three changed keys** — **met** — `evaluationSubmitFinish` EN `Send reviews`, RU `Отправить оценки`; `beaconHudActReviewContributions` EN unchanged, RU `Оценить вклад`; `beaconReviewReopenBody` plan copy + placeholder; sibling `beaconReviewReopenBodyNoSent` added.
- **Additive only (D17)** — **met** — vs `5b3f4f6b9`: **0** arb keys deleted, **35** added per locale.
- **Do not hand-edit generated l10n** — **met** — no `l10n_*.dart` in commits; tests green imply local `flutter gen-l10n` was run (gitignored output).
- **Terminology script** — **met** — exit 0; contract test bans beacon/room in arb values.
- **§2 literals (spot-check)** — **met** — EN/RU samples including `Помогал(а)`, typographic `“{message}”` / `«{message}»`, `updatesFallbackBodyReviewAllIn` curly title quotes match plan table.
- **D17 widen** — **met** — sole non-arb production change is sheet `NoSent` bridge; no stub `beaconReviewReopenBody(0)`; no other UI wiring.
- **Plan Verify commands** — **met** — all three TEST_CMD green.

GAPS:
- **Known interim product gap (documented):** reopen confirm always shows `beaconReviewReopenBodyNoSent` until UNIT 14 plumbs `sentReviewerCount` — not a UNIT 07 defect.
- **None material** for UNIT 07 acceptance.

### overseer — UNIT 07 accepted — 2026-09-18

Verdict: **accepted**. Opus-low inner + Composer verify pass. Independent terminology script ok and l10n contract **+4**. D17 sheet `NoSent` bridge is required compile fix; UNIT 14 must restore sent-count copy. No generated l10n committed.

## UNIT 08 — Client domain: ReviewPackageState

UNIT_BASE: `f6da84625`
Inner: Opus 5 low. Not Astra.

### scout — 2026-09-18 — UNIT 08

STATUS: complete

BRIEF: Add **pure domain** `ReviewPackageState` enum + `deriveReviewPackageState(...)` at `packages/client/lib/features/evaluation/domain/review_package_state.dart` (sibling to `evaluation_exception.dart`, **not** under `entity/` — matches other feature roots like `forward/domain/forward_draft_policy.dart`). **Both Owns paths are absent** on `UNIT_BASE` `c5b920e87` (live `git rev-parse --short HEAD`; journal header `f6da84625` is stale vs tree). **No** `ReviewPackageState` / `deriveReviewPackageState` symbols anywhere in `packages/client` yet. Production file must be **plan-literal** (comments included): frozen **if-chain order**, no `switch`, no new parameters, **no Flutter import**. D10/D11: `sentAt` distinguishes sent-then-edited from first-save `status == 1`; `userReviewStatus == 2` short-circuits to `sent` before `sentAt`/completeness (server demotes to `1` on edit). Status codes align with server `beacon_review_statuses.dart:14` (`0` not started, `1` in progress, `2` submitted, `3` skipped, `4` expired unsent). `beaconIsInReview` / `beaconIsClosed` are **derivation inputs only** — not on client yet (UNIT 10/11 add `EvaluationState` fields); tests pass them explicitly.

STEPS (commit-sized; **test-first** — red is meaningful while types missing):
1. **`review_package_state_test.dart` (red)** — `import package:tentura/features/evaluation/domain/review_package_state.dart`; table-driven rows via named records + `for (final c in cases) test(c.name, …)` (mirror `forward_draft_policy_test.dart`). **One named `test` per plan oracle row** (groups optional). Suggested groups/rows:
   - **`all nine enum values are reachable`** — nine rows, one `ReviewPackageState.*` each (use distinct inputs; see traps below).
   - **`status 1 without sentAt never yields changedNotSent`** — at least two rows: `(requiredAnswered < requiredTotal → inProgress)`, `(requiredAnswered >= requiredTotal → readyToSend)`; all with `userReviewStatus: 1`, `sentAt: null`, live window (`hasWindow: true`, `windowComplete: false`, `beaconIsClosed: false`).
   - **`status 3 matches status 0 for derivation`** — pair rows: same inputs except `userReviewStatus` `0` vs `3`, same expected state (e.g. incomplete → `inProgress`, complete → `readyToSend`).
   - **`requiredTotal zero with targets present`** — `requiredTotal: 0`, `requiredAnswered: 0`, `totalTargets: 2`, enrolled `userReviewStatus: 0`, no `sentAt` → `readyToSend`.
   - **`zero targets`** — `totalTargets: 0`, enrolled (`userReviewStatus: 1`), `hasWindow: true` → `empty` (not `readyToSend`).
   - **`sentAt set but required incomplete`** — `sentAt: DateTime.utc(2026, 1, 1)`, `requiredTotal: 2`, `requiredAnswered: 1`, `userReviewStatus: 1` → `inProgress`.
   - **`lost window while request still in review`** — `hasWindow: false`, `beaconIsInReview: true`, `beaconIsClosed: false`, `windowComplete: false`, enrolled `userReviewStatus: 0` → `notEnrolled`.
   - **`lost window after reopen (not in review)`** — `hasWindow: false`, `beaconIsInReview: false` → `paused` (keep `windowComplete`/`beaconIsClosed` false, `userReviewStatus` enrolled e.g. `1`, so earlier branches do not fire).
   - **`windowComplete or beaconIsClosed`** — four rows: `(windowComplete: true, sentAt set → closed)`, `(windowComplete: true, sentAt null → closedUnsent)`, `(beaconIsClosed: true, sentAt set → closed)`, `(beaconIsClosed: true, sentAt null → closedUnsent)`; use `hasWindow: true`, `userReviewStatus: 1` so status-2/sent path is not taken before close branch.
   - Optional extra row: **`userReviewStatus 4 → closedUnsent`** with live window flags (documents check before `!hasWindow`).
   - **Default “live checklist” baseline** for rows that need an open window: `beaconIsInReview: true`, `beaconIsClosed: false`, `hasWindow: true`, `windowComplete: false`, `sentAt: null`, `requiredTotal: 1`, `requiredAnswered: 0`, `totalTargets: 1`, `userReviewStatus: 0` — override only fields under test.
   - **Reachability cheat sheet**: `notEnrolled` (`userReviewStatus: -1`); `empty` (`totalTargets: 0`); `inProgress` (incomplete, no `sentAt`); `readyToSend` (complete, no `sentAt`, status `0`/`1`); `sent` (`userReviewStatus: 2`); `changedNotSent` (`sentAt` set, complete, status `1`); `paused` (no window, not in review); `closed` / `closedUnsent` (complete/closed flags + `sentAt`).
2. **`review_package_state.dart` (green)** — paste **exact** plan UNIT 08 step-1 block (lines 1078–1164 in plan md); no edits, no reorder, no switchify.
3. **Verify** — run TEST_CMD; then `check-custom-lints.sh packages/client` (domain-only change should not move baseline).

TEST_CMD:
```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test test/features/evaluation/review_package_state_test.dart --dart-define=ENV=test --dart-define-from-file=env/test.env
```

UNTOUCHABLE: pre-existing dirty/untracked; generated; other units; UI wiring (`EvaluationState.packageState` is UNIT 10); `review_window_info.dart` getters remain until UNIT 12.

RISKS:
- **Frozen order traps**: `windowComplete || beaconIsClosed` runs before `userReviewStatus == 2` — tests for `sent` must keep both false; close-oracle rows must not use `userReviewStatus: 2` expecting `sent`.
- **`status 4` before `!hasWindow`**: expired unsent is `closedUnsent` even if `hasWindow` would otherwise apply — do not conflate with `paused`.
- **`!hasWindow && beaconIsInReview` → `notEnrolled`**, not `paused` — first-time / never-window visitors vs reopen loss (plan comment literal).
- **`userReviewStatus == 2` ignores `sentAt` and completeness** — only valid while server status is submitted; post-edit client path is `1` + `sentAt` → `changedNotSent` or `inProgress`.
- **D11 regression row is the unit’s reason** — never expect `changedNotSent` when `sentAt == null` regardless of `status == 1`.
- **`requiredTotal == 0`**: `allRequiredAnswered` is vacuously true → `readyToSend` when no `sentAt` and status not `2` (all-optional package).
- **Journal UNIT_BASE header** (`f6da84625`) vs overseer `c5b920e87` — inner should record actual commit parent when committing.
- **No semver bump** in this unit (domain-only; release is UNIT 15).

COMMITS (expected): `feat(client): derive review package state` — sources only: the two Owns files + journal inner/verify.

---
### inner — 2026-09-18 — UNIT 08 (Opus 5 low)

STATUS: complete — green, committed `703b607ea` (parent `c5b920e87`, i.e. the
overseer UNIT_BASE; the journal's `f6da84625` header was stale vs the tree).

STEPS:
1. **RED** — wrote `test/features/evaluation/review_package_state_test.dart`
   first (table-driven, one named `test` per plan oracle row, `_row(...)` helper
   with the scout's live-checklist baseline). TEST_CMD failed at load with
   `Undefined name 'ReviewPackageState'` / `Undefined name
   'deriveReviewPackageState'` — `00:00 +0 -1: Some tests failed.`
2. **GREEN** — created
   `lib/features/evaluation/domain/review_package_state.dart` by extracting the
   plan's UNIT 08 step-1 dart block **programmatically** (python slice of the
   fenced block) so the file is byte-identical to the plan literal: same comments,
   same frozen if-chain order, no switch, no extra inputs, no Flutter import.
   TEST_CMD: `00:00 +25: All tests passed!`
3. `scripts/check-custom-lints.sh packages/client` → `total: 30 (baseline: 30)`,
   `OK`. Baseline did not move.
4. Single commit `feat(client): derive review package state` with both Owns files
   only. Not pushed. No semver bump, no UI wiring, no generated files.

FILES:
- `packages/client/lib/features/evaluation/domain/review_package_state.dart` (new, plan-literal)
- `packages/client/test/features/evaluation/review_package_state_test.dart` (new, 25 tests)

TEST COVERAGE (groups → rows):
- `all nine states are reachable` — 9 rows, one per enum value.
- `status 1 without sentAt never yields changedNotSent` — 2 rows (D11 regression).
- `status 3 behaves like status 0` — 4 paired rows.
- `completeness edges` — `requiredTotal == 0` + targets → `readyToSend`;
  `totalTargets == 0` → `empty`; `sentAt` set with a required answer removed →
  `inProgress`.
- `missing window` — in-review → `notEnrolled`; not-in-review → `paused`.
- `closed windows` — `windowComplete`/`beaconIsClosed` × `sentAt` (4 rows) plus
  `status 4` in a live window → `closedUnsent`.

FINDINGS:
- The scout's frozen-order traps all held in practice: close rows use
  `userReviewStatus: 1` (not `2`) so the close branch is what fires, and the
  `sent` row keeps `windowComplete`/`beaconIsClosed` false.
- `analysis_options` flagged `DateTime.utc(2026, 1, 1)` as
  `avoid_redundant_argument_values`; the shared `_sentAt` sentinel is
  `DateTime.utc(2026, 3, 14)` instead. Five remaining info-level
  `avoid_redundant_argument_values` hits in the test are **deliberate** — they
  spell out the field under test (`userReviewStatus: 0`, `requiredAnswered: 0`,
  `beaconIsInReview: true`) even where it matches the baseline, because the plan
  oracle names those values. Info severity only; tentura_lints baseline unaffected.
- `beaconIsInReview` / `beaconIsClosed` have no client producer yet — tests pass
  them explicitly, as the scout noted. Wiring is UNIT 10/11.

REMAINING:
- Nothing for UNIT 08. `EvaluationState.packageState` and every UI switch over
  this enum stay with UNIT 10+; `review_window_info.dart` getters untouched
  (UNIT 12). Nothing pushed.

### verify — 2026-09-18 — UNIT 08

STATUS: pass

TEST_OUTPUT:
- `flutter test test/features/evaluation/review_package_state_test.dart` (via `run_with_test_cleanup.sh`, 10m) — **+25, −0** (~4.3s).

RANGE: `c5b920e87..996724eec` — `703b607ea` `feat(client): derive review package state` (both Owns dart files only); `996724eec` journal inner. Worktree: no uncommitted changes to UNIT 08 product paths; only pre-existing UNTOUCHABLE dirty/untracked outside range.

SCOPE: `grep ReviewPackageState|deriveReviewPackageState` under `packages/client` hits **only** `review_package_state.dart` + `review_package_state_test.dart` — no UI/`lib/` consumers.

ACCEPTANCE (plan UNIT 08 + overseer checks):
- **Plan-literal production file** — **met** — `review_package_state.dart` matches plan § UNIT 08 step-1 block (enum, doc comments, frozen if-chain, same parameters); **no** `import` lines; **no** `switch`; `rg switch|import` on file is empty.
- **All nine states reachable** — **met** — test group `all nine states are reachable` has 9 named rows covering each enum value.
- **D11: status 1 + `sentAt == null` never `changedNotSent`** — **met** — dedicated group with `inProgress` + `readyToSend` rows only; no `changedNotSent` expectation with `sentAt: null`.
- **Plan oracle rows** — **met** — status 3 ≡ 0 (4 rows); `requiredTotal == 0` → `readyToSend`; `totalTargets == 0` → `empty`; `sentAt` + incomplete → `inProgress`; missing-window pair; `windowComplete`/`beaconIsClosed` × `sentAt` (4) + status `4` row (25 tests total).
- **No Flutter import in domain** — **met** — production file is pure Dart; test uses `flutter_test` only.
- **No UI wiring** — **met** — no `packageState`, no imports from `ui/`; `EvaluationState` unchanged.
- **Verify command** — **met** — TEST_CMD green.
- **Owns exclusive** — **met** — feat commit touches only the two new dart paths (+ journal in follow-up commit).

GAPS: none material for UNIT 08 acceptance.

### overseer — UNIT 08 accepted — 2026-09-18

Verdict: **accepted**. Opus-low inner + Composer verify pass. Independent TEST_CMD **+25**. Production file is plan-literal; D11 regression covered; no UI wiring.

## UNIT 09 — Client data: role, optionality, context, sheet

UNIT_BASE: `02db0c811` (journal header `996724eec` was stale; live `git rev-parse --short HEAD` at scout time)
Inner: Opus 5 low. Not Astra. Do not parallelize with UNIT 10.

### scout — 2026-09-18 — UNIT 09

STATUS: ready (hard DTO hop) — **compile trap** if plan step 2 removes `contributionSummary`/`causalHint` from `EvaluationParticipant` while `review_contributions_screen.dart` (UNIT 10, untouchable) still reads `participant.contributionSummary` at `:392–393`. Strict Owns + untouchable screen ⇒ **BLOCKED** on literal entity removal unless overseer waives a one-line screen stub or mechanical constructor fixes in non-Owns tests (~6 files). Pragmatic fallback (journal FINDING, not plan text): stop selecting legacy fields in `.graphql`/repo, wire sheet via `presentParticipantContext`, keep deprecated `@Default('')` entity fields until UNIT 10 deletes consumers.

BRIEF: Plumb UNIT 04 GraphQL fields into client domain + repository; add `EvaluationParticipantRole.formerCommitter` (`db 3` at `_roleFromInt` `:493–497`, today `_ => committer`); extend `EvaluationParticipant` with `isOptional`, `rowStatus`, `committedAt`, `offerMessage`, `forwarderDisplayName`, and `hasAnswer` getter (draft/submitted/final only); extend `ReviewWindowInfo` with nine window fields + parse `sentAt` via existing `_parseUtcDateTime` (`:491`); update three `.graphql` documents (drop legacy participant columns per plan, add new ones; extend `review_window_status.graphql`); run `dart run build_runner build --delete-conflicting-outputs` (D18, commit sources only); add `evaluation_participant_context.dart` presenter (l10n keys from UNIT 07); update `evaluation_state.dart` with `requiredParticipants`/`optionalParticipants` and **live** `canFinalize` over `hasAnswer` on required rows only; fix exhaustive role switches in `evaluation_detail_sheet.dart` `:140–145`, `:151–158`, replace `:238` `contributionSummary` with presenter (D9); **do not** add `packageState` / `deriveReviewPackageState` (UNIT 10); **do not** delete `ReviewWindowInfo.viewerHasOutstandingReviewWork` / `viewerCanOpenReviewScreen` (UNIT 12, D17).

**Live vs plan — `canFinalize` / `hasAnswered` / `hasAnswer`:** Plan step 5 mixes **`hasAnswered`** (draft: `currentValue != null`, unchanged on entity `:35`) and **`hasAnswer`** (live: `rowStatus ∈ {0,1,2}`, new). That is intentional, not a typo. **Contradiction is vs live `evaluation_state.dart` `:28–34`**, which uses **`isSubmitted` for live mode**, not `hasAnswered` and not `hasAnswer`. Inner must implement plan step 5 (#180). **`reviewedCount` still counts `isSubmitted` in live mode** after this unit — progress UI may disagree with finalize gate until UNIT 10; do not “fix” reviewedCount here unless plan adds it.

**Schema (UNIT 04 done):** `v2_EvaluationParticipant` / `v2_ReviewWindowStatus` in `schema.graphql` `:7756–7776`, `:8033–8055` already expose all new fields. Client queries still legacy-only (`evaluation_participants.graphql`, `evaluation_draft_participants.graphql`, `review_window_status.graphql`).

**Repository:** `_participantFromGraphqlRow` / `_mapParticipant` / `_mapDraftParticipant` `:44–117` pass `contributionSummary`, `causalHint`, `isSubmitted` only. `fetchReviewWindowStatus` `:163–176` maps 11 legacy fields; batch `fetchReviewWindowStatuses` `:198–202` minimal stub unchanged (My Work UNIT 13).

**Sheet:** `_promptText` treats handoff only for `committer` (`:147–149`); `formerCommitter` must follow committer prompt paths. `_roleLabel` / inner switch need new enum case (same l10n as committer per plan).

**Tests — patterns:** `evaluation_state_test.dart` — small `EvaluationState`/`EvaluationParticipant` const fixtures with `contributionSummary`/`causalHint` today; replace live finalize oracle (`live canFinalize requires every row ready`) with `rowStatus`/`isOptional`/`hasAnswer`. `evaluation_presenter_test.dart` — `lookupL10n` + EN/RU for presenter tests. `evaluation_detail_sheet_test.dart` — `evaluation_sheet_test_support.dart`, const `participant` with legacy summary; add `renders a former committer without crashing` with `role: formerCommitter`. New `evaluation_participant_context_test.dart` — one named test per presenter rule × EN/RU (mirror `evaluation_presenter_test.dart`).

STEPS (4 commits, test-first; red meaningful on state/context/sheet before codegen green):

1. **`feat(client): evaluation participant DTO and role`** — RED: extend `evaluation_state_test.dart` (three plan test names; use `rowStatus`/`isOptional`, keep draft tests on `hasAnswered`); RED: `evaluation_detail_sheet_test.dart` former-committer crash test (fails on non-exhaustive switch). GREEN: add `formerCommitter` to enum; expand `evaluation_participant.dart` (+ `hasAnswer` getter); edit both participant `.graphql` (remove `contributionSummary`/`causalHint`, add `isOptional`, `rowStatus`, `committedAt`, `offerMessage`, `forwarderDisplayName`; keep `isSubmitted` on wire for now); `build_runner`; update `evaluation_repository.dart` `_roleFromInt` + `_participantFromGraphqlRow` mapping; run `dart run build_runner` / freezed regen. **Resolve compile trap** (see STATUS) before committing. Fix sheet switches only if former-committer test is in this commit.

2. **`feat(client): review window status fields on client`** — Extend `review_window_info.dart` (nine fields, `sentAt` as `DateTime?`); `review_window_status.graphql` selections; map in `fetchReviewWindowStatus` (nullable ints/bools with `??` defaults matching entity `@Default`s); `build_runner`. No getter deletion.

3. **`feat(client): canFinalize respects optional targets`** — `evaluation_state.dart` plan getters + `canFinalize`; adjust/replace existing live finalize test; optional-target + all-optional-package rows (#180 / scenario 25).

4. **`feat(client): localized participant context and sheet`** — RED: `evaluation_participant_context_test.dart`; GREEN: `evaluation_participant_context.dart` (`intl` `DateFormat.yMMMd(locale.toLanguageTag())`, rules order per plan step 4, never server English); `evaluation_detail_sheet.dart` replace `:238–241` with presenter output (keep #76 layout minimal); update Owns sheet tests off legacy summary strings.

After each commit: `check-custom-lints.sh packages/client`. Final: full TEST_CMD.

TEST_CMD:
```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/features/evaluation --dart-define=ENV=test --dart-define-from-file=env/test.env
```

UNTOUCHABLE: pre-existing dirty/untracked; generated `_g/`/`*.g.dart`/`*.freezed.dart`; do not push; do not start UNIT 10 (`review_contributions_screen.dart`, cubit finalize/`packageState`, screen tests) except **`evaluation_state.dart` Owns**; do not delete `viewerHasOutstandingReviewWork` / `viewerCanOpenReviewScreen`; journal/doc/plan edits only for scout.

RISKS:
- **D17 vs Owns vs entity field removal** — highest risk; see STATUS.
- **Codegen order** — `.graphql` + freezed entity + ferry must land before repository compiles; one `build_runner` pass at end of step 1/2 may be needed twice.
- **`hasAnswer` vs `currentValue`/`isSubmitted`** — live finalize uses row status; a card with `currentValue` but `rowStatus == -1` is not finalizable (matches server readiness); tests must set `rowStatus` explicitly.
- **`reviewedCount` / screen `ready` tile** (`review_contributions_screen.dart:373`) still use `isSubmitted`/`hasAnswered` — UX drift until UNIT 10.
- **Batch `fetchReviewWindowStatuses`** still omits new fields — OK for this unit; My Work UNIT 13 widens query.
- **`evaluation_case_test.dart` / other evaluation tests** outside Owns still pass legacy constructor args — break if entity removes required legacy fields without mechanical fixes.
- **Handoff `promptVariant`** — extend committer condition to `formerCommitter` in `_promptText`.
- **Do not wire `packageState`** — UNIT 10 owns `deriveReviewPackageState` on state.

### inner — 2026-09-18 — UNIT 09 (Opus 5 low, incomplete)

STATUS: partial — steps 1–3 committed; step 4 presenter tests written then Opus hit monthly spend limit (resets 02:00 Europe/Amsterdam). Did not retry Opus. Did not spend Astra.

COMMITS:
1. `d912677c4 feat(client): evaluation participant DTO and role`
2. `d1f5264ed feat(client): review window status fields on client`
3. `c8fede875 feat(client): canFinalize respects optional targets`

Uncommitted at death: presenter + context tests (date-init added; tests +9) and un-wired sheet still using `contributionSummary`.

### overseer — UNIT 09 step 4 finish — 2026-09-18

Small local finish of the dead inner: committed `432d2839d feat(client): localize evaluation participant context on the sheet`. Sheet uses `presentParticipantContext` (D9), not `contributionSummary`. Independent TEST_CMD `flutter test test/features/evaluation` **+135**. contributionSummary/causalHint kept on entity (D17) for UNIT 10 screen.

Next: Composer verify on scout chat `07232140-54cd-4019-8db2-e8996a830838`.

### verify — 2026-09-18 — UNIT 09

STATUS: pass

TEST_OUTPUT:
- `flutter test test/features/evaluation` (via `run_with_test_cleanup.sh`, 15m) — **+135, −0** (~11.2s).

RANGE: `02db0c811..2a2d29593` — product commits `d912677c4`, `d1f5264ed`, `c8fede875`, `432d2839d`; journal `2a2d29593`. Worktree: no uncommitted changes under `packages/client/lib/features/evaluation/**` or UNIT 09 test paths; only pre-existing UNTOUCHABLE dirty/untracked elsewhere.

ACCEPTANCE (plan UNIT 09 + hard-unit checks + overseer correction):
- **formerCommitter / db `3`** — **met** — `_roleFromInt` maps `3 => formerCommitter` (`evaluation_repository.dart:518`); sheet exhaustive switches include `formerCommitter`; test `renders a former committer without crashing`.
- **`hasAnswer` is 0/1/2 only** — **met** — entity getter `:46`; test `hasAnswer covers draft, submitted and final only`.
- **`canFinalize` plan step 5** — **met** — `evaluation_state.dart`: draft `hasAnswered`, live `requiredParticipants.every(hasAnswer)`; tests `canFinalize ignores optional targets`, `canFinalize still requires every required target`, `empty participants are not finalizable`, plus `a package of only optional targets is finalizable unanswered`.
- **Presenter rule order (D9)** — **met** — `evaluation_participant_context.dart` matches plan step 4 order; EN/RU tests per rule including no-date fallback and optional ended line.
- **GraphQL plumb, no legacy selection** — **met** — both participant `.graphql` + `review_window_status.graphql` select new fields; no `contributionSummary`/`causalHint` in queries; repo maps structured fields + `sentAt` parse.
- **ReviewWindowInfo nine fields + getters kept** — **met** — entity `:20–28`; `fetchReviewWindowStatus` `:188–196`; `viewerHasOutstandingReviewWork` / `viewerCanOpenReviewScreen` unchanged (`:34–47`).
- **No `packageState`** — **met** — no import/use in `evaluation_state.dart`.
- **No checklist screen edits (UNIT 10)** — **met** — `git diff 02db0c811..HEAD` empty for `review_contributions_screen.dart`.
- **Sheet uses presenter, not server English** — **met** — `evaluation_detail_sheet.dart` `presentParticipantContext` at `:243+`; no `contributionSummary` read in sheet.
- **No generated committed (D18)** — **met** — commit file lists contain no `_g/` or `*.g.dart`/`*.freezed.dart`.
- **Plan acceptance (leaver vs helper + localized context on new paths)** — **met** — `isOptional` + `formerCommitter` + finalize gate; sheet/list-card path for sheet localized; repo leaves `contributionSummary`/`causalHint` at entity defaults (not fetched).
- **TEST_CMD** — **met** — independent run matches overseer **+135**.

GAPS:
- **Plan step 2 literal** — entity still carries `@Default('') contributionSummary`/`causalHint` (overseer D17 waiver); GraphQL/repo no longer populate — **intentional**, not a verify fail.
- **`review_contributions_screen.dart`** still displays `participant.contributionSummary` for list subtitles (UNIT 10); live fetches leave it empty — checklist may show role-only subtitles until UNIT 10 wires `presentParticipantContext`.
- **`review_contributions_screen_test.dart`** — four `rowStatus: 1` fixture lines in range (not in plan Owns; keeps screen tests aligned with live `canFinalize`).
- **`reviewedCount` / tile `ready`** still use `isSubmitted`/`hasAnswered` on checklist — scout-predicted drift until UNIT 10; not UNIT 09 scope.

### overseer — UNIT 09 accepted — 2026-09-18

Verdict: **accepted**. Opus-low steps 1–3, overseer step 4 after Opus spend limit, Composer verify pass. Independent TEST_CMD **+135**. D17: kept `contributionSummary`/`causalHint` on the entity; GraphQL no longer selects them. Screen list subtitles stay UNIT 10.

## UNIT 10 — Checklist: sections, progress, sent states

UNIT_BASE: `578b72f07` (`docs: accept UNIT 09…`; live `git rev-parse --short HEAD` at scout)
Inner: **ASTRA** slot A2. Opus is at spend limit until 02:00 Europe/Amsterdam — do not use Opus for this unit.

### scout — 2026-09-18 — UNIT 10

STATUS: ready (#162 primary surface; dependencies UNIT 08/09 landed)

BRIEF: Wire `deriveReviewPackageState` as `EvaluationState.packageState` (add `beaconIsInReview`/`beaconIsClosed` on state, defaults `@Default(true)`/`@Default(false)`; plan says “set from window read” but `ReviewWindowInfo` has no beacon lifecycle fields — leave defaults on happy-path loads in UNIT 10; UNIT 11 sets them in `_classifyLifecycleError`). Change live `finalize()` to **stay on screen**: remove post-success `_emitNavigateBack()`; add `_refreshAfterSend()` (refetch participants + window like `submitOne` `:176–191`); on refresh failure after successful send, **do not** revert UI — keep prior participants, locally set `windowInfo.userReviewStatus` to `2` (and `sentAt` if still null), snackbar only (scenario 5 / D16 date still from `sentAt` when present). Rebuild bottom bar from `state.packageState` only (never compare `userReviewStatus` to a number in the screen). Rebuild list: own-package notice (`viewerPackageOptional`), required section (`evaluationSectionRequired` + role grouping over `requiredParticipants` only), optional section (`evaluationSectionOptional` + hint + `optionalParticipants` minus in-memory `_skipped`); optional cards get `evaluationOptionalSkip` (local `setState`, no cubit, D8); required keep `evaluationCannotEvaluate`. Card subtitles: `presentParticipantContext` lines `line` → `offerLine` → `endedLine`; delete `contributionSummary` read (`:392–393`). Tile `ready` in live mode should align with `hasAnswer`/`rowStatus`, not only `isSubmitted` (`:373`), or CTA/progress drift vs `canFinalize` persists. `evaluationPackageDone`: tonal `FilledButton.tonal` + `TestIds.evaluationDone`; `pop` when `router.canPop()`, else `BeaconViewRoute(id: state.beaconId)`. Draft `finalize` still `_emitNavigateBack()` unchanged.

**Live gaps vs plan (exact edit targets):**
- `review_contributions_screen.dart` — `StatelessWidget`; single bottom bar always `evaluationProgress` + `evaluationSubmitFinish` (`:106–151`); empty body only when `participants.isEmpty` (`:82–104`), not `packageState.empty`; `_participantItems` groups all participants by role, no required/optional split (`:164–263`); no `formerCommitter` in `addRole` (optional leavers live under `isOptional`, not committer section).
- `evaluation_cubit.dart` `finalize` `:248–265` — always `_emitNavigateBack()` after successful live send (`:260`).
- `evaluation_state.dart` — no `packageState`, no beacon flags; `canFinalize` already correct (UNIT 09).
- `test_ids.dart` `:140–154` — no `evaluation.package_status` / `evaluation.done`.
- `review_contributions_screen_test.dart` — no UNIT 10 plan tests; fixtures use `contributionSummary: 'Helped'` and `rowStatus` where needed; `pump` sets minimal `ReviewWindowInfo` (no `userReviewStatus`/`sentAt`/`viewerPackageOptional`).
- `evaluation_cubit_lifecycle_test.dart` — only draft dispose test; Owns allows adding live `finalize` / `NavigateBack` oracle.
- `FakeEvaluationRepository.finalize` (`evaluation_case_test.dart:495–498`) does not bump `reviewWindowResult` — screen/cubit tests must stub post-send window (`userReviewStatus: 2`, `sentAt`) on refresh or in fake.

STEPS (test-first; one commit subject per plan: `fix(client): show whether the review package was sent`):

1. **RED state/cubit** — `evaluation_state.dart`: import `review_package_state.dart`; add `beaconIsInReview`, `beaconIsClosed`, `packageState` getter (plan literal); `dart run build_runner` for freezed. `evaluation_cubit.dart`: plan `finalize` + `_refreshAfterSend()`; optional `evaluation_cubit_lifecycle_test.dart`: `live finalize does not emit NavigateBack`; refresh-failure test with gated `fetchReviewWindowStatus` throw after `finalize` asserts local status 2 + no `NavigateBack`.
2. **RED screen** — Add eight named widget tests from plan §UNIT 10 in `review_contributions_screen_test.dart`; extend `FakeEvaluationRepository` / `pump` helpers for `rowStatus`, `isOptional`, `sentAt`, `userReviewStatus`, multi-participant 360×`TextScaler.linear(2)` (`MediaQuery` already in harness — match plan `Size(360, 800)`).
3. **GREEN screen** — Convert to `StatefulWidget` + `_skipped`; extract bottom bar widget switching on `packageState` (`inProgress`, `readyToSend`, `sent`, `changedNotSent`, `empty`; do not implement paused/closed bodies — UNIT 11); progress via `evaluationProgressSplit(req, reqTotal, opt, optTotal)` from `requiredParticipants`/`optionalParticipants` and `hasAnswer` counts; status key `TestIds.evaluationPackageStatus` (new const, value `evaluation.package_status`). Skip action on optional tiles only.
4. **GREEN list/context** — Section rebuild + `presentParticipantContext` in `_ParticipantTile`; remove legacy summary.
5. **Verify** — `check-custom-lints.sh packages/client` after `lib/` edits.

TEST_CMD:
```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/features/evaluation --dart-define=ENV=test --dart-define-from-file=env/test.env
```

UNTOUCHABLE: pre-existing dirty/untracked; generated `_g/`/`*.g.dart`/`*.freezed.dart` (regen locally, do not commit); UNIT 11/12 HUD/banner/My Work; do not persist skip set; do not push; do not add paused/closed full-body UI (UNIT 11); do not delete `viewerHasOutstandingReviewWork` / `viewerCanOpenReviewScreen` (UNIT 12).

RISKS:
- **`beaconIsInReview`/`beaconIsClosed` source** — not on GraphQL `reviewWindowStatus`; defaults suffice for UNIT 10 acceptance tests; wrong `paused`/`closed` derivation until UNIT 11 — do not test spontaneous lifecycle here.
- **Existing screen tests** — copy expecting `evaluationProgress` / `0 of 1 reviewed` may need updating to `evaluationProgressSplit` and `hasAnswer`-based CTA; `Left to review` hint only for `inProgress`.
- **Subtitle tests** — after presenter wiring, untouched cards show `evaluationContextCommittedNoDate` (not empty subtitle); scroll tests using `contributionSummary` text need fixture dates/messages.
- **`TextStyle(fontSize: tt.iconSize)`** in tile `:430` — pre-existing; avoid drive-by unless linter flags on touch.
- **360×2.0** — long header stack (title, intro, privacy, deadline, two section headers) can push first participant off viewport; plan requires asserting a participant **below** headers is built, not merely no overflow.
- **Skip + stored row** — assert cubit `participants` length unchanged and optional `rowStatus` still present after hide (D8).
- **Astra inner** — slot A2; do not spend Opus (spend limit).

### checkpoint — UNIT 10 — 2026-09-18 — overseer

Astra slot A2 **failed closed**: `codex` usage limit, retry at **05:51**. ~50k tokens spent reading, **no product commits**. Do not retry Astra until that reset. Opus-low is also at monthly spend (resets 02:00 Europe/Amsterdam). Skill substitute for unavailable Astra is Opus **high** once Claude is back; do not spend remaining post-06:00 Astra on a second UNIT 10 inner attempt if Opus-high already landed it.




### inner — 2026-09-18 — UNIT 10 (Opus 5, Astra substitute)

STATUS: complete — plan steps 1–6 landed, test-first, three commits, nothing pushed.

COMMITS (on `fix/162-180-review-package-state`, base `578b72f07`):
1. `c2a6bfe19 fix(client): keep the reviewer on the checklist after a send` — state flags + `packageState` + cubit `finalize`/`_refreshAfterSend`.
2. `8b2887c11 fix(client): show whether the review package was sent` — bottom bar by package state, sections, local skip, presenter subtitles, two new `TestIds`.
3. `e090142a5 test(client): Done opens the request on a deep-linked sent package`.

TEST_OUTPUT: `flutter test test/features/evaluation` (wrapped, 15m) — **+148, −0** (~5s). `check-custom-lints.sh packages/client` — 30, baseline 30. `dart analyze lib test` — no errors. No `*.freezed.dart` / `_g/` committed (gitignored; regenerated locally).

WHAT LANDED (plan §UNIT 10):
- **Step 1** — `EvaluationState.beaconIsInReview` (`@Default(true)`) / `beaconIsClosed` (`@Default(false)`) + `packageState` getter, plan literal. No other feature's cubit is read; happy-path loads keep the defaults (UNIT 11 sets them).
- **Step 2** — live `finalize()` no longer calls `_emitNavigateBack()`; it awaits `_refreshAfterSend()` (participants, then window). A refresh that throws after a successful send keeps the previous participants, patches `windowInfo` to `userReviewStatus: 2` (and `sentAt` if still null), and surfaces only a snackbar. Draft `finalize` still navigates back.
- **Step 3** — `_PackageBottomBar` switches on `state.packageState`; `inProgress` / `readyToSend` / `sent` / `changedNotSent` per plan. `TestIds.evaluationSubmit` stays on the primary CTA in `readyToSend` and `changedNotSent`; new `TestIds.evaluationPackageStatus` (`evaluation.package_status`) and `TestIds.evaluationDone` (`evaluation.done`). `evaluationPackageDone` pops when `router.canPop()`, else `router.replace(BeaconViewRoute(id: state.beaconId))`. `empty` is the existing body with no CTA; the lifecycle states fall through to the progress line only — **no paused/closed bodies** (UNIT 11).
- **Steps 4–5** — own-package notice (`viewerPackageOptional`), `Required` section over `requiredParticipants` with the existing role grouping (`formerCommitter` grouped with helpers), `Optional` section with the hint, minus a screen-local `_skipped` set on a `StatefulWidget`. Skip calls `setState` only.
- **Step 6** — card subtitles are `presentParticipantContext` (`line` → `offerLine` → `endedLine`); the `contributionSummary` read is gone. Live tile readiness is now `participant.hasAnswer`, matching the send gate.

FINDINGS (worth carrying):
- **The bottom bar can eat the whole screen.** At 320×700 / `textScaler 2.0` the `readyToSend` bar (status + CTA + `evaluationPackageSentHint`, 350px of copy) left the `ListView` **44px** tall, so the checklist built one item and the pre-existing narrow/large-text tests failed with no overflow error. Fixed by capping the bar at `_maxBottomBarShare = 0.4` of the viewport and letting it scroll inside its share. Any future copy added to this bar inherits that budget.
- **Two scrollables now.** The bar's `SingleChildScrollView` broke `scrollUntilVisible(scrollable: find.byType(Scrollable))` with `Bad state: Too many elements` in two pre-existing tests; they now pass `.first` (the list).
- **`skipOffstage` hides cache-region items.** At 360×800 / 2.0 the header stack (intro 252px + privacy + deadline) is taller than the 444px viewport, so the sections are below the fold. Default finders skip items built into the cache region, so the plan's "assert the item is actually built" is written as `find.text('Required', skipOffstage: false)` plus a `scrollUntilVisible` to the card — a list that stops building items fails both, which is the trap the plan names.
- **`reviewedCount` still counts `isSubmitted` in live mode** (`evaluation_state.dart`). The bar no longer uses it (it counts `hasAnswer` per section), but the getter is still live for other surfaces — UNIT 12/13 should decide whether it follows `hasAnswer`.
- `FakeEvaluationRepository.finalize` still does not bump the window; screen tests model the server with a local `_PackageRepository` subclass (`windowAfterFinalize` / `windowAfterSubmit`).

TESTS ADDED: the eight named plan tests in `review_contributions_screen_test.dart`, plus `Done on a sent package opens the request when nothing can pop`; in `evaluation_cubit_lifecycle_test.dart`: `live finalize stays on screen and refreshes the package`, `refresh failure after a successful send keeps the package sent`, `draft finalize still navigates back`, `packageState derives from the window and the required rows`.

REMAINING / NOT DONE (out of unit scope):
- `beaconIsInReview` / `beaconIsClosed` are never set from a read — UNIT 11.
- `paused` / `closed` / `closedUnsent` / `notEnrolled` render only the progress line — UNIT 11.
- The optional section is omitted entirely when every optional card is skipped (no dangling header + hint); the stored rows are untouched, so nothing is lost.

PRE-EXISTING RED, NOT UNIT 10 (for the overseer): the full client suite (`flutter test packages/client`, **+3537 ~29 −1**) has one failure, `test/architecture/updates_event_contract_test.dart` — `Updates contract has the exact revision 4 semantic coverage`, row `[9]` is `reviewAllPackagesIn` where the fixture expects `mutualConnectionFormed`. That row arrives with the UNIT 05 nudge event (`3c769e4d3` / `f3f557f70`); the client contract fixture was never widened. Untouched by UNIT 10 (no file in this unit's commits feeds that test) — likely UNIT 14 or a UNIT 05 follow-up.

### verify — 2026-09-18 — UNIT 10

STATUS: pass

TEST_OUTPUT:
- `cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/features/evaluation --dart-define=ENV=test --dart-define-from-file=env/test.env` — **+148, −0** (~10.3s). Matches overseer **+148**.

RANGE: `578b72f07..0b27c5885` (5 commits: `c2a6bfe19`, `8b2887c11`, `e090142a5`, `0ee85b8a7`, `0b27c5885`). Owns-only diff: cubit, state, `review_contributions_screen.dart`, `test_ids.dart`, two test files, journal. No uncommitted changes under `packages/client/lib/features/evaluation/**` or UNIT 10 tests at verify time.

ACCEPTANCE (plan UNIT 10 + hard-unit checks + overseer follow-up):

| Criterion | Verdict | Evidence |
|-----------|---------|----------|
| Live `finalize()` does not `NavigateBack` | **met** | `evaluation_cubit.dart:248–261` — success path calls `_refreshAfterSend()` only; `evaluation_cubit_lifecycle_test.dart` `live finalize stays on screen…` asserts zero `NavigateBack`. |
| Post-send refresh failure: sent locally, not loading | **met** | `_refreshAfterSend` catch patches `userReviewStatus: 2`, `sentAt`, `status: StateStatus.isSuccess` (`:291–303`); `0b27c5885` adds explicit success emit on that path; lifecycle test `refresh failure after a successful send…` asserts `packageState.sent`, `isLoading` false, `ShowError` once. |
| Screen uses `packageState`, not numeric `userReviewStatus` | **met** | `review_contributions_screen.dart` — `switch (state.packageState)` in `_PackageBottomBar` (`:468`); ripgrep: no `userReviewStatus` in screen file. |
| Local skip (D8), no cubit | **met** | `_skipped` + `setState` (`:60`, `:318`); widget test `skip hides an optional card without calling the cubit` — `submitCalls`/`draftDeleteCalls` 0, participants length unchanged. |
| `contributionSummary` removed from checklist UI | **met** | No `contributionSummary` in screen; subtitles via `presentParticipantContext` (`:599+`). Entity field retained (D17). |
| 360×2.0 builds participant card(s) | **met** | `sections render at 360px and textScaler 2.0` — `Required` `skipOffstage: false`, `scrollUntilVisible` to `evaluation.participant.u1` and `u2`. |
| `TestIds.evaluationSubmit` on `readyToSend` and `changedNotSent` | **met** | `_PackageBottomBar` `cta()` always keys `evaluationSubmit` (`:438–442`); tests `first fill offers…`, `editing a card after a send offers Send changes` assert enabled submit button. |
| Paused/closed bodies not implemented (UNIT 11) | **met** | No `evaluationPaused*` / `evaluationClosed*` in screen; lifecycle states fall through to progress-only bar (`:525–530`). |
| `packageState` getter on state (plan step 1) | **met** | `evaluation_state.dart:27–37` literal `deriveReviewPackageState` inputs; `beaconIsInReview`/`beaconIsClosed` defaults present. |
| Bottom bar matrix (inProgress / ready / sent / dirty) | **met** | `_PackageBottomBar` cases `:469–521`; sent uses `evaluationPackageSentAt` + tonal Done (`evaluation.done`). |
| Sections + optional skip + own-package notice | **met** | `_participantItems` required/optional split; tests `viewerPackageOptional…`, `skipping an optional card with a stored row…`. |
| Draft `finalize` still pops | **met** | `evaluation_cubit.dart:249–252`; lifecycle test `draft finalize still navigates back`. |
| Eight plan-named screen tests | **met** | All present in `review_contributions_screen_test.dart` (`:536`–`:744` region). |
| #162 acceptance (submit then stay sent) | **met** | `after a send the screen stays and shows the sent status` — no submit CTA, `evaluation.package_status` shows sent date. |
| Plan Verify TEST_CMD | **met** | Independent run **+148**. |

GAPS:
- **`beaconIsInReview` / `beaconIsClosed` never set from reads** — defaults only until UNIT 11 (`_classifyLifecycleError`); not a UNIT 10 fail (scout + inner acknowledged).
- **Lifecycle package states UI** — `paused` / `closed` / `closedUnsent` / `notEnrolled` show progress line only, not replacement body; UNIT 11 owns full copy.
- **`reviewedCount` live mode still uses `isSubmitted`** (`evaluation_state.dart:39–41`); bar uses `hasAnswer` counts — HUD/My Work drift until UNIT 12/13 (inner FINDING).
- **Optional section hidden when all optional cards skipped** — intentional inner behavior; stored rows remain in cubit state (tested).
- **No generated files in commits** — `evaluation_state.freezed.dart` gitignored; suite green implies local regen OK (D18).

### overseer — UNIT 10 accepted — 2026-09-18

Verdict: **accepted**. Opus 5 high substitute for Astra A2; follow-up `0b27c5885` for loading after refresh failure. Composer verify **+148**. Checklist #162 primary surface met; UNIT 11/12 untouched as required.

Independent overseer: TEST_CMD **+148**; `_refreshAfterSend` catch now emits `isSuccess`; skip is local `setState`; screen switches on `packageState`; `evaluationSubmit` on send CTAs.

UNIT 11 UNIT_BASE: `0b27c5885` (journal commit of this accept will sit on top — scout uses HEAD after this commit). Inner: Opus-low. Astra reserved for UNIT 12 (A3). Do not probe Astra until 05:51.

## UNIT 11 — Checklist: paused / closed classification

UNIT_BASE: `c9182d93f` (live `git rev-parse --short HEAD` at scout)

### scout — 2026-09-18 — UNIT 11

STATUS: ready (UNIT 10 accepted; `packageState` wired; lifecycle UI deferred)

BRIEF: On `EvaluationReviewWindowNotOpenException` (1401) or `EvaluationReviewWindowExpiredException` (1405) in **live** `loadParticipantsOnly`, `submitOne`, `clearOne`, and `finalize`, call `_classifyLifecycleError(originalError)` instead of `_emitSnackError` — **never** map 1401→paused vs 1405→closed by code (D12). Classify = single `fetchReviewWindowStatus` only; **do not** refetch participants (plan: stale list not rebuilt in paused). On success: `emit(copyWith(windowInfo: window, beaconIsInReview: …, beaconIsClosed: …, status: isSuccess))`. On classify failure: `_emitSnackError(originalError)`; leave prior state.

**Close the plan “from window read” gap (no GraphQL/repo edits in this unit):** `ReviewWindowInfo` has no beacon lifecycle fields. Derive flags from the classify snapshot + enrollment context:

| Classify read | `beaconIsClosed` | `beaconIsInReview` |
|---|---|---|
| `windowComplete == true` | `true` | `false` |
| `hasWindow && !windowComplete` | `false` | `true` |
| `!hasWindow && !windowComplete` after lifecycle error **and** `state.participants.isNotEmpty` (enrolled viewer, author **reopen** — server deletes window row, `reviewWindowStatus` returns `hasWindow: false` only) | `false` | **`false`** → `deriveReviewPackageState` → **`paused`** |
| `!hasWindow && !windowComplete` with empty participants (never enrolled / no stale package) | `false` | keep default **`true`** → **`notEnrolled`** |

With UNIT 10 defaults (`beaconIsInReview: true`, `beaconIsClosed: false`), `!hasWindow` alone yields **`notEnrolled`**, not **`paused`** — the enrolled+reopen row is mandatory.

Also set the same flags whenever a happy-path emit already sets `windowInfo` (`loadAll`, `loadParticipantsOnly` success, `submitOne`/`clearOne` refresh, `_refreshAfterSend` success) using the first three rows only (no `participants.isNotEmpty` heuristic on happy path).

**Server truth (for fakes):** `reviewWindowStatus` when `getReviewWindow == null` → `hasWindow: false`, title only (`evaluation_case.dart:1055–1060`). When window `status == 1` → `hasWindow: true`, `windowComplete: true`, `sentAt` still readable (`:1142–1158`). Mutations use `_requireLiveReview` → same **1401** after reopen **and** after final close (`:1161–1173`); only the classify read distinguishes. `evaluationParticipants` requires live window (D13) — `loadParticipantsOnly` fetches participants **before** window (`evaluation_cubit.dart:109–115`), so a vanished window often throws **1401 on participants**; that catch must classify too.

**Screen (`review_contributions_screen.dart`):** Before list/empty/bottom-bar branch, if `!draft && packageState` is `paused` | `closed` | `closedUnsent`, replace **entire** `body` (no `ListView`, no `_PackageBottomBar`, no send CTA). Copy: `evaluationPausedTitle` + `evaluationPausedBody` + primary `evaluationPausedAction` → same navigation as `_onPackageDone` (`BeaconViewRoute` when cannot pop). `closed` / `closedUnsent`: `evaluationClosedSentBody` / `evaluationClosedUnsentBody` + **text link** (not filled CTA) using existing key `reviewWindowViewReceivedReviewsAction` → `context.router.push(ReceivedReviewsRoute(id: state.beaconId))` (pattern: `beacon_operational_header_card.dart:129–132`). Remove lifecycle cases from `_PackageBottomBar` progress fallback (`:525–530`) once body handles them. Design system: `context.tt`, `TenturaText.*`, no raw colors/sizes.

**Cubit catch shape:** `} on EvaluationReviewWindowNotOpenException catch (e) { await _classifyLifecycleError(e); }` (and 1405); other errors unchanged. Draft mode: keep generic snack on errors. `finalize` after failed send: classify, not `_refreshAfterSend`.

STEPS (test-first; commit `fix(client): explain a review window cancelled by the author`):

1. **RED** — `evaluation_cubit_lifecycle_test.dart`: five plan-named tests; extend `FakeEvaluationRepository` with `submitError` / `participantsError` typed throws + classify `reviewWindowResult` stubs (`hasWindow: false` for paused; `windowComplete: true` + `sentAt` for closed; without `sentAt` for closedUnsent; failing second `fetchReviewWindowStatus` for classify failure; assert `participantsResult` fetch count unchanged across classify).
2. **GREEN cubit** — `_classifyLifecycleError(Object originalError)` + `_lifecycleFlagsForWindow(ReviewWindowInfo window, {required bool afterLifecycleError})`; wire four methods; optional happy-path flag updates on existing `windowInfo` emits.
3. **GREEN screen** — `_LifecyclePackageBody` (or inline) early in `build`; hide bottom bar for lifecycle states.
4. **Verify** — `check-custom-lints.sh packages/client` after `lib/` edits.

TEST_CMD:
```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/features/evaluation --dart-define=ENV=test --dart-define-from-file=env/test.env
```

UNTOUCHABLE: pre-existing dirty/untracked (journal §UNTOUCHABLE); generated `_g/`/`*.g.dart`/`*.freezed.dart`; UNIT 12 HUD/banner/`review_window_banner_host.dart`; no second error mapper; no polling; no spontaneous-transition test; do not revert UNIT 10 stay-after-send; do not edit `review_window_info.dart` / repository / GraphQL in this unit unless BLOCKED (prefer cubit inference above).

RISKS:
- **`loadParticipantsOnly` order** — participants-first means classify runs with stale participants (intended); empty participants + `!hasWindow` shows `notEnrolled` not `paused` — tests must seed non-empty participants for paused oracle.
- **1405 vs 1401** — same classify path; closed outcome must come from `windowComplete`/`sentAt`, not exception type.
- **`_refreshAfterSend` on window closed after send** — if finalize succeeds then refresh throws 1401, today snacks; UNIT 11 may need classify on that catch too if in scope — plan lists `finalize` catch only on `finalize()` try, not `_refreshAfterSend` inner catch (leave refresh path as UNIT 10 unless product asks).
- **Closed UI link copy** — plan §2 names only bodies; reuse `reviewWindowViewReceivedReviewsAction` (already EN/RU), not new strings.
- **`notEnrolled` on checklist** — rare; no dedicated copy in UNIT 11; do not add strings.

### inner — 2026-09-18 — UNIT 11 — Opus 5 low

STATUS: complete

COMMITS (UNIT_BASE `c9182d93f`):
- `23a408bce fix(client): classify vanished review windows by re-reading status`
- `fix(client): explain a review window cancelled by the author` (screen + 2 widget tests)

NOTES:
- Red run first: 4/5 plan-named lifecycle tests failed; the classify-failure test already passed (current code snacks the original error) and stays as a regression guard.
- `_withWindow(base, window, afterLifecycleError:)` derives flags: windowComplete → closed; hasWindow → in review; !hasWindow → paused only after a 1401/1405 with non-empty participants. Used on all happy-path windowInfo emits (loadAll, loadParticipantsOnly, submit/clear refresh, _refreshAfterSend).
- `_onError` routes 1401/1405 (live only) to `_classifyLifecycleError` in loadParticipantsOnly, submitOne, clearOne, finalize, and `_refreshAfterSend` catch (after the UNIT 10 optimistic-sent emit, so non-lifecycle errors are unchanged). loadAll still snacks (not in brief).
- Screen: `_LifecyclePackageBody` replaces the whole body for paused/closed/closedUnsent (no ListView, no bottom bar); paused button reuses `_onPackageDone`; closed link = TextButton → `ReceivedReviewsRoute`.

VERIFY: TEST_CMD +155 all passed; check-custom-lints packages/client OK (30/30 baseline).

### verify — 2026-09-18 — UNIT 11

STATUS: pass

TEST_OUTPUT:
- `cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/features/evaluation --dart-define=ENV=test --dart-define-from-file=env/test.env` — **+155, −0** (~11.3s). Matches inner/overseer **+155**.

RANGE: `c9182d93f..dbb405fb3` (3 commits: scout journal, `23a408bce`, `d2876e587`, `dbb405fb3`). Owns diff: `evaluation_cubit.dart`, `review_contributions_screen.dart`, `evaluation_cubit_lifecycle_test.dart`, `review_contributions_screen_test.dart` (+ journal). No uncommitted changes under `packages/client/features/evaluation` at verify time. `evaluation_state.dart` unchanged (flags set via cubit `_withWindow`).

ACCEPTANCE (plan UNIT 11 + hard-unit checks):

| Criterion | Verdict | Evidence |
|-----------|---------|----------|
| D12: classify by re-read, not 1401 vs 1405 | **met** | `_classifyLifecycleError` only `fetchReviewWindowStatus` (`evaluation_cubit.dart:96–108`); `_onError` treats both exception types identically (`:115–122`). Closed vs paused from `windowComplete` / `hasWindow` + flags, not error type. |
| Paused: non-empty participants + `!hasWindow` after lifecycle error | **met** | `_withWindow` `beaconIsInReview: !(afterLifecycleError && base.participants.isNotEmpty)` (`:87–91`); lifecycle test `submitOne on a vanished window…` stubs `hasWindow: false` with loaded participants → `packageState.paused`. |
| Classify does not `fetchParticipants` | **met** | `_classifyLifecycleError` has no participants call; tests assert `participantsCalls` unchanged (`evaluation_cubit_lifecycle_test.dart:323–324`, `:411`). |
| Classify-fail snacks original error, keeps state | **met** | `catch (_) { _emitSnackError(originalError); }` (`:109–111`); test `a failing classification read…` asserts `same(original)`, window/participants unchanged. |
| Wire 1401/1405 in loadParticipantsOnly, submitOne, clearOne, finalize | **met** | All four use `await _onError(e)` in catch (`:189–191`, `:257–259`, `:306–308`, `:327–329`). |
| Screen: whole-body replacement, no list/CTA | **met** | Early return `_LifecyclePackageBody` (`review_contributions_screen.dart:93–99`); widget tests assert no `ListView`, no `evaluationSubmit`, no participant tile. Closed uses `TextButton` + `ReceivedReviewsRoute` (`:594–598`). |
| Plan five named cubit tests | **met** | All five in `lifecycle classification (D12)` group (`:302–414`). |
| No polling / no spontaneous-transition test | **met** | No timer/subscription added; no test asserts idle transition. |
| No second error mapper | **met** | Only existing `evaluation_error_mapper.dart`; cubit imports typed exceptions. |
| UNIT 10 stay-after-send intact | **met** | Live `finalize` success → `_refreshAfterSend()` only (`:324–326`); draft still `_emitNavigateBack()` (`:314–317`); prior lifecycle tests for refresh failure unchanged in suite. |
| Plan Verify TEST_CMD | **met** | Independent **+155**. |

GAPS:
- **`loadAll` still snacks on 1401/1405** (`:149–151`) — screen uses `loadParticipantsOnly` only; scout noted, not plan UNIT 11 Owns requirement.
- **`_PackageBottomBar` dead lifecycle cases** (`:538–543`) — unreachable when body handles lifecycle first; harmless dead code, not acceptance fail.
- **Two extra widget tests** (`review_contributions_screen_test.dart:630–691`) — added after screen (not red-first); assertions are substantive (copy, no checklist, navigation/link).
- **`_refreshAfterSend` catch now calls `_onError`** — successful send then 1401 on refresh can classify to closed/paused instead of snack-only; extends UNIT 10 path, aligns with lifecycle handling, not required by plan text.

### overseer — UNIT 11 accepted — 2026-09-18

Verdict: **accepted**. Opus-low inner; Composer verify **+155**. D12 classify-by-reread is correct; paused heuristic matches UNIT 08 `!hasWindow && !beaconIsInReview`. Screen uses `loadParticipantsOnly`, so unused `loadAll` snack is deferred.

Astra A3 for UNIT 12 remains parked until ~05:51 (do not probe). Next: UNIT 12 scout (Composer, no Astra spend) so the brief is ready when quota returns; UNIT 13 waits on 12; UNIT 14 can run in the wait window (depends on 05/06/09 only).

## UNIT 12 — HUD and banner by package state

UNIT_BASE: `1eabfab62` (live `git rev-parse --short HEAD` at scout)

### scout — 2026-09-18 — UNIT 12

STATUS: ready (UNIT 08 `deriveReviewPackageState`, UNIT 09 nine window fields + getters still live, UNIT 07 l10n; UNIT 10/11 checklist done — do not touch checklist)

BRIEF: **Kill #162 on the request HUD** by driving author review ACT from `ReviewPackageState`, not `viewerHasOutstandingReviewWork` / `viewerCanOpenReviewScreen` / raw `userReviewStatus`. After send, the author HUD must **not** offer a filled primary **review** CTA; close-now stays a separate primary when `canCloseNow == true` (i.e. `allRequiredSent`). **D17:** delete both getters from `review_window_info.dart` and every reference — post-edit grep must print nothing under `packages/client/lib` and `packages/client/test`.

**§2.1 matrix (role × state × `allRequiredSent`) — normative surfaces:**

| Viewer | State | `allRequiredSent` | HUD (author) | Banner |
|---|---|---|---|---|
| any | `inProgress` | — | primary `beaconHudActReviewContributions` + effect `beaconHudActEffectReviewProgress(remaining, requiredTotal)` where `remaining = requiredTotal - requiredReviewed` | non-author: primary review CTA + same progress effect; author in own work: banner empty (HUD owns ACT) |
| any | `readyToSend`, `changedNotSent` | — | primary review CTA, effect `beaconHudActEffectReviewContributions` (neutral) | non-author: primary review CTA, no progress line |
| author | `sent` | false | **no** review ACT; banner: `beaconHudReviewSent` + `beaconHudWaitingForRequiredReviews` + **TextButton** `beaconHudReviewEdit` | |
| author | `sent` | true | **primary close-now** (outranks review) + banner status/edit as above (no second primary review button) | |
| non-author | `sent` | — | n/a | `beaconHudReviewSent` + `beaconHudWaitingForAuthorClose` + **TextButton** `beaconHudReviewEdit` — **never** `FilledButton` |
| any | `paused`, `closed`, `closedUnsent`, `notEnrolled`, `empty` | — | no review ACT | no review CTA (host already shrinks when `!hasWindow \|\| windowComplete`; lifecycle copy is checklist UNIT 11) |

**Live bug (confirm at `beacon_hud_author_action.dart:138–158`):** `_reviewOpenAuthorAction` returns `reviewContributions` when `viewerHasOutstandingReviewWork` **or** `viewerCanOpenReviewScreen` — so **sent** (`userReviewStatus: 2`) still gets a filled “Review contributions” HUD ACT (`beacon_hud_author_action_test.dart:208–227` encodes the bug as expected). **Plan order:** after null-guard, **`if (review.canCloseNow == true) return closeNow` first**, then `switch (reviewPackageStateOf(state))` with review ACT only on `inProgress \| readyToSend \| changedNotSent`; all other states → `null` for review ACT.

**`reviewPackageStateOf(BeaconViewState state)`** (export from `beacon_hud_author_action.dart` or same presenter file — banner may import it; **do not** put helpers on checklist cubit/screen): call `deriveReviewPackageState` with:

```dart
beaconIsInReview: state.beacon.status == BeaconStatus.reviewOpen && !(review?.windowComplete ?? false),
beaconIsClosed: state.beacon.status == BeaconStatus.closed || (review?.windowComplete ?? false),
hasWindow: review?.hasWindow ?? false,
windowComplete: review?.windowComplete ?? false,
userReviewStatus: review?.userReviewStatus,
sentAt: review?.sentAt,
requiredTotal: review?.requiredTotal ?? 0,
requiredAnswered: review?.requiredReviewed ?? 0,
totalTargets: review?.totalCount ?? 0,  // server: vis.length (evaluation_case.dart:1145)
```

No new GraphQL / `BeaconViewState` fields (mirror UNIT 11 inference, without checklist `participants.isNotEmpty` paused heuristic — beacon detail only mounts banner under `BeaconStatus.reviewOpen`, `fetchReviewWindowStatusIfReviewOpen`). **`BeaconViewState` has no `beaconIsInReview`/`beaconIsClosed` fields** — infer from beacon status + window snapshot only.

**Effect line (plan step 3):** extend `deriveBeaconHudAuthorActSpec` (not only `effectLineForBeaconHudAuthorAction`) so `reviewContributions` + `inProgress` uses `beaconHudActEffectReviewProgress`; `readyToSend` / `changedNotSent` keep `beaconHudActEffectReviewContributions`.

**Banner (`review_window_banner_host.dart:58–105`):** replace `viewerCanOpenReviewScreen` filled `ReviewBanner` and author branch using `beaconHudWaitingForReviews` + `viewerHasOutstandingReviewWork`. Implement §2.1 with `reviewPackageStateFromWindow(review, isAuthor: …)` sharing the same derive inputs as above (host only receives `ReviewWindowInfo?` + `isAuthor` — pass `beaconIsInReview`/`beaconIsClosed` derived assuming live `reviewOpen` mount, or add optional params if cleaner). Edit navigates via `ReviewContributionsRoute(id: review.beaconId)` like today. **`review_banner.dart`:** only caller is this host (`isDraftPhase: false`); refactor or inline — drop filled “Review” card for **sent**; non-author **unsent** states may still use a filled primary with `beaconHudActReviewContributions` label (not legacy `evaluationBannerReview`).

STEPS (test-first; commit `fix(client): stop re-offering a review that was already sent`):

1. **RED** — Replace/extend tests per plan names in `beacon_hud_author_action_test.dart` and `review_window_banner_host_test.dart`: table over nine `ReviewPackageState` values × `isAuthor` × `allRequiredSent` where applicable; four named oracles: `at most one primary review CTA per state`, `no primary review CTA in sent`, `the author keeps close-now in sent when allRequiredSent`, `the author waiting on others does not see the author-waiting copy` (assert non-author **never** finds `beaconHudWaitingForRequiredReviews`; author `sent` + `!allRequiredSent` **does**). Delete getter test groups (`review_window_banner_host_test.dart:57–94`). Fix `reviewOpen prefers review UI until server canCloseNow` — sent + `canCloseNow: false` must expect **null** HUD review ACT, not `reviewContributions`.
2. **GREEN HUD** — Plan literal `_reviewOpenAuthorAction` + `reviewPackageStateOf`; dynamic effect in `deriveBeaconHudAuthorActSpec`.
3. **GREEN banner** — Matrix-driven `ReviewWindowBannerHost`; remove getter usage.
4. **GREEN D17** — Remove getters from `review_window_info.dart` (`:34–47`); run `build_runner` locally if freezed complains; **grep verification**:

```bash
cd /home/vader/MY_SRC/tentura && grep -rn "viewerHasOutstandingReviewWork\|viewerCanOpenReviewScreen" packages/client/lib packages/client/test
```

5. **Verify** — `check-custom-lints.sh packages/client` after `lib/` edits.

TEST_CMD:
```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/features/beacon_view test/features/evaluation --dart-define=ENV=test --dart-define-from-file=env/test.env
```

UNTOUCHABLE: pre-existing dirty/untracked (journal §UNTOUCHABLE); generated `_g/`/`*.g.dart`/`*.freezed.dart` (regen locally, do not commit); **UNIT 10/11 checklist** (`review_contributions_screen.dart`, `evaluation_cubit.dart` lifecycle except if accidentally touched — must not); **UNIT 13 My Work**; do not persist skip; do not push; HUD helper **must not** live on checklist screen/cubit.

RISKS:
- **Paused vs `notEnrolled` on beacon detail** — without checklist `participants.isNotEmpty` heuristic, `!hasWindow` while still `reviewOpen` maps to `notEnrolled`; banner already hidden when `!hasWindow`; low product impact.
- **`totalCount` vs participant list** — HUD uses window `totalCount`/`requiredTotal`/`requiredReviewed`, not checklist rows; must match server visibility (UNIT 03); all-optional package: `requiredTotal == 0` → `readyToSend` when answered per UNIT 08 tests.
- **Author `sent` + `canCloseNow: false`** — HUD null review ACT but banner shows waiting-for-others copy; ensure HUD filled button absent while TextButton Edit still opens checklist (edit is not a “primary review CTA”).
- **Legacy `beaconHudWaitingForReviews`** — banner author-wait branch uses old key (`:92`); matrix requires `beaconHudWaitingForRequiredReviews` for author sent/waiting.
- **Existing banner tests** — expect filled `Review` for sent non-author (`:110–116`); must flip to `Edit` text + status lines, no `ReviewBanner` filled child.
- **`deriveBeaconHudAuthorActSpec` semantics** — `semanticsLabel` should include progress effect when shown; keep close-now `hiddenKeepSemantics`.
- **Freezed regen** — removing custom getters on `ReviewWindowInfo` is source-only; do not commit generated files (D18).

Park inner until Astra quota (~05:51 CEST). Do not probe Astra. Do not start UNIT 13. UNIT 14 shares `my_work_cards.dart` with UNIT 13 — do not implement 14 until 13 lands.

---

## UNIT 14 — scout — 2026-09-18

UNIT_BASE: `2600af80c` (current HEAD = UNIT_BASE). Dependencies 05/06/07/09 present on branch (`ReviewWindowInfo.sentReviewerCount` / `unsentStartedPackages` at `review_window_info.dart:27–28`; l10n `beaconReviewCloseNow*` / `beaconReviewReopenBody(sent)` / `updatesFallback*` keys in arbs).

STATUS: complete

BRIEF: Wire **four** author paths through **one** shared close confirm and **one** shared reopen confirm in `beacon_hud_author_confirm_sheets.dart` (plan step 1). **Close body:** `beaconReviewCloseNowBody` + when `unsentStartedPackages > 0` append `beaconReviewCloseNowDiscardNote(unsentStartedPackages)` — **never** `optionalTotal - optionalReviewed`. **Reopen body:** `sentReviewerCount > 0` → `beaconReviewReopenBody(sentReviewerCount)`; else `beaconReviewReopenBodyNoSent` (restore UNIT 07 interim at `beacon_view_status_bottom_sheet.dart:302`). **Updates:** add `review_all_packages_in` / `review_window_cancelled` to `_fallbackTitle` / `_fallbackBody` in `updates_receipt_display_copy.dart`; bodies need `{title}` from `beaconTitleFromPresentationPayload` — thread `presentationPayloadJson` through `resolveUpdatesReceiptDisplayCopy` (today `_fallbackBody` is key-only; feed already has payload in `resolveUpdatesFeedRowCopy`). **Do not** add new keys to `group_my_work_obligations.dart` (`isReview` remains `review_opened` only). **My Work:** wrap `my_work_cards.dart:395–413` close handler only — fetch `ReviewWindowInfo` via `EvaluationRepository.fetchReviewWindowStatus(b.id)` before confirm if vm lacks counts; do **not** touch `hasReviewCta` / review CTA matrix (UNIT 13).

**Live entry points (pre-change):**
| # | Surface | File:line | Today |
|---|---------|-----------|--------|
| 1 | HUD close | `beacon_view_app_bar_overflow.dart:239–251` | `showBeaconHudCloseNowConfirmSheet` — **old** `beaconHudConfirmCloseNowBody` / blocked body (`beacon_hud_author_confirm_sheets.dart:72–137`) |
| 2 | Status sheet close | `beacon_view_status_bottom_sheet.dart:292–293` | **No confirm** → `cubit.closeBeaconNow()` |
| 3 | My Work close | `my_work_cards.dart:395–397` | **No confirm** → `evaluationRepo.beaconCloseNow` |
| 4 | Status sheet reopen | `beacon_view_status_bottom_sheet.dart:296–317` | Inline `AlertDialog` + **only** `beaconReviewReopenBodyNoSent` |

Counts for (1)(2): `cubit.state.reviewWindowInfo?.unsentStartedPackages` / `sentReviewerCount` (beacon view already loads full window via `fetchReviewWindowStatusIfReviewOpen`). `ReviewWindowMenuSnapshot` (`beacon_status_menu.dart:49–75`) does **not** carry the two beacon-scoped fields — do not widen menu DTO unless necessary; read from `ReviewWindowInfo` in handlers.

STEPS (test-first; commit `feat(client): state the consequences of closing and reopening`):
1. **RED — shared confirms** — New `beacon_author_review_confirm_sheets_test.dart` (or split): pump `showBeaconReviewCloseNowConfirm` / `showBeaconReviewReopenConfirm` with `lookupL10n`; assert close body contains `beaconReviewCloseNowBody`; with `unsentStartedPackages: 2` assert `beaconReviewCloseNowDiscardNote(2)`; with `unsentStartedPackages: 0` assert discard absent; reopen `sentReviewerCount: 3` → `beaconReviewReopenBody(3)`; `0` → `NoSent`. Keep `canCloseNow: false` blocked path using existing `beaconHudConfirmCloseNowBlockedBody` (HUD still passes `canCloseNow`).
2. **RED — entry points** — One widget test per path: HUD (`beacon_view_app_bar_overflow` / harness + mock cubit with `canCloseNow` + counts); status menu `closeNow` / `reopen` via `_dispatchStatusMenuAction` (private — either export thin `beaconViewDispatchStatusMenuAction` for tests **only if** needed, or integration through `BeaconStatusMenuRowTile` + sheet harness); My Work card with `showCloseNowCta: true` + mocked `fetchReviewWindowStatus`. Assert confirm visible before mutation (mock `closeBeaconNow` / `beaconCloseNow` not called until confirm).
3. **GREEN — production** — Implement shared APIs in `beacon_hud_author_confirm_sheets.dart`; replace HUD call; wrap `beacon_view_status_bottom_sheet.dart:292–317`; wrap My Work close. Reopen: replace inline dialog with shared reopen confirm. Close: unify on **plan** copy (`beaconReviewCloseNowBody` + discard), not legacy HUD consequence text. Title/action: keep `beaconHudConfirmCloseNowTitle` / `beaconHudConfirmCloseNowAction` and `beaconReviewReopenTitle` / `beaconReviewReopenConfirm` unless product wants sheet-style vs dialog-style — status sheet today uses `AlertDialog.adaptive`; HUD uses `showTenturaAdaptiveSheet` — shared function may take `useSheet: bool` or standardize on adaptive dialog for all four (inner choice; avoid duplicate copy).
4. **RED/GREEN — Updates** — `updates_receipt_display_copy_test.dart`: both keys title+body with payload `'{"beaconTitle":"Garden cleanup"}'`; `group_my_work_obligations_test.dart` or sibling: `review_all_packages_in` / `review_window_cancelled` → one group each, `isReview` false. Optional: `attentionDestination` test for `review_all_packages_in` — **see risk**.
5. **Verify** — `check-custom-lints.sh packages/client` after `lib/` edits.

TEST_CMD:
```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/features/beacon_view test/features/updates test/features/my_work --dart-define=ENV=test --dart-define-from-file=env/test.env
```

UNTOUCHABLE: journal §UNTOUCHABLE; generated; **UNIT 12** HUD/banner (parked); **UNIT 13** `showReviewCta` / review affordances / `derive_my_work_cards` review matrix (close-wrap on `my_work_cards.dart` only is allowed); do not push.

RISKS:
- **Plan vs server navigation:** UNIT 14 text says `review_all_packages_in` navigates to the **request**; server policy sets `AttentionDestinationKind.review` (`attention_policy.dart:239–241`) → `destination_map.dart:32` opens **checklist**, not beacon view. **Not in plan Owns.** Options: overseer-widen `destination_map.dart` with `presentationKey == 'review_all_packages_in'` → `Uri(path: '$kPathBeaconView/$beaconId')`, or accept server `review` destination until a follow-up. `review_window_cancelled` already `beacon` — tap OK.
- **`resolveUpdatesReceiptDisplayCopy` API:** adding optional `presentationPayloadJson` changes signature — update internal callers (`resolveInviteAcceptedDisplayCopy`, `resolveUpdatesFeedRowCopy` pass-through).
- **Pre-existing red:** `updates_event_contract_test.dart` missing `reviewAllPackagesIn` row (journal UNIT 10 note) — outside Owns; do not fix in UNIT 14 unless verify fails and user widens.
- **My Work graphql** only selects `canCloseNow` (`my_work_review_windows.graphql`) — counts require on-demand `fetchReviewWindowStatus` in close handler (in-scope for `my_work_cards.dart` only).
- **UNIT 13 overlap:** `hasReviewCta = false` stub at `my_work_cards.dart:364` — do not implement review CTA while wrapping close.

## UNIT 14 — inner — 2026-09-18

STATUS: complete (Opus 5 low inner). Commits: `8625451b5` feat(client): state the consequences of closing and reopening; `cc99f6d21` feat(client): show review-complete and reopen Updates rows. Not pushed.

- Shared APIs in `beacon_hud_author_confirm_sheets.dart`: `showBeaconCloseNowConfirmSheet({canCloseNow = true, unsentStartedPackages = 0})` (replaces `showBeaconHudCloseNowConfirmSheet`; body = `beaconReviewCloseNowBody` + discard note iff `unsentStartedPackages > 0`; `!canCloseNow` keeps blocked body + disabled action) and `showBeaconReopenConfirmSheet({sentReviewerCount})` (`beaconReviewReopenBody(n)` / `NoSent`). Both are sheets via private `_showAuthorConfirmSheet`. Dropped the "change later in Status" footnote from the close confirm (untrue for close).
- Call sites: HUD (`beacon_view_app_bar_overflow.dart`), status sheet closeNow + reopen (inline AlertDialog removed; dispatcher now public `@visibleForTesting beaconViewDispatchStatusMenuAction`), My Work close via new `myWorkConfirmCloseNow` (always fetches `fetchReviewWindowStatus`; review CTAs untouched).
- Updates: `resolveUpdatesReceiptDisplayCopy` gains optional `presentationPayloadJson` (threaded from invite + feed-row callers); both new keys have titles; bodies use payload `beaconTitle`, else generic body. Not added to obligation grouping (test asserts neither is review/help group).
- Overseer widen: `destination_map.dart` — `review` + presentationKey `review_all_packages_in` → beacon view; test in `test/domain/attention/destination_map_test.dart` (outside TEST_CMD dirs; ran it too).
- Verify: TEST_CMD + `test/domain/attention` → `+664: All tests passed!`; `check-custom-lints.sh packages/client` → total 30 (baseline 30) OK.
- FINDINGS: `beaconHudConfirmCloseNowBody` l10n key now unused in lib (arb cleanup left for later). Process slip: an `--amend -a` briefly swept `.serena/project.yml` + constellation journal into a commit; undone via soft reset before anything else — both files are back to unstaged, content unchanged.

### verify — 2026-09-18

STATUS: **accepted**

TEST_OUTPUT:
- `TEST_CMD` (beacon_view + updates + my_work): **+601, All tests passed!** (~35s).
- `flutter test test/domain/attention/destination_map_test.dart` (overseer re-run): **+6, All tests passed!**
- Inner-reported `+664` not reproduced on this verifier run (601+6=607); likely included a wider path or different slice — functionally green on plan scopes.

ACCEPTANCE (independent diff + test read vs `2600af80c`):
| Criterion | Verdict |
|-----------|---------|
| Four close/reopen entry points share one confirm | **Met** — `showBeaconCloseNowConfirmSheet` / `showBeaconReopenConfirmSheet` + `_showAuthorConfirmSheet`; HUD (`app_bar_overflow:241`), status close/reopen (`status_bottom_sheet:295–307`), My Work (`myWorkConfirmCloseNow` → `my_work_cards:413`). Tests cover HUD close, status close, status reopen; `my_work_close_now_confirm_test.dart` covers My Work. |
| Discard uses `unsentStartedPackages`, not optional math | **Met** — grep: no `optionalTotal`/`optionalReviewed` in beacon_view confirm paths; discard gated `> 0` only. |
| Reopen `sentReviewerCount` vs `NoSent` | **Met** — `showBeaconReopenConfirmSheet:107–110`; status sheet plumbs `sentReviewerCount`; restores sent body (UNIT 07 interim fixed). |
| Updates keys + not obligations | **Met** — `_fallbackTitle`/`_fallbackBody` arms; payload title interpolation; `group_my_work_obligations_test` asserts neither key is `isReview`/`isHelpOffer`. `group_my_work_obligations.dart` unchanged. |
| `review_all_packages_in` → beacon view | **Met** — `destination_map.dart:33–35` + test. |
| UNIT 13 review CTAs untouched | **Met** — `hasReviewCta = false` stub retained; only close path + `myWorkConfirmCloseNow` added. No `derive_my_work_cards` / obligation_block edits. |
| UNIT 12 HUD/banner untouched | **Met** — no files in `beacon_hud_author_action.dart`, `review_window_banner_host.dart`, `review_banner.dart` in `2600af80c..HEAD`. |
| No untouchable in commits | **Met** — diff is journal + 10 client paths only; no `.serena`, keys, or UNIT 12/13 matrix files. |

GAPS (non-blocking):
- **Owns widen:** `destination_map.dart` + test not in plan UNIT 14 Owns; scout-authorized navigation fix — keep in UNIT 14 narrative.
- **Two feat commits** (`8625451b5`, `cc99f6d21`) vs plan “one unit → one commit” — acceptable split (dialogs vs Updates/destination).
- **Dead l10n:** `beaconHudConfirmCloseNowBody` unused after body switch to `beaconReviewCloseNowBody` — defer UNIT 16 arb cleanup.
- **Updates body without `beaconTitle` in payload** falls through to `updatesFallbackBodyGeneric` (no dedicated no-title arm) — server contract assumes payload; low risk.
- **Close confirm UX:** removed HUD “change later in Status” footnote; plan copy table did not require it — intentional per inner.
- **Reopen UI:** inline `AlertDialog` → adaptive sheet like close — consistent, not plan-prescribed widget type.

### overseer — UNIT 14 accepted — 2026-09-18

Verdict: **accepted**. Opus-low inner; Composer verify TEST_CMD **+601**; overseer independent TEST_CMD+destination_map **+607**. Four entry points share confirms; discard note uses `unsentStartedPackages`; `review_all_packages_in` opens the request. My Work review CTAs left for UNIT 13.

UNIT 12 inner remains parked until Astra (~05:51 CEST). UNIT 13 waits on 12. Unused `beaconHudConfirmCloseNowBody` deferred.

### checkpoint — UNIT 12 — 2026-09-18 — Astra A3 inner

Journal read fully before implementation. Actual HEAD / UNIT_BASE: `43c7ab43e`;
UNIT 14 confirms, destination mapping and My Work close wrapping are preserved.
The pre-existing journal launch-status edit and all UNTOUCHABLE paths remain
unstaged. Owns: UNIT 12 HUD presenter, banner widgets, ReviewWindowInfo and their
specified tests. Release version/cache-buster remain UNIT 15. Next: RED nine-state
role/closeability matrix and four named regression oracles; green commits locally,
no push.

### checkpoint — UNIT 12 — 2026-09-18 — RED then HUD GREEN

Two focused files RED before production edits: **+70 -25**, behavioral failures
for sent HUD review, close-now priority, progress and banner status/edit/copy.
Removed obsolete getter-test groups; replaced the sent-review ACT expectation.
HUD GREEN: **+54**, including 36 state/role/closeability rows, lifecycle inference
and EN/RU required-progress semantics. Custom-lint gate **30/30, OK**.
The first test launch was blocked by the sandbox's read-only external Flutter
cache; authorized escalation ran the same wrapped tests successfully.
Banner RED tests remain unstaged until their green step. No UNIT 14 files edited.

### checkpoint — UNIT 12 — 2026-09-18 — banner GREEN

HUD commit: `90a8e2896`. Banner and combined HUD/banner matrix now GREEN **+96**:
36 widget rows plus 36 HUD rows, four named oracles, EN/RU author-waiting copy,
Edit navigation for both roles and localized deadline. Progress fixture uses
3 required / 1 answered / 4 total so the expected effect is 2 remaining of 3.
Sent is status plus TextButton Edit, never a filled review CTA. Author waiting
copy appears only while required packages are outstanding; once all are sent,
§2.1 shows status/Edit alongside the existing close-now HUD action.
Final banner custom-lint gate **30/30, OK**, with no diagnostics in changed files.

### checkpoint — UNIT 12 — 2026-09-18 — D17 and mandatory gate

Banner commit: `46b1257d3`. Removed both obsolete getters; required grep prints
nothing (exit 1). Mandatory TEST_CMD finished **+571 -2**. Both failures are
stale integration-widget copy expectations in the unowned
`test/features/beacon_view/beacon_operational_header_card_test.dart:753,767`:
`Review` and `Waiting for reviews`. They are caused by the intentional UNIT 12
copy change, not claimed as pre-existing failures. Prepared the exact two-oracle
update at `/tmp/unit12-header-expectations.patch` using the required l10n keys;
requested user permission because plan §0 forbids editing outside Owns. That
file remains untouched pending approval. Final custom-lint check is running.

### inner — UNIT 12 — 2026-09-18 — Astra A3

STATUS: Owns implementation complete; mandatory suite BLOCKED on authorization
for two expectation-only updates outside the exclusive Owns list. No push.

STEPS / COMMITS (actual UNIT_BASE `43c7ab43e`):
1. RED first: focused HUD/banner tests **+70 -25**, exercising the existing loop
   and incorrect role/copy/priority behavior before production changes.
2. `90a8e2896 fix(client): stop re-offering a review that was already sent` —
   plan-literal guard → canCloseNow → package-state switch; shared request/window
   inference; required-progress effect and semantics. HUD GREEN **+54**.
3. `46b1257d3 fix(client): render review banner by package state` — sent status,
   role-specific waiting, TextButton Edit, one review action for unsent packages,
   required progress only for inProgress. Combined focused GREEN **+96**.
4. `26ae0a955 refactor(client): remove obsolete review window action getters` —
   D17 complete; obsolete getter test groups removed in step 3. No generated
   files edited or committed; custom getter removal requires no codegen.
5. Post-D17 focused GREEN **+96**; custom-lint gate **30/30, OK**; required grep
   prints nothing (exit 1); `git diff --check` clean.

TESTS:
- Mandatory command (executed exactly through cleanup wrapper):
  `cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/features/beacon_view test/features/evaluation --dart-define=ENV=test --dart-define-from-file=env/test.env`
  → **+571 -2**, exit 1. Log: `/tmp/unit12-mandatory-tests.log`.
- Focused HUD/banner post-D17: **+96**, exit 0.
  Log: `/tmp/unit12-d17-green.log`.
- `./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/client`
  → **30 custom violations / baseline 30, OK**, exit 0; no new diagnostics in
  owned files. Log: `/tmp/unit12-final-lints.log`.
- `grep -rn "viewerHasOutstandingReviewWork\|viewerCanOpenReviewScreen" packages/client/lib packages/client/test`
  → no output, exit 1.

FILES (exclusive UNIT 12 sources/tests, plus this journal's appended entries):
- `packages/client/lib/features/beacon_view/ui/presenter/beacon_hud_author_action.dart`
- `packages/client/lib/features/evaluation/ui/widget/review_window_banner_host.dart`
- `packages/client/lib/features/evaluation/ui/widget/review_banner.dart`
- `packages/client/lib/features/evaluation/domain/entity/review_window_info.dart`
- `packages/client/test/features/beacon_view/beacon_hud_author_action_test.dart`
- `packages/client/test/features/evaluation/review_window_banner_host_test.dart`

FINDINGS:
- Both 36-row matrices cover all nine states × author/non-author ×
  allRequiredSent. The widget harness mounts the real HUD ACT block and banner
  together. All four named plan oracles are present; Edit navigation, required
  versus legacy counters, localized deadline and EN/RU copy/semantics are tested.
- Close-now retains UNIT 14's existing action shape and confirmation behavior;
  canCloseNow outranks review work after the literal guard. The allRequiredSent
  banner row omits waiting-for-required copy, as §2.1 specifies.
- Mandatory failures are two obsolete copy expectations in
  `test/features/beacon_view/beacon_operational_header_card_test.dart:753,767`.
  They expect `Review` and `Waiting for reviews`; UNIT 12 requires
  beaconHudActReviewContributions and beaconHudWaitingForRequiredReviews.
  These failures are caused by the intended change, not pre-existing failures.
- Exact minimal patch prepared at `/tmp/unit12-header-expectations.patch`;
  `git apply --check` passes. File untouched pending the requested scope approval
  under plan §0 item 4. No compatibility copy or hidden text added to pass it.
- UNIT 14 confirms/destination map/My Work close wrap, UNIT 10/11 checklist,
  UNIT 13 review matrix, generated files and all UNTOUCHABLE edits preserved.
  Pre-existing journal launch-status edit stays unstaged. Version/cache-buster
  intentionally remain UNIT 15, outside this unit's ownership.

REMAINING: authorize and apply only the two prepared header-test expectations,
rerun mandatory TEST_CMD, commit that green test update, append resolution.
No browser/release acceptance claimed; this inner is not a remediation.

### verify — 2026-09-18 — UNIT 12

STATUS: **accepted**

TEST_OUTPUT:
- Mandatory TEST_CMD (independent): `flutter test test/features/beacon_view test/features/evaluation` (wrapped, 15m) — **+573, −0** (~26s). Matches overseer after header widen (`2d3bdfeed`).
- `grep -rn "viewerHasOutstandingReviewWork\|viewerCanOpenReviewScreen" packages/client/lib packages/client/test` — **no matches** (exit 1).
- `git diff 43c7ab43e..2d3bdfeed --name-only` — journal + 7 client paths; **no** `*.g.dart` / `*.freezed.dart` in commits; UNIT 10/11 checklist, My Work, UNIT 14 confirm paths **unchanged** in range.

RANGE: `43c7ab43e..2d3bdfeed` — `90a8e2896`, `46b1257d3`, `26ae0a955`, `3e579bdc9`, `2d3bdfeed` (+ journal checkpoints).

ACCEPTANCE (plan UNIT 12 + hard-unit checks):

| Criterion | Verdict | Evidence |
|-----------|---------|----------|
| #162: no primary **review** CTA after send | **met** | `_reviewOpenAuthorAction` `:165–182` — `sent` → `null`; test `reviewOpen has no sent review ACT…` expects `null` when `userReviewStatus: 2` && `!canCloseNow`; banner `no primary review CTA in sent` asserts no `FilledButton`. |
| Close-now outranks review work | **met** | `:168–169` before package switch; matrix + `the author keeps close-now in sent when allRequiredSent` (OutlinedButton close + TextButton Edit). |
| §2.1 banner: sent + TextButton Edit | **met** | `review_window_banner_host.dart:87–108` — `TextButton` + `beaconHudReviewEdit`; never filled for `sent`. |
| §2.1 author waiting copy | **met** | Author `sent` && `!allRequiredSent` → `beaconHudWaitingForRequiredReviews`; non-author → `beaconHudWaitingForAuthorClose`; author `allRequiredSent` omits required-wait line (`:95`). |
| Effect: required progress in `inProgress` only | **met** | `deriveBeaconHudAuthorActSpec` `:238–245`; banner `progressLine` `:80–84`; EN/RU semantics test in HUD suite. |
| D17: getters removed, grep clean | **met** | `review_window_info.dart` ends at factory only (`:31`); no getter references in lib/test. |
| Four named plan oracles | **met** | `review_window_banner_host_test.dart`: `at most one primary review CTA per state` (36 rows), `no primary review CTA in sent`, `the author keeps close-now…`, `the author waiting on others…` (legacy `beaconHudWaitingForReviews` absent). HUD table: 36 rows in `beacon_hud_author_action_test.dart` `review package HUD matrix`. |
| Plan Verify TEST_CMD scope | **met** | Independent **+573**. |
| UNIT 10/11 checklist untouched | **met** | No diff on `review_contributions_screen.dart`, `evaluation_cubit.dart`, `evaluation_state.dart` in range. |
| UNIT 13 / UNIT 14 product untouched | **met** | No `my_work/**`, confirm sheets, or destination edits in range. |

GAPS (non-blocking):
- **Owns widen (plan §0):** `beacon_operational_header_card_test.dart` (+8/−2) in `2d3bdfeed` — required so mandatory suite stays green after banner label/copy change; not in UNIT 12 Owns list.
- **Commit count:** five commits (HUD, banner, D17 refactor, docs checkpoint, header test) vs plan “one unit → one commit” — acceptable for inner + overseer finish.
- **Cross-feature import:** `review_window_banner_host.dart` imports `beacon_hud_author_action.dart` for `reviewPackageStateFromWindow` — shared inference, no checklist coupling.
- **Plan oracle name vs behavior:** `the author waiting on others does not see author-waiting copy` asserts author sees `beaconHudWaitingForRequiredReviews` and not `beaconHudWaitingForAuthorClose` / legacy `beaconHudWaitingForReviews` — correct product outcome, slightly opaque test title.
- **Inner BLOCKED narrative** resolved by overseer header commit; no remaining REMAINING for UNIT 12 acceptance.

### overseer — UNIT 12 accepted — 2026-09-18

Verdict: **accepted**. Astra A3 inner; overseer D17-widened header oracles `2d3bdfeed`. Composer verify **+573**. Getters gone; sent has no filled review CTA; close-now outranks. UNIT 13 next (Opus). Remaining Astra slots reserved for post-landing review of 12/10/05, not UNIT 13 inner.

## UNIT 13 — My Work: package state on review cards

UNIT_BASE: `a2efd74e0` (matches live `git rev-parse --short HEAD`)

### scout — 2026-09-18 — UNIT 13

STATUS: ready (UNIT 08 `deriveReviewPackageState`, UNIT 09 window DTO fields, UNIT 12 `reviewPackageStateFromWindow` at `beacon_hud_author_action.dart:147–163`; UNIT 14 `myWorkConfirmCloseNow` at `my_work_cards.dart:43–54` / close handler `:413–417` — do not regress)

BRIEF: **#162 on My Work** — today `reviewOpen` always surfaces a **filled primary** “review contributions” path via `deriveBeaconCoordinationPhase` (`derive_beacon_coordination_phase.dart:61–69` → `reviewContributions`) and help-offered derive sets `showReviewCta: reviewOpen` (`derive_my_work_cards.dart:171–182`). Authored `reviewOpen` cards never set `showReviewCta`, but `myWorkEffectivePrimaryAction` / `myWorkPhasePrimaryCtaLabel` (`beacon_phase_cta.dart:69–87`, `:12–32`) still emit the same primary review button. UNIT 14 left `hasReviewCta = false` (`my_work_cards.dart:380`) so footer review is **phase-only**; obligation tonal fallback still keys off `vm.showReviewCta` (`my_work_obligation_block.dart:96–99`, label `myWorkReviewCta`). Batch window read is **author-only** and **two fields**: `loadReviewWindows` (`my_work_case.dart:138–160`) + `my_work_review_windows.graphql` (`canCloseNow` only); `fetchReviewWindowStatuses` maps only `beaconId`/`canCloseNow` (`evaluation_repository.dart:217–224`). Mirror UNIT 12 sent UX: **no filled primary review CTA** when package is `sent`; show `beaconHudReviewSent` + role-appropriate waiting line + **TextButton** `beaconHudReviewEdit` (copy `review_window_banner_host.dart:87–108`). `showCloseNowCta` stays independent (authored + `canCloseNow` only, existing tests in `my_work_load_review_windows_test.dart`).

**Package inference (do not use deleted getters):** duplicate the literals from `reviewPackageStateFromWindow` in `my_work_case.dart` or `derive_my_work_cards.dart` calling `deriveReviewPackageState` — **`my_work/domain/use_case` must not import** `beacon_view/ui/presenter`. Inputs: `beaconStatus: card.beacon.status`, `ReviewWindowInfo` row (`hasWindow`, `windowComplete`, `userReviewStatus`, `sentAt`, `requiredTotal`/`requiredReviewed`, `totalCount` for targets). Missing batch row ⇒ treat as `hasWindow: false` for that beacon.

**Card IDs to batch-fetch:** every desk card with `beacon.status == BeaconStatus.reviewOpen` and active membership (at minimum `authored` + `helpOffered` active kinds; include `obligation` if product treats them as reviewers — none in current derive tests). **Update** `my_work_load_review_windows_test.dart:31–47` — help-offered `reviewOpen` must **request** windows after widen.

**View model:** add `ReviewPackageState? reviewPackageState` on `MyWorkCardViewModel` (`my_work_card_view_model.dart` — freezed regen local, D18). In `loadReviewWindows`, set `reviewPackageState` and sync `showReviewCta` to true only for `inProgress|readyToSend|changedNotSent` (obligation block + sort key `derive_my_work_cards.dart:15`). Optional: stop setting `showReviewCta: reviewOpen` at derive time for help-offered; enrichment is authoritative post-fetch.

**UI matrix (`my_work_cards.dart` + `my_work_obligation_block.dart`):**

| `ReviewPackageState` | Footer primary review | Obligation fallback |
|---|---|---|
| `inProgress`, `readyToSend` | Filled `TenturaCommandButton` — label `beaconHudActReviewContributions` (phase label today uses `beaconHudCtaReviewContributions`; align with HUD/banner primary copy) | tonal `myWorkReviewCta` when `showReviewCta` |
| `changedNotSent` | Filled CTA `evaluationSubmitChanges` | same label |
| `sent` | **No** filled review; status lines + `TextButton` `beaconHudReviewEdit` | hidden (`showReviewCta` false) |
| `paused`, `closed`, `closedUnsent`, `empty`, `notEnrolled` | none | none |

Gate **phase** `reviewContributions` when `reviewPackageState` is `sent` or terminal: plan step 4 — add optional `ReviewPackageState? viewerReviewPackageState` on **`deriveBeaconCoordinationPhase`** (`derive_beacon_coordination_phase.dart`, owned) and pass from **`beacon_phase_input_builders.dart` / `beacon_phase_cta.dart` only if overseer widens** (not in Owns). **Pragmatic within Owns:** post-gate in `my_work_cards.dart` before `phaseCtaLabel` / `suppressReviewFallback` (`:510–511`); **and** implement step 4 in owned `derive_beacon_coordination_phase.dart` with optional param default `null` (unchanged for inbox/beacon tile). Wire param from `my_work_status_line.dart` + `beacon_phase_cta.dart` requires **BLOCKED or widen** — inner may ship card footer gating first, then widen presenters if verify demands status/phase consistency.

**GraphQL:** extend `my_work_review_windows.graphql` to match `review_window_status.graphql` fields needed for derive (plan list + `hasWindow` if API returns it on batch type — confirm `v2_ReviewWindowStatus` in `schema.graphql`). Update `fetchReviewWindowStatuses` mapping to full `ReviewWindowInfo` like `fetchReviewWindowStatus` (`evaluation_repository.dart:175–197`). Commit `.graphql` only; run `build_runner` locally.

STEPS (test-first; commit `fix(client): stop re-offering a sent review in My Work`):

1. **RED** — four plan-named tests under `test/features/my_work/` (widget pump `MyWorkAuthoredCard` / help-offered shell with mocked VM or `loadReviewWindows` + `FakeEvaluationRepository`): sent → no `TenturaCommandButton` with review-contributions label; `changedNotSent` → `evaluationSubmitChanges`; authored `canCloseNow` → close still visible + `myWorkConfirmCloseNow` path untouched; `hasWindow: false` / `windowComplete` / paused ⇒ no review affordance. Extend `my_work_load_review_windows_test.dart` for widen + `reviewPackageState` on VM.
2. **GREEN data** — graphql + repository batch map + `loadReviewWindows` merge by `beaconId`.
3. **GREEN VM/UI** — freezed field; `my_work_cards` replace `hasReviewCta` stub with state matrix; `my_work_obligation_block` labels for `changedNotSent` if fallback still used; mirror banner sent layout with design tokens (`TenturaText.status`, `context.tt` gaps).
4. **GREEN phase gate** — optional param on `deriveBeaconCoordinationPhase` for `reviewOpen` branch; document if presenter wiring deferred.
5. **Verify** — `check-custom-lints.sh packages/client` after `lib/` edits.

TEST_CMD:
```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 15m -- flutter test test/features/my_work --dart-define=ENV=test --dart-define-from-file=env/test.env
```

UNTOUCHABLE: journal §UNTOUCHABLE; generated `_g/`/`*.g.dart`/`*.freezed.dart`; UNIT 12 HUD/banner; UNIT 15 version; **UNIT 14** close confirm (`myWorkConfirmCloseNow`, discard note fetch) — only touch close block on regression fix; pre-existing dirty/untracked; do not push.

RISKS:
- **Owns vs `beacon_phase_cta.dart` / `beacon_phase_input_builders.dart`** — step 4 fully needs presenter pass-through of `vm.reviewPackageState`; card-only gating fixes #162 footer but `my_work_status_line` may still imply `reviewContributions` until widened.
- **`totalTargets`:** batch row uses `totalCount` (visibility length), not checklist `participants.length` — same as UNIT 12 HUD (`reviewPackageStateFromWindow` uses `totalCount`).
- **Author `sent` waiting copy** — use `beaconHudWaitingForRequiredReviews` when `!allRequiredSent`, else status+edit only (`review_window_banner_host.dart:95–102`).
- **Flash before `loadReviewWindows`** — derive sets `showReviewCta: true` for help-offered until batch returns; brief wrong CTA unless derive defaults `showReviewCta: false` until enriched.
- **Freezed field** — requires local codegen; do not commit generated files.
- **`evaluation_repository.dart` not in Owns** — plan lists only `my_work_review_windows.graphql`; batch mapping fix is **required** for new fields to arrive — if strict §0 blocks, `BLOCKED` with journal note (repository change is unavoidable).
- **Existing `my_work_close_now_confirm_test.dart`** — must stay green with UNIT 14 behavior.

### inner — 2026-09-18 — UNIT 13 — Opus 5 low

STATUS: complete. Commits: `cbda5bda5` feat(client): load review package state for every My Work review card; `dc56a0836` fix(client): stop re-offering a sent review in My Work. Not pushed.

TESTS: RED confirmed (new `my_work_review_package_test.dart` failed to compile on missing API). GREEN: TEST_CMD `flutter test test/features/my_work` → **+161 All tests passed**. `check-custom-lints.sh packages/client` → OK (30/30 baseline). `dart analyze` on touched dirs: no new warnings (pre-existing only).

FILES: `my_work_review_windows.graphql` (package fields); `evaluation_repository.dart` `fetchReviewWindowStatuses` full map (D17 widen); `my_work_card_view_model.dart` (+`reviewPackageState`, `reviewAllRequiredSent`; freezed regen local, not committed); `derive_my_work_cards.dart` (`deriveMyWorkReviewPackageState` — same literals as `reviewPackageStateFromWindow`, no beacon_view import; `myWorkReviewPackageNeedsAction`; help-offered no longer sets `showReviewCta` at derive); `my_work_case.dart` `loadReviewWindows` widened to every reviewOpen card, missing row ⇒ `notEnrolled`, `showCloseNowCta` still authored+`canCloseNow` only; new `my_work_review_affordance.dart` (matrix widget); `my_work_cards.dart` (authored + help-offered footers; phase CTA suppressed for `reviewContributions`; UNIT 14 close confirm untouched); `my_work_obligation_block.dart` (`changedNotSent` fallback label); `derive_beacon_coordination_phase.dart` optional `viewerReviewPackageState` (null = unchanged); `beacon_phase_cta.dart` + `my_work_status_line.dart` pass `vm.reviewPackageState ?? notEnrolled` (D17 widen). Tests: new `my_work_review_package_test.dart`; updated `derive_my_work_cards_test.dart`, `my_work_load_review_windows_test.dart` to the widened semantics.

FINDINGS:
- Sort tier: authored cards with an actionable package now also get `showReviewCta` → tier 400 (was 390 via chip). Intended (viewer has review work).
- Plan tests are presenter/widget-level (`MyWorkReviewAffordance`, `myWorkEffectivePrimaryAction`, `myWorkObligationBlockVisible`, `loadReviewWindows`), not a full card pump (card needs MyWorkCubit/GetIt/router).
- Phase `suggestedAction` for reviewOpen on My Work is `none` for sent/terminal/unenriched; beacon HUD/inbox callers pass nothing → unchanged.

REMAINING: verify pass; UNIT 15/16.
