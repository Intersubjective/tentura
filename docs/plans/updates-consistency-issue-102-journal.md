# Updates Consistency (#102) — Implementation Journal

Shared coordination state for the overseer and every Cursor worker on this plan.
**Read this entire file before inspecting or editing anything.** Reread it before any
cross-unit decision. Append a checkpoint after meaningful progress or an unexpected finding,
and a final entry before exit.

---

## Objective

Close [issue #102](https://github.com/Intersubjective/tentura/issues/102): make Updates complete,
prompt and consistent across open screens.

**Plan source:** `docs/plans/updates-consistency-issue-102-plan.md` (read the whole thing; it
contains the live-code diagnosis, the decisions that must not be re-litigated in §4, the unit
definitions in §5, and the boundaries in §7).

**Root cause established before execution:** the realtime transport (#73) and the attention
feed/badge stack (#80) are intact. The defect is **missing producers** — 25 of 35 coordination-item
use cases never build an `AttentionDispatchIntent`, including `accept_ask_case.dart`, which is the
exact reported scenario. Secondary defects: no atomic mutation+receipt transaction on those cases,
unguarded empty-copy rendering in `_UpdatesCard`, and no creation-to-render latency instrumentation.

---

## Repository state at start

- Repo: `/home/vader/MY_SRC/tentura`
- Branch: `feat/updates-consistency-102` (created off `main`)
- Starting HEAD: `7323a3893ce3ea94965014701dfc1ef9146b8cca` ("Journal: record the post-close-out end-to-end wiring test")
- Schema tip: `m0138`; next free migration number `m0139` (**no migration is expected for this plan**)
- Tooling gate: `cursor-agent 2026.07.23-e383d2b`, non-fast `composer-2.5` present

### Pre-existing untracked files — DO NOT touch, stage, move, or delete

```
dart-defines
docs/plans/graph-navigation-implementation-guide.md
docs/plans/graph-navigation-rework-plan.md
graph-ego-neighbors-layout-issue.md
key.fb            <- key material: never read, print, or commit
out.key           <- key material: never read, print, or commit
product_testing_compact_buglist.md
product_testing_detailed_report.md
```

Orchestrator-owned files on this branch: the plan and this journal.

---

## Unit checklist

| Unit | Scope | Status | Verdict |
|---|---|---|---|
| U1 | Event coverage contract + guard test (no behavior change) | complete | pass |
| U2 | Emit accept / resolve / redirect / cancel events (the #102 core) | pending | — |
| U3 | Emit remaining silent transitions + `accept_resolution` transaction fix | pending | — |
| U4 | Copy completeness + no-empty-card invariant | pending | — |
| U5 | Latency budget + instrumentation + visible refresh failure | pending | — |
| U6 | Multi-client My Work regression + reconnect dedup | pending | — |
| U7 | Cross-surface consistency verification | pending | — |
| U8 | Integration and close-out | pending | — |

Scope decision (user, 2026-08-05): **full scope U1–U8**, U3 included.

---

## Verification commands

```bash
cd packages/server && dart analyze && dart test --exclude-tags pg
cd packages/server && dart test --tags pg               # needs local Postgres
cd packages/client && flutter analyze && flutter test
bash scripts/check-custom-lints.sh packages/client      # baseline 115 — must not grow
bash scripts/check-custom-lints.sh packages/server      # baseline 0
bash scripts/check-user-facing-terminology.sh
```

After any Injectable/DI change: `cd packages/server && dart run build_runner build -d`.
Never hand-edit `*.g.dart`, `*.freezed.dart`, `di.config.dart`.

Do **not** use `flutter analyze` to check `tentura_lints` rules — it does not load analyzer plugins
and always reports them clean. Use `scripts/check-custom-lints.sh`.

---

## Unresolved decisions and blockers

- None open. §4 of the plan records the four decisions already taken (new `AttentionEventType`
  members over collapsing `coordinationChanged`; source-event-key scheme; per-transition collapse
  policy; transactional boundary). Workers must not re-open them — report disagreement in this
  journal instead.

---

## Checkpoints

<!-- Append below. Newest last. Each worker: STATUS / COMMITS / TESTS / FILES / FINDINGS / REMAINING -->

### 2026-08-05 — U1 worker — Step A (contract schema v2 + producers seed)

Extended `docs/contracts/updates-event-contract.json` to `schemaVersion: 2` with a `producers`
array (45 entries: 34 `coordination_item/*_case.dart` plus 11 beacon/room/evaluation/forward/
invitation/auth producers). `eventTypes` unchanged. Silent gaps tagged `#102-U2` (7 cases) and
`#102-U3` (7 cases); draft and query-only cases use `silentReason`. Updated server and client
`updates_event_contract_test.dart` to accept schema v2 and the new top-level key.

FINDING: `coordination_case.dart`, `beacon_room_case.dart`, `help_offer_case.dart`, and
`evaluation_case.dart` each emit multiple `AttentionEventType` values across methods; the one-row-
per-file `producers` shape records the primary event from `eventTypes` only (same limitation as the
existing `eventTypes.producer` pipe notation).

TESTS: `cd packages/server && dart test test/architecture/updates_event_contract_test.dart` — pass.

### 2026-08-05 — U1 worker — Step B (coverage guard test)

Added `packages/server/test/architecture/updates_event_coverage_test.dart`: enumerates
`coordination_item/*_case.dart`, asserts one `producers` row per file, validates non-silent
`eventType` members and `coveringTest` paths, and requires `silentReason` or `gap` on silent rows.

Scratch verification: temporary `zz_scratch_case.dart` made the guard fail with the undeclared-file
message; removed before commit.

COMMITS: ca95bbf2 test(#102-U1): guard coordination-item attention producer coverage

TESTS:
- `dart test test/architecture/updates_event_coverage_test.dart` — pass (after scratch removed)
- `dart test --exclude-tags pg` — 1151 passed
- `dart test test/architecture/` — 16 passed
- `bash scripts/check-custom-lints.sh packages/server` — pass (baseline 0)
- `dart analyze` — 1869 pre-existing warnings/info, 0 errors (exit code 2 from warning count)

### 2026-08-05 — U1 worker — final

STATUS: complete
COMMITS: d851e0d7 docs(#102-U1): seed updates event producer contract at schema v2; ca95bbf2 test(#102-U1): guard coordination-item attention producer coverage
TESTS: see Step B checkpoint
FILES: docs/contracts/updates-event-contract.json, packages/server/test/architecture/updates_event_coverage_test.dart, packages/server/test/architecture/updates_event_contract_test.dart, packages/client/test/architecture/updates_event_contract_test.dart, docs/plans/updates-consistency-issue-102-journal.md
FINDINGS: Plan counted 35 coordination-item use cases; live tree has 34 `*_case.dart` files plus `coordination_room_access.dart` (helper, not a case). Multi-event use-case files (`coordination_case`, `beacon_room_case`, `help_offer_case`, `evaluation_case`, auth/invite paths) are one producer row per file with the primary `eventTypes` event. `coordination_responsibility_case.dart` is query-only — silent with `silentReason`, not a mutation gap.
REMAINING: none for U1; U2 should flip `#102-U2` gap rows to emitting producers.

### 2026-08-05 — overseer — plan and journal initialized

Branch created, plan committed, unit manifest above is the authoritative order. Launching U1.
