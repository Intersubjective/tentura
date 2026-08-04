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
feed/badge stack (#80) are intact. The defect is **missing producers** — 24 of 34 coordination-item
`*_case.dart` files never build an `AttentionDispatchIntent`, including `accept_ask_case.dart`,
which is the exact reported scenario. U1 refined this against the live tree: 10 of those 24 are
legitimately silent (9 draft-lifecycle + 1 query-only), leaving **14 real gaps** — 7 in U2, 7 in U3. Secondary defects: no atomic mutation+receipt transaction on those cases,
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
| U1 | Event coverage contract + guard test (no behavior change) | complete | **accepted by overseer** |
| U2 | Emit accept / resolve / redirect / cancel events (the #102 core) | complete | — |
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

### 2026-08-05 — U2 worker — Step 1 (event types + policy)

COMMITS: 0b24a35b feat(#102-U2): add commitment event types, kinds, and attention policy
TESTS: `dart analyze` — 0 errors (1871 pre-existing info/warnings)

### 2026-08-05 — U2 worker — Step 2 (recipient resolver)

COMMITS: d6ff8c30 feat(#102-U2): resolve commitment notification recipients
TESTS: `dart test test/domain/notification/beacon_notification_recipient_resolver_test.dart` — 11 passed

### 2026-08-05 — U2 worker — Step 3 (intent builder)

COMMITS: 5262111a feat(#102-U2): add commitmentChanged attention intent builder
TESTS: `dart test test/domain/attention/attention_intent_case_test.dart --name commitmentChanged` — 2 passed

### 2026-08-05 — U2 worker — Step 4 (accept cases)

COMMITS: 72e7539a feat(#102-U2): emit commitmentAccepted on ask/promise accept

### 2026-08-05 — U2 worker — Step 5 (resolve cases)

COMMITS: 27adc35c feat(#102-U2): emit commitmentResolved on ask/promise resolve

### 2026-08-05 — U2 worker — Step 6 (redirect cases)

COMMITS: db7d487d feat(#102-U2): emit redirect commitment events for ask/promise

### 2026-08-05 — U2 worker — Step 7 (cancel case)

COMMITS: 54e219e6 feat(#102-U2): emit commitmentCancelled on ask cancel

### 2026-08-05 — U2 worker — Step 8 (contract + pg tests)

COMMITS: 08286c2a test(#102-U2): contract coverage and commitment attention pg tests
TESTS:
- `dart run build_runner build -d` — OK
- `dart analyze` — 0 errors
- `dart test --exclude-tags pg` — 1165 passed (baseline 1151 + 14 new)
- `dart test --tags pg test/domain/use_case/coordination_item/commitment_attention_pg_test.dart` — 2 passed (local Postgres reachable)
- `bash scripts/check-custom-lints.sh packages/server` — OK (baseline 0)
- `dart test test/architecture/updates_event_coverage_test.dart` — pass

FINDING: Verified m0121 `attention_occurrence.event_type` and m0096 `notification_outbox.kind` are unconstrained `text` — no migration required, matching plan §4.
FINDING: `commitmentCancelled` policy table lists `coordinationChurn` preference class, but `AttentionPolicy` only persists `inAppPreferenceClass` when suppression is `noisy`; with `standard` suppression the field stays null (existing policy behavior, not changed).
FINDING: Cancel recipient extras (`acceptedById`, creator when actor ≠ creator) pass through `BeaconNotificationIntent.admittedUserIds` / `moderatorUserIds` to avoid extending the freezed intent shape.

### 2026-08-05 — U2 worker — final

STATUS: complete
COMMITS: 0b24a35b, d6ff8c30, 5262111a, 72e7539a, 27adc35c, db7d487d, 54e219e6, 08286c2a (subjects per step checkpoints above)
TESTS: see Step 8 checkpoint
FILES: packages/server/lib/domain/attention/attention_models.dart, attention_policy.dart, packages/server/lib/domain/entity/notification_kind.dart, notification_category.dart, packages/server/lib/domain/notification/beacon_notification_recipient_resolver.dart, beacon_notification_copy_builder.dart, packages/server/lib/domain/use_case/attention_intent_case.dart, packages/server/lib/domain/use_case/coordination_item/{accept_ask,accept_promise,resolve_ask,resolve_promise,redirect_ask,redirect_promise,cancel_ask}_case.dart, docs/contracts/updates-event-contract.json, packages/server/test/domain/notification/beacon_notification_recipient_resolver_test.dart, packages/server/test/domain/attention/attention_intent_case_test.dart, packages/server/test/domain/use_case/coordination_item/{ask_lifecycle_case,accept_promise_case,resolve_promise_case,redirect_promise_case,commitment_attention_pg}_test.dart, packages/server/test/architecture/transactional_attention_producer_inventory_test.dart, docs/plans/updates-consistency-issue-102-journal.md
FINDINGS: see step checkpoints; repository matches plan on schema (no migration). Redirect emits two events (`redirected_to` + `redirected_from`) in one transaction.
REMAINING: none for U2; U3 still has 7 `#102-U3` gap rows; U4 needs copy for the four new kinds.

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

### 2026-08-05 — overseer — U1 manager review: ACCEPTED

Independently verified rather than accepting the worker's report:

- `dart analyze` in `packages/server`: **0 errors** (exit 2 is pre-existing warnings/info only).
- `dart test --exclude-tags pg`: **1151 passed**.
- `dart test test/architecture/updates_event_coverage_test.dart`: passes.
- **Guard bite re-proved by the overseer**, not just the worker: added
  `coordination_item/zz_overseer_probe_case.dart`, the coverage test went **red**; removed it, green
  again. Worktree left clean.
- Contract cross-checked against an independent classification made before the worker ran: 34 of 34
  `*_case.dart` files covered exactly once, 45 producers, 7 `#102-U2` gaps + 7 `#102-U3` gaps, 10
  emitting coordination cases. Matches exactly.
- The two pre-existing `updates_event_contract_test.dart` files were only widened (new top-level key,
  schema version bump) — no assertion was weakened or deleted.
- Pre-existing untracked files all still present and unstaged. Nothing pushed.

Overseer corrections applied on top: plan §1 and this journal's root-cause paragraph said
"35 cases / 25 silent"; the live tree has **34** `*_case.dart` files (the 35th,
`coordination_room_access.dart`, is an access helper). Corrected in both documents. The worker had
independently caught and fixed the related "13 vs 7" gap-count error in 40c4e790.

Releasing U2.
