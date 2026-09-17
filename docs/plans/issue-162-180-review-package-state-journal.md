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
- [ ] UNIT 02 m0176 `sent_at` + context — hard (many hops, PG) — Opus inner
- [ ] UNIT 03 optional targets / counters — hard (D6/D7) — Opus inner; Astra review later
- [ ] UNIT 04 GraphQL + client schema — routine — Opus inner
- [ ] UNIT 05 author nudge — hard (races, idempotency) — **ASTRA inner**
- [ ] UNIT 06 reopen announces — hard (tx order) — Opus inner
- [ ] UNIT 07 l10n keys — routine — Opus inner
- [ ] UNIT 08 `ReviewPackageState` — routine — Opus inner
- [ ] UNIT 09 client data/role/context — hard (DTO hops, codegen) — Opus inner
- [ ] UNIT 10 checklist UI — hard (Flutter, #162) — **ASTRA inner**
- [ ] UNIT 11 paused/closed classify — hard (D12) — Opus inner
- [ ] UNIT 12 HUD + banner — hard (#162 loop) — **ASTRA inner**
- [ ] UNIT 13 My Work cards — hard — Opus inner
- [ ] UNIT 14 author dialogs + Updates — medium — Opus inner
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

### manager — UNIT 01 accepted — 2026-09-18T00:24:00+02:00

Overseer independently re-ran `evaluation_case_test.dart --exclude-tags pg` → `+74 All tests passed!` (4.2s). Grep empty. Production diff is a 59-line delete of the auto-close tail + `_autoCloseReviewWindow`; `closeNow` / `_canCloseNow` / `closeAndFinalize` untouched. Untouchables preserved. Tests-folded-into-fix is a process miss, not a product miss — red was recorded before the delete.

---

## UNIT 02 — in progress

UNIT_BASE: `e136ba450`
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
