# Updates Completeness & Cross-Screen Consistency — Implementation Plan

Issue: [#102 — [P0][Regression] Make Updates complete, prompt and consistent across open screens](https://github.com/Intersubjective/tentura/issues/102)
Parent: #96 · Regressions against: #73 (closed), #80 (closed)
Status: **draft — awaiting execution** · Written 2026-08-05 · Schema tip at authoring: `m0138`
Execution mode: **overseer skill** (sequential fresh Cursor `composer-2.5` workers, one unit at a time)

---

## 1. Problem statement (from live-code investigation, not from the issue text)

The reporter's scenario — *author A stays on My Work, participant B accepts/commits, A sees nothing* —
is **not** a transport regression. The `entity_changes` realtime path from #73 and the attention
feed/badge stack from #80 are both intact and correctly wired:

- `notify_entity_change()` (m0133) fans `coordination_item` changes to
  `realtime_room_recipients(beacon)` + `creator_id` + `target_person_id` + `accepted_by_id`.
- Client `AttentionCase` (`packages/client/lib/domain/attention/attention_case.dart`) subscribes to
  `RealtimeEntityKind.notification` **and** `catchUps`, with an in-flight + single-queued-rerun
  refresh budget.
- `UpdatesNavbarItem` and `MyWorkNavbarItem` both derive from `AttentionCase` — a single source.
- `MyWorkCase.deskRelevantChanges` already includes `BeaconRoomEntityType.coordinationItem`.

**The actual defect is missing producers.** Of 35 coordination-item use cases, only 10 build an
`AttentionDispatchIntent`. Every acceptance/commitment/closure transition is silent:

| Use case (`packages/server/lib/domain/use_case/coordination_item/`) | Emits attention? | Who loses the event |
|---|---|---|
| `accept_ask_case.dart` | **no** | ask creator — **the exact #102 scenario** |
| `accept_promise_case.dart` | **no** | promise creator |
| `resolve_ask_case.dart` | **no** | ask creator |
| `resolve_promise_case.dart` | **no** | promise recipient |
| `cancel_ask_case.dart` | **no** | ask target |
| `cancel_blocker_case.dart` | **no** | room participants |
| `create_resolution_case.dart` | **no** | owner of the resolved blocker/ask |
| `accept_resolution_case.dart` | **no** | resolution author + target-item owner |
| `reject_resolution_case.dart` | **no** | resolution author |
| `redirect_ask_case.dart` | **no** | **the new target person** — reassigned work, zero notice |
| `redirect_promise_case.dart` | **no** | new target person |
| `add_plan_step_case.dart` / `resolve_plan_step_case.dart` | **no** | room participants |
| `update_coordination_item_case.dart` | **no** | target of an edited published item |
| `mark_ask_case`, `mark_blocker_case`, `publish_draft_*`, `create_promise_case`, `cancel_promise_case`, `resolve_blocker_case`, `remind_coordination_item_case`, `update_plan_case` | yes | — |
| `create_draft_*`, `update_draft_*`, `delete_draft_*` | no — **correct**, drafts are private to the creator | — |

Corroborating facts:

- `docs/contracts/updates-event-contract.json` declares **10** event types and
  `"pendingProducerEventTypes": []` — i.e. the contract asserts full coverage while ~13 real
  transitions have no declared producer. Nothing tests that assertion.
- The silent cases also do **not** run inside `TransactionalAttentionCase.runAction`, so even after
  adding intents there is no atomic mutation+receipt boundary. `accept_resolution_case.dart`
  additionally performs **two** `updateStatus` writes with no enclosing transaction — a partial
  resolution is possible today.
- `AttentionEventType` (`domain/attention/attention_models.dart`) has no
  accepted/resolved/cancelled/redirected members. `attention_occurrence.event_type` (m0121) and
  `notification_outbox.kind` (m0096) are **unconstrained `text`** — new members need **no migration**.
- Presentation: `BeaconNotificationCopyBuilder` produces bare titles (`"Asked of you"`,
  `"Plan updated"`, `"Blocker opened"`) with no request title and no next step; `_UpdatesCard`
  (`features/updates/ui/screen/updates_screen.dart`) renders `receipt.title` / `receipt.body`
  **unguarded**, so a receipt with empty copy renders a blank card — the "empty/false notification
  card" the issue calls out. Age is rendered as `"2d"` with no absolute local time.
- No creation-to-render latency instrumentation exists. `docs/realtime-sync-operations.md` states a
  1.5 s connected / 3 s reconnect p95 budget, but nothing measures the *attention receipt* leg.

**Conclusion:** #102 is a producer-coverage + presentation + observability gap, not a re-do of #73/#80.

---

## 2. Acceptance criteria (verbatim from the issue) → unit map

| Criterion | Units |
|---|---|
| Multi-client: A on My Work, B accepts/commits, A updates without navigation or reload | U2, U6 |
| Event appears exactly once, links to the affected request/person state | U2, U3, U6 |
| Updates and request detail consistent within the latency budget | U5, U6 |
| Reconnect catches up missed events without duplicates | U6 |
| Empty/false notification cards impossible | U4 |
| Regression coverage for the precise My Work scenario | U6 |
| Instrument event creation-to-render latency | U5 |
| Every state-changing request event emits one canonical activity event | U1, U2, U3 |
| Event reaches all entitled users regardless of open screen | U2, U3 (server) — transport already correct |
| My Work, request detail, People, Updates derive from the same source | U6 (verify) |
| Notifications present actor, action, request, time, next step | U4 |
| Defined latency target with visible retry/error behavior | U5 |

---

## 3. Non-goals

- **Do not** redesign the realtime transport, the `entity_changes` envelope, or the five-table
  attention topology. Both are working; `docs/notification-attention-convergence-plan.md` §3
  do-not-touch invariants remain binding.
- **Do not** change the `attentionFeed` / `attentionMarkers` GraphQL output shape (client contract).
- **Do not** remove the `notify_*` trigger `EXCEPTION … RETURN NULL` fail-open wrapper.
- **Do not** add a second caller of `AttentionDispatchRepository.record()` from a data adapter —
  only domain use cases may call it, inside their own transaction.
- **Do not** take on sibling issues: #108 (Archive), #111 (blocking), #112 (timezone rendering).
  U4 renders an absolute local timestamp only where the Updates card already shows relative age; the
  app-wide timezone sweep stays in #112.
- **Do not** resume the deferred T-20/21/22 work (occurrence store rework, durable channel jobs,
  dot unification) — out of scope per the #80 rev-4 scope decision.
- No push/email channel changes. This plan is about the **in-app** activity surface.

---

## 4. Decisions taken (a worker must not re-litigate these)

1. **New `AttentionEventType` members rather than overloading `coordinationChanged`.**
   `coordinationChanged` carries `AttentionCollapseKey.family('coordination_changed', [beaconId])`,
   which collapses all coordination churn for a request into one row. That directly violates *"the
   event appears exactly once and links to the affected request/person state"* — an acceptance of
   *your* ask must be its own row pointing at that item. New members are code-only (no migration,
   no DB check constraint, client treats `kind` as an opaque string with an icon fallback).

2. **Source-event-key scheme** reuses the existing convention from `mark_ask_case.dart`:
   `coordination_item:<itemId>:<transition>:<updatedAt.toUtc().microsecondsSinceEpoch>`.
   This gives replay idempotency for free via the `source_event_key` unique index.

3. **Collapse policy:** `AttentionCollapseKey.none(sourceEventKey)` for all directed
   accept/resolve/cancel/redirect events (one row per transition). Only genuinely bursty,
   non-directed churn keeps a family collapse key.

4. **Preference class:** directed obligation transitions (redirect-to-me, ask accepted on my
   request, resolution proposed on my blocker) are `requestProgress`; incidental room churn
   (plan steps, published-item edits) is `coordinationChurn`. Safety/obligation events stay
   `mandatory` per #80.

5. **Transaction boundary:** every newly-emitting case is wrapped in
   `TransactionalAttentionCase.runAction`, so the state change and its receipt commit together or
   not at all. `accept_resolution_case`'s two writes are brought into that same transaction.

**Open question for the user, not for a worker** — U3 covers ~9 lower-severity transitions
(plan steps, published-item edits, cancel-blocker, resolution accept/reject). If the goal is only to
unblock the next usability session, U3 may be deferred and the issue closed on U1+U2+U4+U5+U6. The
overseer should ask before starting U3 if a session date is pending.

---

## 5. Plan units

Units are dependency-ordered. Each is one fresh Cursor worker. Within a unit, commit after each
coherent step (do not bundle the whole unit into one commit).

**Shared verification commands** (used by every unit's exit gate):

```bash
cd packages/server && dart analyze && dart test --exclude-tags pg
cd packages/server && dart test --tags pg            # needs local Postgres (docker compose)
cd packages/client && flutter analyze && flutter test
bash scripts/check-custom-lints.sh                   # baseline: client 115, server 0 — must not grow
```

After any Injectable/DI change: `cd packages/server && dart run build_runner build -d`
(`di.config.dart` is generated and gitignored — never hand-edit).

---

### Unit 1 — Make event coverage a testable contract (no behavior change)

**Goal:** turn "every state-changing request event emits one canonical activity event" from prose
into a guard that fails when a new silent mutation is added.

**Changes**

- Extend `docs/contracts/updates-event-contract.json` to `schemaVersion: 2`, adding a
  `producers` array: one entry per state-changing use case with `useCase`, `eventType`
  (or `null`), `recipientCategory`, `destinationFamily`, `muteability`, `coveringTest`, and — for
  deliberately silent cases — `silent: true` with a `silentReason` (e.g. `"draft is private to its
  creator until published"`). Seed it with **today's** reality, including the silent gaps, each
  tagged `gap: "#102-U2"` or `gap: "#102-U3"`.
- Add `packages/server/test/architecture/updates_event_coverage_test.dart` (model it on the existing
  `test/architecture/realtime_entity_contract_test.dart`): enumerate every `*_case.dart` under
  `domain/use_case/coordination_item/` plus the named beacon/room/evaluation producers, and assert
  each appears exactly once in `producers`. Fail on an undeclared file. Assert every non-silent
  entry's `eventType` is a real `AttentionEventType` member and its `coveringTest` file exists.
- No production-code change in this unit.

**Acceptance:** adding a new use-case file under `coordination_item/` without a contract entry fails
the suite (prove it locally by temporarily adding a scratch file, then delete it).

**Exit gate:** server analyze + unit suite green; new test green. One commit.

---

### Unit 2 — Emit the acceptance/commitment events (the #102 core scenario)

**Depends on:** U1.

**Goal:** the reported scenario produces exactly one canonical event that reaches the author while
they sit on My Work.

**Changes** (`packages/server/lib/`)

- `domain/attention/attention_models.dart`: add `AttentionEventType` members
  `commitmentAccepted`, `commitmentResolved`, `commitmentCancelled`, `commitmentRedirected`.
  Keep `isBeaconScoped` returning `true` for all four (default branch already does).
- `domain/entity/notification_kind.dart`: add `commitmentAccepted`, `commitmentResolved`,
  `commitmentCancelled`, `commitmentRedirected` (or map onto the existing `commitmentEvent` —
  **decide by whether `categoryOf()` and the push preference matrix can already route
  `commitmentEvent` correctly for these; if a single kind loses the accept/resolve distinction in
  copy or preferences, add the new members**). Update `categoryOf()` and any exhaustive `switch`
  the compiler flags — `dart analyze` is the authoritative list.
- `domain/use_case/attention_intent_case.dart`: add `commitmentChanged({beaconId, actorUserId,
  transition, excerpt, sourceEventKey, targetPersonId, coordinationItemId})` built via
  `fromBeaconNotification`, with `AttentionCollapseKey.none(sourceEventKey)`.
- Wire these four cases, each wrapped in `_attention!.runAction(actorUserId: userId, action: …)`
  with the intent recorded on the caller-owned transaction (copy the shape from
  `mark_ask_case.dart:67-95`):
  - `accept_ask_case.dart` → recipient: item `creator_id` (+ beacon author if distinct)
  - `accept_promise_case.dart` → recipient: item `creator_id`
  - `resolve_ask_case.dart`, `resolve_promise_case.dart` → recipient: the counterpart
    (`creator_id` when the actor is the target; `target_person_id` when the actor is the creator)
  - `redirect_ask_case.dart`, `redirect_promise_case.dart` → recipients: **new** target person
    (obligation) **and** previous target person (release)
  - `cancel_ask_case.dart` → recipient: `target_person_id` and `accepted_by_id` when set
- Constructor params follow the existing optional-nullable pattern
  (`AttentionIntentCase? attentionIntents, TransactionalAttentionCase? attention`) so existing unit
  tests that construct these cases directly keep compiling.
- Update the U1 contract entries: flip these from `silent` to declared producers, drop their
  `gap` tags.

**Tests**

- Per case, a unit test asserting the intent is built with the right event type, recipients, and
  `sourceEventKey` shape.
- `test/data/repository/…` pg test: replaying the same transition (same item, same `updated_at`)
  creates **one** receipt, not two.
- pg test: accepting an ask on beacon B creates a `notification_outbox` row for the ask creator
  with a non-null `beacon_id` and `coordination_item_id`.

**Acceptance:** B accepting A's ask writes exactly one receipt addressed to A, in the same
transaction as the status change, linked to both the request and the item.

**Exit gate:** server analyze + both suites green; U1 guard green. Commit per case-group
(accept / resolve / redirect / cancel), not one bundled commit.

---

### Unit 3 — Emit the remaining silent transitions

**Depends on:** U2. **Ask the user before starting** (see §4 open question).

**Changes:** same pattern as U2 for `create_resolution_case`, `accept_resolution_case`,
`reject_resolution_case`, `cancel_blocker_case`, `add_plan_step_case`, `resolve_plan_step_case`,
`update_coordination_item_case`.

Additionally fix the latent correctness bug in `accept_resolution_case.dart`: its two `updateStatus`
calls (target item + resolution) must run inside the single `runAction` transaction so a partial
resolution is impossible.

`update_coordination_item_case` emits **only** when the edit changes `title`/`body` of a *published*
item that has a `target_person_id` other than the actor — a no-op edit must not create a receipt.

**Tests:** one unit test per case; a pg test proving `accept_resolution_case` rolls both status
writes back together on failure; a test proving a no-op edit emits nothing.

**Exit gate:** both server suites green; U1 guard shows zero remaining `gap` entries.

---

### Unit 4 — Presentation completeness and the no-empty-card invariant

**Depends on:** U2 (needs the new kinds to write copy for).

**Server** (`packages/server/lib/domain/notification/beacon_notification_copy_builder.dart`)

- Every branch must yield a **non-empty** title and body. Add a test that iterates
  **all** `NotificationKind` values × an intent with empty excerpt/actor/beacon title and asserts
  both strings are non-empty and contain no raw ids.
- Give copy the four facts the issue names — actor, action, request, next step:
  - carry the request title into the intent where it is currently dropped (`beaconTitle` is already
    a `BeaconNotificationIntent` field but several intent builders never populate it);
  - copy for the new U2 kinds, e.g. `"<actor> accepted your ask"` / body = request title +
    excerpt; redirect: `"<actor> reassigned this to you"` with the next step made explicit.
- Time is not copy — it stays `created_at` on the receipt and is rendered client-side.

**Client** (`packages/client/lib/features/updates/`)

- `_UpdatesCard`: never render an empty card. If `receipt.title` is blank, fall back to a
  kind-derived l10n title; if `receipt.body` is blank, fall back to a kind-derived line; if the
  receipt is a tombstone/redacted shape, render the existing safe-terminal presentation. Extract the
  fallback into a small pure mapper so it is unit-testable without a widget pump.
- Show the request title as a distinct line where `receipt` carries a beacon reference, and render
  the timestamp as **relative age + absolute local time** (tooltip/secondary line). Local-time
  rendering here must use the same helper #112 will generalize — do not invent a second one.
- Route all styling through the design system (`context.tt`, `TenturaText`, no raw constants) — the
  `material-3-flutter` skill contract applies; new l10n keys go in **both** `app_en.arb` and
  `app_ru.arb`, respecting the Request/Chat user-facing terminology rule.

**Tests:** widget test that a receipt with empty title **and** empty body renders a non-empty,
tappable card with a stable semantics label; a test that the card exposes actor, action, request and
time; l10n completeness check.

**Exit gate:** client analyze + tests green; `scripts/check-custom-lints.sh` not above baseline;
`scripts/check-user-facing-terminology.sh` green.

---

### Unit 5 — Latency budget and instrumentation

**Depends on:** U2.

**Goal:** creation-to-render latency is measurable, has a stated target, and slow/failed propagation
is visible to the user.

- **Server:** on `AttentionDispatchRepository.record()` success, log a structured line with the
  existing marker convention (`attention_event=receipt_created`) carrying `event_type`,
  `recipients` (count only — no ids, no payload), and the occurrence timestamp. Follow the
  privacy rule already documented in `docs/realtime-sync-operations.md` (counts, never recipients).
- **Client:** in `AttentionCase`, record `receipt.createdAt → snapshot emitted` for the newest
  receipt in each head refresh; expose it as a debug/QA-only measurement gated behind the existing
  `QA_INTEGRATION_TEST_MODE` define so the multiclient harness can assert on it. Do not add
  always-on telemetry.
- **Budget:** adopt the existing realtime numbers so there is one budget, not two — connected
  convergence **p95 ≤ 1.5 s**, reconnect catch-up **p95 ≤ 3 s**, measured receipt-commit → card
  visible. Document in `docs/realtime-sync-operations.md` under a new "Updates delivery budget"
  section, plus the alert thresholds.
- **Visible retry/error behavior:** confirm the existing live-updates-paused banner covers the
  Updates surface; if `UpdatesFeedCubit` swallows a refresh failure into a log line only
  (it currently does — `_logger.warning` in `refresh()`), surface a non-blocking retry affordance in
  the feed's status area rather than failing silently.

**Tests:** a cubit test that a failed refresh produces a user-visible error state with a retry, not
just a log; the harness artifact from U6 carries the measured latency in `proof.json`.

---

### Unit 6 — Regression coverage: the precise My Work scenario

**Depends on:** U2, U4, U5. (Run before U3 if U3 is deferred.)

**Goal:** the exact reported scenario is covered by an automated multi-client test, plus reconnect
de-duplication.

- Extend `packages/client/test_driver/realtime_multiclient_web_test.dart` (driven by
  `scripts/run_realtime_multiclient_web_local.sh`, which owns three Chrome sessions) with:
  1. **My Work scenario:** A signs in and stays on My Work; B accepts an ask / commits on A's
     request; assert **without any navigation or reload** that (a) the Updates badge increments,
     (b) the My Work card reflects the new participant state, (c) the Updates feed contains
     **exactly one** matching event, (d) elapsed time is within the U5 budget. Keep the existing
     semantics-identifier approach (`updates-unread-count-<n>`) rather than screenshot diffing.
  2. **Reconnect catch-up:** force a missed event (the runner already supports a forced-miss path),
     reconnect, assert the event appears exactly once — assert on receipt id sets, not counts alone.
- Add a client-side integration or widget-level regression for the same state transition where it
  can be covered more cheaply, so the fast suite catches regressions too (see
  `docs/local-integration-tests.md` for runner ownership).
- Record proof artifacts under `packages/client/reports/realtime-multiclient/updates-102-<date>/`
  following the existing `updates-t21-markers-*` layout (`proof.json` + failure-only screenshots).

**Exit gate:** the multiclient runner passes **five consecutive times** (release rule in
`docs/realtime-sync-operations.md`) and **fails** when delivery is deliberately disabled.

---

### Unit 7 — Cross-surface consistency verification

**Depends on:** U6.

**Goal:** discharge *"My Work, request detail, People and Updates derive from the same event/state
source"* with evidence rather than assumption.

- Trace each of the four surfaces to its source and record the finding in the journal. Expected
  result from the pre-plan investigation: all four already derive from `AttentionCase` +
  `entity_changes`; this unit is **verify-then-fix-only-if-broken**, not a refactor.
- Add architecture-level assertions where a surface bypasses the shared source (e.g. a cubit
  holding a locally-incremented counter instead of deriving from the feed).
- If nothing is broken, the unit's output is journal evidence + any missing test, not code churn.

---

### Unit 8 — Integration and close-out

**Depends on:** all above.

- Re-read the plan and journal from the top; confirm every §2 acceptance row has a named test.
- Full matrix: server analyze + `--exclude-tags pg` + `--tags pg`; client analyze + `flutter test`;
  `scripts/check-custom-lints.sh`; `scripts/check-doc-drift.sh`;
  `scripts/check-user-facing-terminology.sh`; `bash scripts/run_client_integration_web_local.sh`;
  `bash scripts/run_realtime_multiclient_web_local.sh` ×5.
- Update `docs/contracts/updates-event-contract.json` to its final state (zero `gap` tags, or the
  U3 deferral recorded explicitly with the user's decision).
- Add a short "Updates delivery" entry to `docs/realtime-sync-operations.md` incident triage.
- Journal final evidence summary: commit hashes, verification output, measured latency, anything
  explicitly deferred.

---

## 6. Shared journal

`docs/plans/updates-consistency-issue-102-journal.md` — created by the overseer before Unit 1 and
excluded from the work manifest. Initialize with: objective and plan path; repo, branch, starting
HEAD; the pre-existing untracked files listed in §7; the unit checklist; verification commands; open
decisions (the §4 U3 question).

Every worker reads the whole journal before editing, appends a checkpoint on meaningful progress,
and appends a final entry with `STATUS / COMMITS / TESTS / FILES / FINDINGS / REMAINING` before exit.

---

## 7. Overseer operating notes

**Branch:** create `feat/updates-consistency-102` off `main` before Unit 1; never commit to `main`.

**Pre-existing worktree state to preserve untouched** (present at plan authoring, all untracked):
`dart-defines`, `docs/plans/graph-navigation-implementation-guide.md`,
`docs/plans/graph-navigation-rework-plan.md`, `graph-ego-neighbors-layout-issue.md`, `key.fb`,
`out.key`, `product_testing_compact_buglist.md`, `product_testing_detailed_report.md`.
Workers must not stage, move, or delete any of these. `key.fb` / `out.key` are key material —
never read, print, or commit them.

**Boundaries every worker prompt must repeat:**

- Never hand-edit generated files: `*.g.dart`, `*.freezed.dart`,
  `packages/server/lib/app/di.config.dart`. Regenerate with `dart run build_runner build -d`.
- Migrations are append-only and immutable once merged; next free number is `m0139`.
  **This plan is expected to need no migration** — if a worker believes one is required, it must
  stop and report rather than invent schema.
- Architecture rules: `.cursor/rules/architecture.mdc` + the `clean-architecture` skill contract.
  Dependency direction is inward; domain stays pure; no data adapter may call
  `AttentionDispatchRepository.record()`.
- UI work goes through the design system (`material-3-flutter` skill,
  `.cursor/rules/tentura-design-system.mdc`); no raw visual constants in feature UI.
- User-facing terminology: **Request** / **Chat**; code paths stay `beacon_*`.
- Do not push, open a PR, deploy, or rewrite history.
- The live repository and current tests outrank this document where they disagree — report the
  discrepancy in the journal rather than forcing the plan's wording.

**Suggested worker sizing:** U2 is the largest unit; if a single turn cannot finish it reliably,
split by transition group (accept → resolve → redirect → cancel) into sequential subunits, keeping
the same dependency order. U1, U5 and U7 are small.

**Manager review per unit:** inspect every commit and uncommitted diff, run the exit-gate commands
independently rather than trusting the worker's report, and map the result to the §2 acceptance
rows before accepting.

---

## 8. Definition of done

- Every row in §2 maps to a green, named test.
- `docs/contracts/updates-event-contract.json` has no `gap` entries (or an explicit, user-approved
  U3 deferral recorded in both the contract and the journal).
- The U1 coverage guard fails when a new silent state-changing case is added.
- The My Work multi-client scenario and the reconnect-dedup scenario pass five consecutive runs and
  fail when delivery is disabled.
- Measured creation-to-render p95 is inside the documented budget, and the number is in the journal.
- No empty Updates card is reachable for any `NotificationKind`, including empty-copy receipts.
- All orchestrator-owned changes committed on `feat/updates-consistency-102`; the §7 pre-existing
  files remain untouched; nothing pushed.
