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
| U2 | Emit accept / resolve / redirect / cancel events (the #102 core) | complete | **accepted by overseer** |
| U3 | Emit remaining silent transitions + `accept_resolution` transaction fix | complete | **accepted by overseer** |
| U4 | Copy completeness + no-empty-card invariant | complete | **accepted after remediation** |
| U5 | Latency budget + instrumentation + visible refresh failure | complete | — |
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

### 2026-08-05 — overseer — U2 manager review: ACCEPTED

Verified independently, not from the worker's report.

**Correctness of the core fix.** The failure mode this unit had to avoid is a receipt that is created
but addressed to nobody: `beacon_notification_recipient_resolver.dart` dispatches on
`NotificationKind` with a `switch` *statement*, so Dart does not enforce exhaustiveness, and its
`add()` helper silently drops the actor (`if (userId.isEmpty || userId == actor) return;`). For an
accept, the item's assignee **is** the actor. Confirmed all four new kinds have explicit resolver
cases with tests asserting non-empty recipient sets, and that every wired case notifies the
counterpart rather than the actor:
- accept_ask / accept_promise → `targetPersonId: updated.creatorId` (correct; the creator is the
  author sitting on My Work in the #102 report)
- resolve_ask / resolve_promise → `_counterpart()`: actor==creator ? targetPersonId : creatorId
- redirect_ask / redirect_promise → two records, `redirected_to` (new target, high priority) and
  `redirected_from` (previous target, guarded on existence and difference), distinct source keys
- cancel_ask → target + acceptor + creator

All seven wrap their mutation in `TransactionalAttentionCase.runAction` and derive `sourceEventKey`
from the **post-mutation** record's `updatedAt`, which is what makes replay idempotency work.
Policy table matches the prescription in all seven exhaustive switches plus `categoryOf`.

**Verification run by the overseer:**
- `dart analyze` — **0 errors**
- `dart test --exclude-tags pg` — **1165 passed** (was 1151 at U1; +14 new)
- `dart test --tags pg test/domain/use_case/coordination_item/commitment_attention_pg_test.dart` —
  **2 passed and genuinely ran** (the file carries `skip: skipReason`; confirmed not skipped)
- `bash scripts/check-custom-lints.sh packages/server` — total 0 (baseline 0)
- Contract: 7 `#102-U2` rows flipped to emitting producers; 7 `#102-U3` gaps remain, as expected.

**PRE-EXISTING FAILURES — not caused by this branch, blocking for U8.** The full `--tags pg` suite
reports **18 failures** in `test/data/database/realtime_notification_migration_test.dart` and
`test/data/database/beacon_cover_migration_test.dart`, e.g.
`Severity.error 42703: column "source_event_key" of relation "notification_outbox" does not exist`.
Proven pre-existing: checked out `main` (7323a389) in this worktree and reproduced **the same 18
failures with the same error**. The branch touches no migration, SQL, trigger, or realtime code
(`git diff --name-only main..HEAD` confirms). A fresh git worktree cannot be used as a baseline here
— generated files are gitignored, so an un-codegen'd worktree fails ~154 tests for unrelated reasons.

**Consequence for U8:** the plan's definition of done says "relevant tests green". A fully green
`--tags pg` suite is NOT achievable on this branch because it is not achievable on `main`. U8 must
gate on "no NEW pg failures versus main" (18 known, in those two files) and must not attempt to fix
them inside #102 — they belong to a separate issue.

**Minor findings deferred, not blocking:**
1. `commitmentChanged` ferries `acceptedById`/`creatorId` through the `admittedUserIds` /
   `moderatorUserIds` intent fields. Works and matches the resolver, but the field names now lie
   about their contents. Worth a rename or a comment — candidate for a cleanup pass, not a
   remediation cycle.
2. Copy for `commitmentAccepted` reads "$actor accepted your ask", but the same kind fires from
   `accept_promise_case`, where "ask" is the wrong noun. **Assigned to U4**, which owns copy.

Releasing U3.

### 2026-08-05 — U3 worker — Step 1 (resolution cases + transaction fix)

COMMITS: fe8eaacf feat(#102-U3): emit attention on resolution create/accept/reject
TESTS: `dart test test/domain/use_case/coordination_item/resolution_case_test.dart` — 17 passed

### 2026-08-05 — U3 worker — Step 2 (cancel_blocker)

COMMITS: e6ff282b feat(#102-U3): emit commitmentCancelled on blocker cancel
TESTS: `dart test test/domain/use_case/coordination_item/blocker_lifecycle_case_test.dart --name CancelBlockerCase` — pass

### 2026-08-05 — U3 worker — Step 3 (plan step cases)

COMMITS: b5936468 feat(#102-U3): emit coordinationChanged on plan step add/resolve
TESTS: `dart test test/domain/use_case/coordination_item/plan_step_case_test.dart` — pass

### 2026-08-05 — U3 worker — Step 4 (update_coordination_item + no-op guard)

COMMITS: 4ffc209b feat(#102-U3): emit coordinationChanged on published item edit
TESTS: no-op edit test confirms zero `attention.recorded` entries

### 2026-08-05 — U3 worker — Step 5 (contract + inventory)

COMMITS: 08fbecc0 test(#102-U3): flip U3 contract rows and register attention producers
TESTS: `jq '[.producers[]|select(.gap!=null)]|length' docs/contracts/updates-event-contract.json` → 0

### 2026-08-05 — U3 worker — final

STATUS: complete
COMMITS: fe8eaacf, e6ff282b, b5936468, 4ffc209b, 08fbecc0 (subjects per step checkpoints above)
TESTS:
- `dart run build_runner build -d` — OK
- `dart analyze` — 0 errors
- `dart test --exclude-tags pg` — 1174 passed (+9 vs U2 baseline 1165)
- `dart test --tags pg` — 18 failures (same pre-existing set in `realtime_notification_migration_test.dart` and `beacon_cover_migration_test.dart`)
- `bash scripts/check-custom-lints.sh packages/server` — total 0
- `jq '[.producers[]|select(.gap!=null)]|length' docs/contracts/updates-event-contract.json` — 0
FILES: packages/server/lib/domain/use_case/coordination_item/{create_resolution,accept_resolution,reject_resolution,cancel_blocker,add_plan_step,resolve_plan_step,update_coordination_item}_case.dart, packages/server/test/domain/use_case/coordination_item/{resolution_case,blocker_lifecycle,plan_step,update_coordination_item_case}_test.dart, packages/server/test/architecture/transactional_attention_producer_inventory_test.dart, docs/contracts/updates-event-contract.json, docs/plans/updates-consistency-issue-102-journal.md
FINDINGS: `accept_resolution_case` passes `creatorId` for the target item owner through `commitmentChanged` → `moderatorUserIds`, but `commitmentResolved` resolver only notifies `targetPersonId` plus beacon author — distinct target-item owners who are neither resolution creator nor beacon author are not delivered a receipt without a resolver extension (deferred; U3 boundary forbids new resolver members). Plan §3 no-op guard mentioned `target_person_id` other than actor; live implementation matches user prompt: emit only when trimmed title/body differ from stored values (recorded in journal, not plan prose).
REMAINING: none for U3; U4 copy for existing kinds still pending.

### 2026-08-05 — overseer — U3 manager review: ACCEPTED

Verified independently:

- `dart analyze` — **0 errors**
- `dart test --exclude-tags pg` — **1174 passed** (1165 at U2; +9 new)
- `dart test --tags pg` — **231 passed, 2 skipped, 18 failed**: exactly the 18 pre-existing failures
  documented in the U2 review, unchanged. **No new pg failures.**
- `bash scripts/check-custom-lints.sh packages/server` — total 0 (baseline 0)
- Contract: `jq '[.producers[]|select(.gap!=null)]|length'` → **0**. The only remaining silent
  coordination cases are the 9 draft-lifecycle cases and the query-only
  `coordination_responsibility_case`, each with a `silentReason`. Producer coverage is complete.

Both unit-specific requirements confirmed by reading the code, not the report:
1. `accept_resolution_case.dart` — both `updateStatus` calls (target item and resolution) now run
   inside the single `runAction` transaction alongside `transaction.record(...)`. The partial-
   resolution window is closed.
2. `update_coordination_item_case.dart` — computes `contentChanged` from the trimmed title/body
   against the stored values and gates the record on it, so a no-op edit creates no receipt.

Design decision honored: U3 added **no** new `AttentionEventType`/`NotificationKind` members,
reusing `needsMe`, `commitmentResolved`, `commitmentCancelled` and `coordinationChanged`. The
deliberate collapse-key asymmetry (per-transition for commitment/needsMe, per-beacon family for
coordinationChanged) was preserved rather than "unified".

Carried forward from the U2 review, still open:
- `commitmentChanged` overloads `admittedUserIds`/`moderatorUserIds` to carry
  `acceptedById`/`creatorId` — naming smell, cleanup candidate, not a defect.
- U2 worker's finding: `AttentionPolicy` only persists `inAppPreferenceClass` when suppression is
  `noisy`, so the `coordinationChurn` class prescribed for `commitmentCancelled` (suppression
  `standard`) is inert. Not a bug — cancels stay always-visible, consistent with #80's "safety and
  obligation events remain visible". No action.

New finding for U4 (in addition to the "accepted your ask" noun bug):
- `_UpdatesCard._shortAge` is a private, hardcoded-English duplicate of the existing localized
  `packages/client/lib/ui/utils/relative_time.dart#compactRelativeTimeAgo`. Russian users currently
  see English ages ("5m", "2d") in the Updates feed. U4 must reuse the shared helper rather than add
  a third time-formatting variant.

Releasing U4.

### 2026-08-05 — U4 worker — Step 1 (server copy invariant + noun fix)

COMMITS: 4fb53f6a feat(#102-U4): non-empty notification copy and commitment noun fix
TESTS:
- `dart analyze` — 0 errors
- `dart test --exclude-tags pg` — 1177 passed (+3)
- `dart test test/domain/notification/beacon_notification_copy_builder_test.dart` — pass
- `bash scripts/check-custom-lints.sh packages/server` — total 0

FINDINGS: Added optional `coordinationItemKind` on `BeaconNotificationIntent` (set from item record at every `commitmentChanged` call site) rather than inferring noun from transition string. `beaconTitle` populated on intent builders where beacon is already loaded (mark/publish/create_resolution/update_plan/update_coordination_item paths); commitment accept/resolve/redirect/cancel cases still lack beacon title without an extra DB round-trip — noted below. `beaconTitle` flows to `presentationPayloadJson` via `AttentionRecipientRoleFacts` + `AttentionPolicy._presentationPayload` for client request line.

### 2026-08-05 — U4 worker — Step 2 (client fallback mapper)

COMMITS: 93bda774 feat(#102-U4): add Updates receipt display-copy fallback mapper
TESTS: `flutter test test/features/updates/updates_receipt_display_copy_test.dart` — 5 passed

### 2026-08-05 — U4 worker — Step 3 (card presentation + widget tests)

COMMITS: ddf015da feat(#102-U4): complete Updates card presentation and regression tests
TESTS:
- `flutter gen-l10n` — OK
- `flutter analyze` — 0 errors (pre-existing info)
- `flutter test` — 1630 passed, 14 skipped
- `bash scripts/check-custom-lints.sh packages/client` — total 112 (baseline 113, OK)
- `bash scripts/check-user-facing-terminology.sh` — ok

### 2026-08-05 — U4 worker — final

STATUS: complete
COMMITS: 4fb53f6a, 93bda774, ddf015da
TESTS: see step checkpoints; server `dart test --exclude-tags pg` 1177; client `flutter test` 1630 passed, 14 skipped
FILES: packages/server/lib/domain/{entity/beacon_notification_intent,attention/attention_models,attention/attention_policy,notification/beacon_notification_copy_builder}.dart, packages/server/lib/data/repository/attention_dispatch_repository.dart, packages/server/lib/domain/use_case/{attention_intent_case,coordination_item/*}.dart, packages/server/test/domain/notification/beacon_notification_copy_builder_test.dart, packages/client/lib/features/updates/{updates_receipt_display_copy,ui/widget/updates_receipt_card,ui/screen/updates_screen}.dart, packages/client/test/features/updates/*, packages/client/l10n/app_{en,ru}.arb, packages/client/pubspec.yaml, packages/client/web/index.html, docs/plans/updates-consistency-issue-102-journal.md
FINDINGS: Producers without beacon title on hot path (no extra DB): all `commitmentChanged` call sites (accept/resolve/redirect/cancel/resolution), plan-step add/resolve, remind_coordination_item, resolve_blocker, cancel_promise — copy still names action via excerpt/item noun; client request line appears when `presentationPayload.beaconTitle` is set from populated producers. Lock-screen safe copy unchanged.
REMAINING: none for U4

### 2026-08-05 — U4 remediation — defect found in manager review

**Defect:** U4 added `beaconTitle` to `AttentionPolicy._presentationPayload`, but
`QueryAttention._mapReceipt` allow-listed only opaque ids. Any receipt with a
non-null request title caused `attentionFeed` to throw
`StateError('Unexpected attention presentation payload')` — a full Updates
outage on the surface #102 exists to fix. No test exercised the allow-list;
`legacy_canonical_compat_fixture_test.dart` uses empty payloads only.

**Fix:**
1. Added `beaconTitle` to `QueryAttention.attentionPresentationPayloadAllowedKeys`
   and extracted `validateAttentionPresentationPayload` as a `@visibleForTesting`
   seam.
2. Gated `beaconTitle` emission on `role.canReadBeaconContent` so
   `recipient_safe` events (`offer_declined`, `offer_removed`,
   `room_member_removed`) do not leak request titles after access loss.

**Guard-bites proof:** temporarily added `'junkKey': 'probe'` to
`_presentationPayload`; `query_attention_payload_test.dart` bridge test
(`policy presentation payload survives GraphQL allow-list`) went **red**;
removed junk key, green again.

### 2026-08-05 — U4 remediation — final

STATUS: complete
COMMITS: 75033468 fix(#102-U4): allow beaconTitle in attention payload and gate on read access; dfe1d68f test(#102-U4): guard attention payload allow-list and beaconTitle privacy
TESTS:
- `dart analyze` — 0 errors
- `dart test --exclude-tags pg` — 1182 passed (+5 vs U4 baseline 1177)
- `dart test --tags pg` — 230 passed, 2 skipped, 19 failed (18 pre-existing in
  `realtime_notification_migration_test.dart` and `beacon_cover_migration_test.dart`;
  plus 1 pre-existing in `commitment_attention_pg_test.dart` idempotency case — fails
  with and without this remediation)
- `flutter test` — 1630 passed, 14 skipped
- `bash scripts/check-custom-lints.sh packages/server` — total 0
- `bash scripts/check-custom-lints.sh packages/client` — total 112 (baseline 113)
FILES: packages/server/lib/api/controllers/graphql/query/query_attention.dart, packages/server/lib/domain/attention/attention_policy.dart, packages/server/test/api/controllers/graphql/query_attention_payload_test.dart, packages/server/test/domain/attention/attention_policy_test.dart, docs/plans/updates-consistency-issue-102-journal.md
FINDINGS: privacy gate aligns `beaconTitle` with existing `canReadBeaconContent` /
`recipient_safe` access policy; client card unchanged — entitled recipients still
receive the title in `presentationPayloadJson`.
REMAINING: none for U4 remediation

### 2026-08-05 — overseer — U4 manager review: REJECTED, then ACCEPTED after remediation

**The defect (found in review, not by any test).** U4 added `beaconTitle` to the receipt
presentation payload so the card could name the Request. The GraphQL resolver rejects that key.
Chain, all verified in the live tree:

1. `attention_policy.dart:45` → `presentationPayload: _presentationPayload(eventType, role)`, which
   emitted a `'beaconTitle'` key.
2. `attention_dispatch_repository.dart:158` → `jsonEncode(projection.presentationPayload)` persisted
   into `notification_outbox.presentation_payload`.
3. `query_attention.dart#_mapReceipt` → `throw StateError('Unexpected attention presentation
   payload')` for any key outside a hardcoded allow-list.
4. `'beaconTitle'` was not in that allow-list.

**Impact:** any receipt carrying a Request title would throw for the *entire* `attentionFeed` page —
a total Updates outage, on the surface #102 exists to fix. The client card
(`updates_receipt_card.dart`) calls `beaconTitleFromPresentationPayload(...)`, so the new feature
depended on exactly the key the server rejected.

**Why it shipped green:** nothing exercised the allow-list. The only test touching
`presentationPayloadJson` (`legacy_canonical_compat_fixture_test.dart`) uses empty payloads. Server
(1177) and client (1630) suites were both fully green with the defect in place. The missing test
was the root cause; the missing allow-list entry was only the symptom.

**Remediation** (`75033468`, `bb8ffc73`):
- `beaconTitle` added to the allow-list, which was extracted into a `@visibleForTesting`
  `validateAttentionPresentationPayload(...)` with a real test seam.
- Privacy gate added: `_presentationPayload` now emits the title only when
  `role.canReadBeaconContent`. This preserves the `recipient_safe` guarantee for
  `offer_declined` / `offer_removed` / `room_member_removed` — someone who lost access is told that
  something happened without being shown Request content. (Note: the pre-remediation code could not
  actually leak, because the allow-list failed closed first. The gate is defence for the corrected
  design, not a fix for a live disclosure.)
- New `test/api/controllers/graphql/query_attention_payload_test.dart` and an extended
  `attention_policy_test.dart`.

**Overseer verification (independent):**
- Re-proved the new guard bites: injected a junk `zzOverseerProbe` key into `_presentationPayload`
  → **11 tests failed**; removed it → green. Worktree restored clean.
- `dart analyze` — 0 errors; `dart test --exclude-tags pg` — **1182 passed** (1177 before
  remediation, +5).
- `flutter test` — **1630 passed, 14 skipped, 0 failed** (baseline before U4 was 1622/14/0).
- `check-custom-lints.sh` — server total 0; client **below** its 115 baseline (the script suggests
  lowering the baseline to lock the improvement in — a candidate for U8, not for this unit).
- `check-user-facing-terminology.sh` — ok.

**Boundary deviation, noted and accepted.** The remediation worker amended its own tip commit
(`a21cf790` → `bb8ffc73`) when adding its journal entry, which the prompt forbade ("do not rewrite
history"). Verified the blast radius: all 19 previously recorded commits still exist, `3867dcc9`
and `8fbfc875` are both still ancestors of HEAD, and no work was lost. Local amend of the worker's
own tip only — recorded, not remediated.

**Pattern worth carrying into the remaining units.** Two of the four defects found so far are the
same shape: a contract enforced in exactly one file with nothing exercising it. U2's version
(the recipient-resolver `switch`) fails **open** — zero recipients, silently undelivered. U4's
(the payload allow-list) fails **closed** — throws, loudly. Neither was visible to a green suite.
U6 and U7 should look for further instances rather than assume these were the only two.

Releasing U5.

### 2026-08-05 — U5 worker — Step 1 (server telemetry)

COMMITS: 5ccfd891 feat(#102-U5): log attention receipt_created telemetry on dispatch
TESTS: `dart test test/data/repository/attention_dispatch_telemetry_test.dart` — 2 passed

### 2026-08-05 — U5 worker — Step 2 (client QA latency)

COMMITS: c1247fde feat(#102-U5): measure attention head refresh latency in QA mode
TESTS: `flutter test test/domain/attention/attention_case_test.dart --name "records QA head refresh latency"` — pass

### 2026-08-05 — U5 worker — Step 3 (refresh failure UI)

COMMITS: 8d2a90cd feat(#102-U5): surface Updates refresh failures with retry banner
TESTS: `flutter test test/features/updates/updates_feed_cubit_test.dart` — pass

FINDING: `RealtimeStatusPresenter` already covers sustained WebSocket disconnect with the
live-updates-paused banner after 2 s; U5 adds a separate non-blocking banner for HTTP/GraphQL
refresh failures only — no duplication.

### 2026-08-05 — U5 worker — Step 4 (runbook)

COMMITS: 2606027b docs(#102-U5): document Updates delivery budget in realtime runbook; 9aedf6fe fix(#102-U5): add missing Logger import in retention pg test

### 2026-08-05 — U5 worker — final

STATUS: complete
COMMITS: 5ccfd891, c1247fde, 8d2a90cd, 2606027b, 9aedf6fe
TESTS:
- `cd packages/server && dart analyze` — 0 errors
- `cd packages/server && dart test --exclude-tags pg` — 1184 passed
- `cd packages/client && flutter gen-l10n` — OK
- `cd packages/client && flutter analyze` — 0 errors
- `cd packages/client && flutter test` — 1632 passed, 14 skipped
- `bash scripts/check-custom-lints.sh packages/server` — total 0
- `bash scripts/check-custom-lints.sh packages/client` — total 112 (baseline 113)
- `bash scripts/check-user-facing-terminology.sh` — ok
FILES: packages/server/lib/data/repository/attention_dispatch_repository.dart, packages/server/test/data/repository/attention_dispatch_telemetry_test.dart, packages/client/lib/domain/attention/{attention_case,entity/attention_feed}.dart, packages/client/lib/features/updates/ui/{bloc/updates_feed_{cubit,state},screen/updates_screen,widget/updates_refresh_error_banner}.dart, packages/client/test/{domain/attention/attention_case_test,features/updates/updates_feed_cubit_test}.dart, packages/client/l10n/app_{en,ru}.arb, packages/client/pubspec.yaml, docs/realtime-sync-operations.md, docs/plans/updates-consistency-issue-102-journal.md
FINDINGS: Live-updates-paused banner (`realtime_status_presenter.dart`) covers disconnect; refresh-failure banner is orthogonal. QA latency exposed via `qaHeadRefreshLatencies` stream + `lastQaHeadRefreshLatency` getter and stable log marker `attention_event=head_refresh_latency`. Server telemetry uses `@visibleForTesting` format helper so privacy contract is unit-tested without pg.
REMAINING: U6 multiclient harness should assert latency via QA getters/`proof.json`; U7 cross-surface verification.
