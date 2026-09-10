# Inbox → Activity: implementation plan

Status: implementation plan, revision 3. Companion to [`inbox-activity-ia-architecture.md`](inbox-activity-ia-architecture.md), which is the authority on *what* is being built and *why*. This document owns *what has to exist first*, *in what order*, and *what breaks*.

Date: 2026-09-10. Repository baseline: `c6b24012d` plus this branch.

Split out of the architecture document at its revision 6. Seven adversarial review passes had by then pushed every surviving objection into exactly this material — server contracts, migration ordering, shipping sequence, blast radius — which is implementation-plan content that the architecture document was never scoped to carry. The split is a response to that, not a reorganisation for its own sake.

## 1. Shipping sequence

The architecture's §8 forbids removing obligations from Activity before My Work can accept them. That constraint has a consequence the architecture document previously stated wrongly: it is **not** true that only the prompt-convergence work gates the Activity change.

| step | what ships | why it cannot move earlier |
|---|---|---|
| 1 | §2.1 live-obligation contract | nothing downstream can identify an obligation without it |
| 2 | §2.2 settlement change notification | without it, step 3's scope never updates on other devices |
| 3 | §3 — My Work **fully** accepts obligations (see below) | the destination must exist and be usable before the source is removed |
| 4 | "Needs you" leaves the Activity feed | only now does it have somewhere to land |
| 5 | §2.4 prompt convergence | gates the Activity body change, independently of 1–4 |
| 6 | Activity branch layout: TabBar removed, feed becomes the body, triage row, pinned prompts | needs 4 and 5 |
| 7 | §2.3 `expired` settlement, §2.5 obligation badge on My Work | improves accuracy; nothing above depends on it |

**Step 3 is a shipping gate, not a list of edits.** It is complete only when a user could do everything in My Work that they can do in the Activity "Needs you" view today. Concretely it must deliver all of:

- the four items in §3 (membership input, card derivation, refresh triggers, archive semantics);
- **a usable obligation view in My Work** — the destination "Needs you" moves *to*, not merely the data behind it;
- **the settlement actions** on that view, so an obligation can be discharged where it now lives;
- **per-destination feed sessions** (architecture §7). Today every `UpdatesFeedCubit` adopts the singleton's selected view (`updates_feed_cubit.dart:29`), so mounting the existing feed in a second destination couples the two: changing the view in one changes it in the other. Without this, step 3 "succeeds" while making Activity worse.

Steps 1–4 and step 5 are independent **only once session ownership is fixed**; numbering alone does not establish it, because step 5 touches the same feed widgets.

**Steps 1–3 ship behind an activation gate.** They are safe to land early precisely because nothing reveals them: the new My Work view stays unmounted, or is mounted behind a flag, until step 4 flips both together. "No visible change" is a property of the gate, not of the work — without one, step 3 exposes a second obligation surface while the first still exists, and the two disagree about view state.

**The step-3/step-4 intermediate state is an explicit test target**, not an assumed no-op: with step 3 landed and step 4 not, Activity must behave exactly as it does today.

## 2. Server contracts

Six items. §2.4 is the only one that gates the Activity **body** (step 6) directly; §2.1 and §2.2 gate it indirectly, by way of step 3 and step 4. §2.3 and §2.5 improve accuracy and gate nothing.

**2.1 Live-obligation beacon-id contract.** A query returning the authorized set of beacon ids for which the viewer holds a live obligation — symmetric to `unreadForBeacons` (`attention_repository.dart:24-48`) and sharing its authorization path so the two cannot diverge. `notification_outbox` is not registered in Hasura metadata, and Beacon reads require `can_read_content` (`hasura/metadata.json:274-277`) which an obligation does not confer, so this cannot be expressed as a client-side query condition. It is a server endpoint or nothing.

**2.2 Settlement must emit a change notification.** `settle` updates only the `settlement_*` columns (`attention_repository.dart:405-415`), while the change-detection tuple driving realtime notification compares `read_at` and `seen_at` and **not** the settlement columns (`m0116.dart:55-76`). So "Mark done" on one device updates neither the badge nor the scope on another. Required: either extend that comparison tuple to include settlement columns, or emit a recipient-targeted invalidation inside the settling transaction. Acceptance: a settlement-only update, with `seen_at` and `read_at` unchanged, converges on a second connected device.

**2.3 The `expired` settlement kind.** The CHECK constraint admits only `resolved, dismissed, superseded, legacy_archived` (`m0118.dart:15-18`), so the UPDATE fails outright. `attention_models.dart:147-160` is a closed enum parsed with `firstWhere` and `attention_repository.dart:203-207` converts on read, so an old server instance reading an `expired` receipt throws. In order:

1. CHECK migration admitting `expired`;
2. server enum and parser accepting it;
3. deploy until no old reader remains;
4. only then enable the writer.

The writer is a **system** settlement path, not the user one — `attention_settlement_case.dart:26-28` is limited to two user-driven values. It must set `settled_at` (the `settlement_facts_chk` constraint requires it) and preserve existing `seen_at` / `read_at`. A receipt already marked seen is still in scope: seen is not settled.

Where it fires: review-window close. `task_worker_case.dart:191-199` sweeps every minute, `evaluation_case.dart:144-145` invokes the same sweep, and `attention_expiry_sweep_case.dart:33-48` → `review_finalization_case.dart:73-99` is the transaction boundary. Two gaps the hook alone leaves open:

- **Backfill.** The sweep only visits `status = 0` (`attention_expiry_repository.dart:19-23`) and the finalizer stops at `evaluation_repository.dart:663-664`, so windows closed before this ships are never revisited. Under the architecture's §8 their obligations would pin their Requests into My Work permanently. A one-time backfill is required.
- **Reopen.** `evaluation_case.dart:445-455` deletes review scaffolding and returns the Request to Open, removing the expiry target. Reopen must settle outstanding obligations as `superseded`.

**Outcomes, with the "submitted" predicate defined.** "Submitted" is ambiguous in the code and must not be used loosely: `evaluationSubmit` handles a single target and sets that reviewer's package to `status: 1` (`evaluation_case.dart:1348`), while only `evaluationFinalize` marks the complete package `status: 2` (`evaluation_case.dart:1473`), and window closure deletes evaluations belonging to packages that were never sent (`evaluation_repository.dart:729`).

Settlement is therefore keyed on **`beacon_review_status.status = 2`**, scoped to the obligation's own review package:

| condition at window close | settlement |
|---|---|
| package finalized (`status = 2`) | `resolved` |
| package not finalized, including targets individually submitted inside an unsent package | `expired` |
| review reopened | `superseded` |

Specify the matching between an obligation receipt and its package, and the transaction boundary. Test explicitly: a submitted target inside an unsent package **expires**, it does not resolve. Verify against both seen and unseen receipts.

**2.4 Prompt-state convergence.** Two parts, and both are required whichever storage branch is chosen:

- *Freshness at read.* Either join prompt state into the feed read, or batch-fetch it before the feed renders. A static `pending` flag on the receipt payload does not work: dispatch stores an event-time projection (`attention_dispatch_repository.dart:84-88,140-141,168`), the feed read never joins prompt state (`attention_repository.dart:82-104`), and `answer`/`skip` write a different table (`invite_seed_attestation_case.dart:63-95`), so a frozen flag reads `pending` forever.
- *Invalidation, committed atomically with the mutation.* `skip` updates only the prompt row (`invite_seed_attestation_case.dart:86`) with no notification trigger (`m0146.dart`), and the client refetches only on notification, catch-up, or block change (`attention_case.dart:95`). A join gives freshness **at fetch time**; it does not cause a fetch. A connected second device re-runs nothing. So the mutation must emit a recipient-targeted invalidation regardless of which freshness branch is chosen.

  **The emission belongs in the same database transaction as the prompt write**, matching §2.2's requirement for settlement. `answer` is already wrapped in a transaction (`invite_seed_attestation_case.dart:70-82`) but `skip` is a standalone write (`:86-95`). A post-write emission leaves a failure window in which the state commits, the emission does not, and another connected device stays stale indefinitely with no event that would ever correct it. Use the existing transactional realtime mechanism. Tests: rollback leaves neither the state change nor an emission; a committed change is visible to a second connected client without a refetch trigger of its own.

- *Tri-state, so prompts cannot block the feed.* The projection reports **unknown / known / failed** (architecture §4.8). Fetching "before the feed renders" means *before placement is decided*, not before the feed paints: the feed renders from receipts alone, and only prompts whose state is known become pinning candidates. Test a successful feed load with a failed prompt load — the feed must be fully usable, with prompt rows in chronological position.

**Authorization is not inherited.** Prompt reads today check blocked pairs, direct-inviter status, and prompt ownership (`invite_seed_attestation_case.dart:125`), whereas a receipt's `profile` access policy checks only presentation shape (`m0117.dart:46`). A naive join would expose prompt state the current endpoint would refuse — for instance after a block. The projection must carry an equivalent authorization predicate: keep the history receipt, withhold the actionable prompt state. Performance is not a concern if the join runs after the page limit (`attention_repository.dart:118`); the summary and the `(created_at, id)` cursor need no change.

**2.5 Obligation count for the My Work badge.** The badge counts **authorized live obligations** — `requires_action AND settlement_kind IS NULL`, under the same authorization as §2.1. `needs_you_total` today lacks a `seen_at IS NULL` filter while `unread_total` beside it has one (`attention_repository.dart:89-95`), but an unseen-filtered counter is **not** a substitute: `isSeen` and `isLiveObligation` are independent (`attention_receipt.dart:35`), so one already-read unsettled review with no triage and no unread would show nothing on either destination while My Work's contract says `1`. If an unseen counter is added, it is for some other purpose and must not be wired to this badge. §2.3's expiry is what makes the live count decay.

**2.6 Scope/count coincidence test.** Every live obligation must imply My Work scope membership. This has been asserted prematurely twice on different grounds and was wrong both times, so it is a test, not an argument.

Prerequisites are wider than the server work: the server projection needs §2.1 and §2.3, but *My Work inclusion* needs step 3 and *badge verification* needs §2.5. Split accordingly:

- **Server projection tests** — set inclusion and count under one authorization condition and **one snapshot**, taken from a single read so the two cannot drift. Name the snapshot mechanism explicitly rather than reading twice.
- **Mounted-client acceptance** — the same properties observed through My Work after step 3.

**Receipt multiplicity is the case most likely to be missed.** Obligations are per-receipt and separate help offers produce separate occurrence keys (`help_offer_case.dart:152`), while My Work merges by Beacon identity (`derive_my_work_cards.dart:207`). Required fixture: one Request with **two** live obligation receipts — expect two obligations and **one** card; settling one must leave the card in place; settling the last removes it only if no other membership source remains. Test that last clause with an authored Request as the surviving source.

**Two reasons a Request leaves scope, and they must not be conflated.** Content permission is lost through a block (`m0162.dart:15`) and content-policy receipts are excluded at read time (`m0117.dart:39`), so "left scope" does not imply "settled". Authorization loss must never write a terminal settlement.

## 3. What My Work must gain

The architecture's §8 states the invariant. Mechanically it needs four things, not three:

1. **A third input** alongside authored and help-offered — the beacon-id set from §2.1. `my_work_fetch.graphql:6-23` has two sets and `derive_my_work_cards.dart:199-212` handles two.
2. **Card derivation for an obligation-only Request.** It may be archived or carry no active offer, so no existing card builder has a row to hang on. Needs its own Beacon fetch, role/kind, default-filter treatment, and archive affordance.
3. **Refresh triggers** — the set changes on obligation arrival, settlement, expiry, **and authorization change**. None are events My Work listens to today (`my_work_cubit.dart:24`), and §2.2 is what makes settlement observable at all.

   Authorization change is the trigger most easily missed, because the receipt does not change. Unblocking an author re-authorizes an existing obligation: `BlockRepository.unblock` emits a block-domain event (`block_repository.dart:51`) which Attention already subscribes to (`attention_case.dart:101`) and My Work does not. Both directions count — blocking must drop the Request from scope, unblocking must restore it. Test on a mounted client with no reconnect and no unrelated notification, and confirm settlement columns are untouched throughout.

4. **Archive semantics — deeper than guarding the removal call.** `my_work_cubit.dart:229` unconditionally calls `_removeBeaconFromState` after archiving and `:232` increments `archivedCountHint`; `:357` strips the Request from both card sets. Worse, archive state is *conflated with card kind*: `isArchived` derives solely from archived kinds (`my_work_card_view_model.dart:85`) and those kinds fail the default filter (`derive_my_work_cards.dart:224`), while keeping the old kind leaves the "Archive" affordance live (`my_work_cards.dart:194`) so each invocation increments the hint again.

   Guarding `_removeBeaconFromState` alone is therefore insufficient. The minimum coherent change:

   - membership has sources; archive revokes the authored/help-offered source only;
   - **viewer archive state is tracked independently of card kind**;
   - exactly **one card per Beacon**, whatever combination of sources it has;
   - obligation-backed cards pass the default filter;
   - the archive affordance and `archivedCountHint` are idempotent.

   Verify: immediate archive, repeated archive of the same Request, reload, and settlement of the final obligation.

## 4. Cleanup: retired coordination machinery

Ask, Blocker and Promise are retired in `DiscussionProductPolicy.retiredCoordinationKinds`; Plan is retired by product decision, leaving `supportedCoordinationKinds` empty in practice. The following are dead and are to be removed as a distinct, separately reviewable change:

- server use cases under `domain/use_case/coordination_item/` (`publish_draft_ask_case`, `mark_ask_case`, `accept_ask_case`, `resolve_ask_case`, `accept_promise_case`, `resolve_promise_case`, `publish_draft_blocker_case`, `mark_blocker_case`, `resolve_blocker_case`, `remind_coordination_item_case`, `update_coordination_item_case`), their DI registrations, and `api/controllers/graphql/mutation/mutation_coordination_item.dart`;
- the `AttentionIntentCase` methods with no surviving caller: `needsMe`, `staleReminder`, `blockerChanged`, `commitmentChanged`, and the `commitmentRedirected` / `blockerOpened` branches of `AttentionPolicy._requiresAction`;
- the client `features/coordination_item/` feature, including `coordination_item_overflow_menu.dart:276` → `item_actions_cubit.dart:136` → `remindItem`, which is the only live wire into `staleReminder`;
- the glossary entry for **Plan (coordination item)** in `CONTEXT.md` §Language, which still describes it as a live structured object on an Items tab.

**Sequencing constraint: the NOW line is currently implemented on this substrate.** Editing NOW runs client `room_cubit.updatePlan` (`beacon_threads/ui/bloc/room_cubit.dart:738`) → `beacon_threads_case.dart:315` → `CoordinationItemCase.updatePlan` (`features/coordination_item/domain/use_case/coordination_item_case.dart:203`) → server `UpdatePlanCase`, which calls `publishRootPlan(..., syncCurrentLineText: trimmed)` and emits `coordinationChanged` (`update_plan_case.dart:65-82`). So NOW is a root `kindPlan` coordination item whose text is synced onto `BeaconRoomState`. Conceptually distinct, mechanically not separable as written.

Removal therefore proceeds in two steps, in this order:

1. **Re-seat the NOW line** directly on `BeaconRoomState` with its own mutation and use case, retiring `UpdatePlanCase`, `publishRootPlan`, and the client `updatePlan` chain. Decide whether NOW edits keep emitting `coordinationChanged` receipts or gain their own event type.
2. **Only then** remove the use cases, mutation and client feature listed above.

Reversing this order breaks a live product surface. `add_plan_step_case.dart` and the rest of the plan-step family have no surviving product surface and go in step 2.

Persisted kind codes are never renumbered (`DiscussionProductPolicy`), and existing rows are left in place. Step 2 is a code and surface removal; step 1 is a data-path change and needs its own migration decision for existing root plan rows.

## 5. Migration and test blast radius

**Integration.** `offerHelpFromInbox` and `openRequestFromInbox` (`integration_test/support/e2e_test_helpers.dart:588-638`) navigate to `kPathInbox` and expect Needs-me cards in the body. Nine lifecycle specs consume them: `request_lifecycle_closed_to_archive_test.dart:52`, `request_threads_navigation_test.dart:79`, `tab_attention_forced_background_test.dart:52`, `request_lifecycle_offer_admit_chat_test.dart:40`, `request_detail_back_navigation_web_test.dart:39`, `witness_admission_forward_band_test.dart:39`, `request_lifecycle_close_review_test.dart:31`, `request_lifecycle_review_trust_control_test.dart:20`, `request_lifecycle_create_forward_inbox_test.dart:31`. The helpers gain a `goToInboxTriage()` step rather than each spec being rewritten.

**Unit / widget.** `inbox_expanded_chrome_test.dart` (3 × `find.byType(TenturaPrimaryTabBar)`), `home_tab_branch_routing_test.dart:324-337`, `home_tab_reselect_cubit_test.dart` (2 cases), `inbox_receipts_fold_test.dart:146-153`.

**Also affected, by section:**

- §4.5 of the architecture (tombstones move into the feed) — `inbox_case_test.dart:100-109` (`dismissTombstone`); decide whether dismissal stays on `InboxCubit`.
- §5 of the architecture (prompt pinning) — `updates_feed_cubit_test.dart`: the cubit has no prompt handling today, so this is new coverage, not a fix. `invite_accepted_receipt_card_test.dart`: the card's lazy `_PromptLoadPhase.loading` contract (`invite_accepted_receipt_card.dart:80-90`) is replaced by §2.4's shared projection — a deliberate change to the card's data path, with its presentation untouched.
- §8 of the architecture (My Work gains obligations and review-window scope) — `my_work_load_review_windows_test.dart:50-61` asserts `canCloseNow` for authored Requests only, and the ~17 `my_work_*_test.dart` files carry no obligation coverage at all. 
- §6 of the architecture (Activity badge becomes a triage count) — `inbox_navbar_item.dart` renders the badge and is inside the `shell_counters` contract bucket (`realtime_entity_contract_impacts_test.dart:107-111`) alongside `inbox_receipts_tab_label.dart`.

**Contracts.** The `updates-unread-count-$unread` semantics identifier (`inbox_receipts_tab_label.dart:25`) is pinned by `realtime_entity_contract_impacts_test.dart:108-116` and must be re-homed, not deleted. Note also that the `updates-needs-you` tab id (`updates_feed_pane.dart:156`) and `AttentionView.needsYou` leave the Activity feed with **no** pinning test covering the 3-tab → 2-tab change — an absence of coverage rather than a breakage, but one this plan closes.


---

## 6. Frozen contracts (do not rename)

Names an executor must use verbatim. Where a name is *chosen* here rather than
existing, that is marked **new**.

### 6.1 Migrations

Next free numbers are **m0164** onward (`m0163a` is the highest present;
register each in `_migrations.dart` — `part` line near `:167-169` and the
ordered list near `:333`).

| id | purpose | unit |
|---|---|---|
| `m0164` | add settlement columns to the outbox change-detection tuple | 03 |
| `m0165` | admit `expired` in `notification_outbox__settlement_kind_chk` | 20 |
| `m0166` | prompt-state change notification trigger | 11 |

`m0163a` shows suffixed ids are acceptable if a number is taken by an
in-flight branch. Never renumber a landed migration.

### 6.2 Server GraphQL (V2, additive)

| field | shape | unit |
|---|---|---|
| `liveObligationBeacons` **new** | `[String!]!` — authorized beacon ids where the viewer holds `requires_action AND settlement_kind IS NULL` | 01 |
| `invitePromptStates` **new** | `[InviteSeedPromptState!]!` for a set of subject ids, under the prompt endpoint's own authorization | 10 |

Both are **camelCase**, matching `custom_types.dart`. Neither is a Hasura
table permission: `notification_outbox` is not registered in Hasura and must
not be.

### 6.3 Settlement kinds

Existing: `resolved`, `dismissed`, `superseded`, `legacy_archived`
(`m0118.dart:15-18`). Added: **`expired`**. Meaning is fixed by §2.3 — do not
reuse `dismissed` for an expiry.

### 6.4 Client identifiers

| name | value | unit |
|---|---|---|
| branch label key | existing l10n key `inbox`, value becomes `Activity` / «Активность» | 19 |
| route path | `kPathInbox` stays `/home/inbox` (`consts.dart:37`) | — |
| triage route path **new** | `$kPathInbox/triage` | 14 |
| watching route path **new** | `$kPathInbox/watching` | 17 |
| `kInboxTabReceipts` | retained for deep-link compatibility only (`consts.dart:63`) | — |

**Test-id convention is mixed in this repo** — `inbox.offer_help` uses dots
(`test_ids.dart:21`), `updates-receipt-$id` uses dashes (`:31`). Do not pick
one at random: new Activity ids follow the **dashed** form, matching the feed
they live in (`activity-triage-row`, `activity-prompt-pin-$receiptId`,
`activity-prompt-collapsed`), and new My Work ids follow the **dotted** form
of their neighbours.

### 6.5 Terms

User-facing **Activity**; internal identifiers stay `inbox`. User-facing
**Request** remains internal **Beacon**. No parallel `Activity` entity, table
or route family.

## 7. Executor contract

1. Units in manifest order. Complete one unit, run its Verify block, append the
   journal entry, make one focused commit, then the next.
2. Preserve pre-existing modified and untracked files. Stage explicit paths only.
3. Create `docs/plans/inbox-activity-ia-implementation-journal.md` in UNIT 00.
4. If live code contradicts a frozen contract, **stop that unit** and record
   `BLOCKED` with the contradicting evidence. Do not adapt the contract silently.
5. Run codegen after GraphQL / Freezed / Drift / AutoRoute / Injectable / `.arb`
   changes; never hand-edit generated output. A unit touching routes, Freezed
   states, `.arb` copy or DI **must** run the matching generator inside its own
   Verify block, before its tests — a stale `*.gr.dart` / `*.freezed.dart` /
   `di.config.dart` fails in a way that looks like a test bug.
6. **Every line of a Verify block runs from the repository root, as its own
   command.** They are a checklist, not a shell script.
7. Do not "fix" a failing assertion by editing the expectation. Record whether
   it is a genuine regression or an assertion that encoded the old behaviour.
8. **UNIT 09 is a hard gate.** Do not start it until UNIT 08 is `complete` and
   its acceptance is recorded in the journal. Shipping 09 early strands
   obligations that fall outside My Work's two existing sets — the failure the
   whole sequence exists to prevent.
9. **UNIT 23 gates UNIT 24.** Removing the coordination-item feature before the
   NOW line is re-seated breaks a live product surface.
10. Units 01–08 land behind the activation gate of UNIT 04 and must produce **no
    visible change**. If a unit in that range changes what a user sees, it is
    wrong.

Journal entry template:

```markdown
## UNIT <id> — <complete|partial|blocked> — <ISO date>
COMMITS: <hash and subject, or none>
TESTS: <exact command and outcome>
FILES: <paths>
FINDINGS: <live facts that differed from the plan, or none>
DECISIONS: <anything this unit resolved that §6 did not fix>
REMAINING: <specific work, or none>
```

## 8. Unit manifest

| Unit | Purpose | Ref | Depends on | Suggested commit |
|---|---|---|---|---|
| 00 | Journal and baseline | — | — | `docs: start inbox-activity implementation journal` |
| 01 | Server: `liveObligationBeacons` | §2.1 | 00 | `feat(server): expose live obligation beacon ids` |
| 02 | Client: consume the obligation set | §2.1 | 01 | `feat(client): fetch live obligation beacons` |
| 03 | Server: settlement change notification — m0164 | §2.2 | 00 | `fix(server): notify on settlement-only outbox updates` |
| 04 | Client: My Work third input, one card per Beacon, activation gate | §3.1–3.2 | 02 | `feat(client): admit obligation-backed requests to my work` |
| 05 | Client: archive membership sources | §3.4 | 04 | `fix(client): archive revokes a source, not the row` |
| 06 | Client: My Work refresh triggers | §3.3 | 03, 04 | `feat(client): refresh my work on obligation changes` |
| 07 | Client: per-destination feed sessions | arch §7 | 00 | `refactor(client): scope feed view state per destination` |
| 08 | Client: My Work obligation view and settlement actions | §1 step 3 | 05, 06, 07 | `feat(client): needs-you view in my work` |
| 09 | **Gate:** remove Needs you from Activity, flip the gate | §1 step 4 | 08 | `feat(client): move needs-you out of activity` |
| 10 | Server: prompt-state projection with own authorization | §2.4 | 00 | `feat(server): expose authorized invite prompt states` |
| 11 | Server: prompt invalidation in-transaction — m0166 | §2.4 | 10 | `fix(server): emit prompt invalidation atomically` |
| 12 | Client: tri-state prompt projection | §2.4, arch §4.8 | 10, 11 | `feat(client): shared tri-state prompt projection` |
| 13 | Client: Activity body — TabBar out, feed in | arch §4.1–4.2 | 09, 12 | `feat(client): make the feed the activity body` |
| 14 | Client: triage row and triage route | arch §4.3 | 13 | `feat(client): activity triage summary and route` |
| 15 | Client: pinned prompts and collapsed row | arch §5 | 12, 13 | `feat(client): pin fresh invite prompts` |
| 16 | Client: resolved section into the feed scroll | arch §4.5 | 13 | `feat(client): fold resolved requests into the feed` |
| 17 | Client: Watching and Rejected entries, forward intent | arch §4.7, §7 | 13 | `feat(client): reach watching from the activity overflow` |
| 18 | Client: Activity badge | arch §6 | 14 | `feat(client): badge activity by pending triage` |
| 19 | Client: rename to Activity | arch §9 | 13–18 | `feat(client): rename the inbox branch to activity` |
| 20 | Server: `expired` kind — m0165, parser | §2.3 | 00 | `feat(server): add the expired settlement kind` |
| 21 | Server: expiry writer, backfill, reopen | §2.3 | 20 | `feat(server): settle review obligations on window close` |
| 22 | Client: My Work obligation badge | §2.5 | 21, 08 | `feat(client): badge my work by live obligations` |
| 23 | Re-seat the NOW line on `BeaconRoomState` | §4 step 1 | 00 | `refactor: move the now line off coordination items` |
| 24 | Remove retired coordination machinery | §4 step 2 | 23 | `chore: remove retired ask/blocker/promise/plan code` |
| 25 | Version bump, terminology, acceptance | arch §9 | all | `chore(client): release activity branch` |

Parallelizable: {01, 03, 07, 10, 20, 23} may start together after 00.
{13–18} are serial on 13. Everything else follows the depends-on column.

---

## UNIT 00 — Journal and baseline

**Owns:**

```text
docs/plans/inbox-activity-ia-implementation-journal.md   new
```

1. Create the journal with a baseline entry: current `git rev-parse --short HEAD`,
   the two plan documents' revisions, and `flutter --version` / `dart --version`.
2. Record the pre-existing modified and untracked files so a later unit can tell
   its own changes from the working tree it inherited.

**Verify:**

```bash
git -C . status --short
```

**Acceptance:** journal exists with a baseline entry. No code touched.

---

## UNIT 01 — Server: `liveObligationBeacons`

Implements §2.1.

**Owns:**

```text
packages/server/lib/data/repository/attention_repository.dart          edit
packages/server/lib/domain/port/attention_repository_port.dart         edit
packages/server/lib/domain/use_case/attention_case.dart                edit
packages/server/lib/api/controllers/graphql/query/query_attention.dart edit
packages/server/lib/api/controllers/graphql/custom_types.dart          edit
packages/server/test/data/repository/attention_live_obligations_pg_test.dart  new
```

1. Add `liveObligationBeacons({required String accountId})` to the repository,
   returning distinct `beacon_id` values. Reuse the **authorized** CTE that
   `unreadForBeacons` uses (`attention_repository.dart:24-48`) — do not write a
   second authorization path; the two must not be able to diverge. Filter
   `requires_action AND settlement_kind IS NULL`. No `seen_at` condition: seen is
   not settled.
2. Thread it through the port and use case following the `unreadForBeacons`
   shape exactly.
3. Expose `liveObligationBeacons: [String!]!` on the attention query type.
4. Tests (`@Tags(['pg'])`): a live obligation appears; a settled one does not; a
   seen-but-unsettled one **does**; a receipt the viewer is not authorized for
   does not; two receipts on one Beacon yield **one** id.

**Verify:**

```bash
cd packages/server && dart run build_runner build -d
cd packages/server && dart test -t pg -j 1 test/data/repository/attention_live_obligations_pg_test.dart
./scripts/check-custom-lints.sh packages/server
```

**Acceptance:** the query returns the authorized live-obligation beacon id set.
Nothing consumes it yet.

---

## UNIT 02 — Client: consume the obligation set

Implements §2.1, client half.

**Owns:**

```text
packages/client/lib/features/attention/data/gql/attention_live_obligations.graphql  new
packages/client/lib/domain/attention/port/attention_repository_port.dart            edit
packages/client/lib/domain/attention/attention_case.dart                            edit
packages/client/test/domain/attention/attention_live_obligations_test.dart          new
```

1. Add the query document and run codegen.
2. Add `liveObligationBeacons()` to the port and `AttentionCase`, mirroring
   `unreadForBeacons` including its batching (`_maxIdsPerRequest`) if the call
   shape needs it.
3. Unit tests against a mocked port: empty, populated, error propagates rather
   than being swallowed into an empty set — an unavailable set must be
   distinguishable from an empty one (architecture §4.8).

**Verify:**

```bash
cd packages/client && dart run build_runner build -d
cd packages/client && flutter test test/domain/attention/attention_live_obligations_test.dart
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** the client can fetch the set and tell "empty" from "unknown".

---

## UNIT 03 — Server: settlement change notification (m0164)

Implements §2.2.

**Owns:**

```text
packages/server/lib/data/database/migration/m0164.dart        new
packages/server/lib/data/database/migration/_migrations.dart  edit
packages/server/test/data/database/settlement_notify_pg_test.dart  new
```

1. Read `m0116.dart:48-76`. The change-detection tuple compares `read_at` and
   `seen_at` and omits the settlement columns, so a settlement-only `UPDATE`
   emits nothing.
2. `m0164` replaces that comparison so it also covers `settlement_kind`,
   `settled_at`, `settled_by_user_id` and `settled_by_occurrence_id`. Change the
   comparison only — do not alter which rows are notified or the payload shape.
3. Tests (`@Tags(['pg'])`): a settlement-only update with `seen_at` and `read_at`
   unchanged produces a notification; an unrelated no-op update still produces
   none.

**Verify:**

```bash
cd packages/server && dart run build_runner build -d
cd packages/server && dart test -t pg -j 1 test/data/database/settlement_notify_pg_test.dart
./scripts/check-custom-lints.sh packages/server
```

**Acceptance:** "Mark done" on one device is observable on another. No client
change yet.

---

## UNIT 04 — Client: My Work third input, one card per Beacon, activation gate

Implements §3.1–3.2.

**Owns:**

```text
packages/client/lib/features/my_work/data/repository/my_work_repository.dart   edit
packages/client/lib/features/my_work/domain/use_case/my_work_case.dart         edit
packages/client/lib/features/my_work/domain/derive_my_work_cards.dart          edit
packages/client/lib/features/my_work/domain/entity/my_work_card_view_model.dart edit
packages/client/lib/features/my_work/ui/bloc/my_work_cubit.dart                edit
packages/client/test/features/my_work/my_work_obligation_membership_test.dart  new
```

1. Add an **activation gate** — a single compile-time or DI-provided boolean,
   default off, named `kMyWorkObligationsEnabled`. Everything in units 04–08
   reads it. With it off the behaviour must be byte-identical to today.
2. Add the obligation beacon-id set as a third input alongside
   `authoredNonArchived` and `helpOfferedNonArchived`
   (`my_work_fetch.graphql:6-23`, repository `:41-54`, case `:114-124`).
   An obligation-only Request needs its own Beacon fetch: it may be archived or
   carry no active offer, so neither existing query returns it.
3. **Membership becomes a set of sources**, not a flag. Give the card view model
   the sources it holds (`authored`, `helpOffered`, `obligation`).
   `derive_my_work_cards.dart:199-212` must emit **exactly one card per Beacon**
   whatever combination of sources applies — this is the merge that
   `:207` already performs by Beacon identity, extended to a third input.
4. Obligation-backed cards pass the default active filter
   (`derive_my_work_cards.dart:224`), which today rejects archived kinds.
5. Tests: one Beacon with two obligation receipts yields one card; a Beacon that
   is both authored and obligation-backed yields one card with both sources; an
   obligation-only archived Beacon appears under the default filter; with the
   gate off none of the above changes anything.

**Verify:**

```bash
cd packages/client && dart run build_runner build -d
cd packages/client && flutter test test/features/my_work/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** with the gate on, obligation-backed Requests appear once each.
With it off, nothing changed.

---

## UNIT 05 — Client: archive revokes a source, not the row

Implements §3.4.

**Owns:**

```text
packages/client/lib/features/my_work/ui/bloc/my_work_cubit.dart                 edit
packages/client/lib/features/my_work/domain/entity/my_work_card_view_model.dart edit
packages/client/lib/features/my_work/ui/widget/my_work_cards.dart               edit
packages/client/test/features/my_work/my_work_archive_membership_test.dart      new
```

1. `archiveBeacon` (`my_work_cubit.dart:226-233`) unconditionally calls
   `_removeBeaconFromState` (`:229`) and increments `archivedCountHint` (`:232`).
   Change it to revoke the **authored / help-offered** sources only. If the
   obligation source remains, the card stays.
2. `isArchived` derives solely from archived card kinds
   (`my_work_card_view_model.dart:85`). Track the viewer's archive state as its
   own field, independent of kind, so a card can be archived *and*
   obligation-backed at once.
3. The Archive affordance (`my_work_cards.dart:194`) and `archivedCountHint` are
   **idempotent**: archiving an already-archived Request neither offers the
   action again nor increments the hint again.
4. Tests: archive an obligation-backed Request — the card stays, marked archived;
   archive it twice — the hint increments once; settle the last obligation on an
   archived Request — the card leaves; reload reproduces each state.

**Verify:**

```bash
cd packages/client && flutter test test/features/my_work/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** archiving never removes a Request that a live obligation keeps
in scope, immediately or after reload.

---

## UNIT 06 — Client: My Work refresh triggers

Implements §3.3.

**Owns:**

```text
packages/client/lib/features/my_work/ui/bloc/my_work_cubit.dart              edit
packages/client/test/features/my_work/my_work_refresh_triggers_test.dart     new
```

1. The obligation set changes on **arrival, settlement, expiry, and
   authorization change**. My Work subscribes to none of these today
   (`my_work_cubit.dart:24`).
2. Arrival, settlement and expiry arrive over the attention notification path
   that UNIT 03 made complete. Subscribe and re-fetch the obligation set.
3. **Authorization change is the one with no receipt change.** Unblocking an
   author re-authorizes an existing obligation. `BlockRepository.unblock` emits a
   block-domain event (`block_repository.dart:51`) that `AttentionCase` already
   listens to (`attention_case.dart:101`) and My Work does not. Subscribe to it.
   Both directions: block drops the Request from scope, unblock restores it.
4. Tests, on a mounted cubit with no reconnect: settlement removes the card;
   block removes it; unblock restores it; settlement columns are untouched
   throughout.

**Verify:**

```bash
cd packages/client && flutter test test/features/my_work/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** a mounted My Work converges on all four change kinds without a
restart.

---

## UNIT 07 — Client: per-destination feed sessions

Implements architecture §7. Independent of 01–06; may run in parallel.

**Owns:**

```text
packages/client/lib/domain/attention/attention_case.dart                 edit
packages/client/lib/features/updates/ui/bloc/updates_feed_cubit.dart     edit
packages/client/test/features/updates/updates_feed_session_test.dart     new
```

1. `AttentionCase` is a singleton holding one `activeView` and one `_search`
   (`attention_case.dart:39,117`), and every `UpdatesFeedCubit` adopts that
   shared view (`updates_feed_cubit.dart:29`). Mounting the feed in a second
   destination would couple them.
2. Split by lifetime, not by widget: **receipts, acknowledgement and summary stay
   account-wide** on `AttentionCase`; **view selection, search text, page and
   cursor move to the cubit**, keyed by a destination id passed at construction.
3. Tests: two cubits with different destination ids hold independent view and
   search; both observe the same receipt list and the same unread total; a
   round trip A → B → A restores A's view and search.

**Verify:**

```bash
cd packages/client && flutter test test/features/updates/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** two feeds coexist without overwriting each other. Only one is
mounted so far, so nothing visible changes.

---

## UNIT 08 — Client: the Needs-you view in My Work

Implements §1 step 3. **The gate that UNIT 09 waits on.**

**Owns:**

```text
packages/client/lib/features/my_work/ui/widget/my_work_obligations_pane.dart  new
packages/client/lib/features/my_work/ui/screen/my_work_screen.dart            edit
packages/client/lib/ui/test_ids.dart                                          edit
packages/client/test/features/my_work/my_work_obligations_pane_test.dart      new
```

1. Mount a Needs-you view inside My Work, behind the UNIT 04 gate, using the
   per-destination session of UNIT 07 with its own destination id. It is backed
   by `AttentionView.needsYou`, which keeps its meaning.
2. Carry the **settlement actions** onto it. An obligation must be dischargeable
   where it now lives; a read-only list does not satisfy this unit.
3. Test ids follow the dotted My Work convention (§6.4).
4. Tests: the view lists live obligations; settling one removes it and leaves the
   Beacon's card if another source holds it; with the gate off the view is not
   mounted at all.

**Verify:**

```bash
cd packages/client && flutter test test/features/my_work/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** with the gate on, a user can see and discharge every obligation
in My Work — everything they can do in Activity's Needs-you view today. Record
that comparison explicitly in the journal; UNIT 09 depends on it.

---

## UNIT 09 — Gate: remove Needs you from Activity

Implements §1 step 4. **Do not start until UNIT 08 is `complete` in the journal.**

**Owns:**

```text
packages/client/lib/features/updates/ui/widget/updates_feed_pane.dart      edit
packages/client/lib/domain/attention/entity/attention_feed.dart            edit
packages/client/test/features/updates/updates_feed_views_test.dart         edit
```

1. Flip the UNIT 04 gate on by default.
2. Remove the `Needs you` tab from the Activity feed's view control
   (`updates_feed_pane.dart:135`, ids at `:155-157`). `AttentionView.needsYou`
   itself stays — My Work uses it.
3. The `updates-needs-you` id leaves the Activity feed with no pinning test
   covering the three-tab → two-tab change. Add one now rather than noting the
   gap.
4. Tests: Activity shows All / Unread only; My Work shows Needs you; the unread
   total is unchanged by the move.

**Verify:**

```bash
cd packages/client && flutter test test/features/updates/ test/features/my_work/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** obligations live in exactly one place, and it is My Work.

---

## UNIT 10 — Server: authorized prompt-state projection

Implements §2.4.

**Owns:**

```text
packages/server/lib/data/repository/invite_seed_prompt_repository.dart       edit
packages/server/lib/domain/use_case/invite_seed_attestation_case.dart        edit
packages/server/lib/api/controllers/graphql/query/query_capability.dart      edit
packages/server/lib/api/controllers/graphql/custom_types.dart                edit
packages/server/test/domain/use_case/invite_prompt_projection_pg_test.dart   new
```

1. Add a batch read returning prompt states for a set of subject ids.
2. **Authorization is not inherited from the receipt.** The current prompt read
   checks blocked pairs, direct-inviter status and prompt ownership
   (`invite_seed_attestation_case.dart:125`), whereas a receipt's `profile`
   access policy checks only presentation shape (`m0117.dart:46`). Carry the
   prompt endpoint's own predicate into the projection. A blocked pair must get
   the **history receipt** and **no actionable prompt state**.
3. Expose `invitePromptStates` per §6.2.
4. Tests (`@Tags(['pg'])`): batch returns states for authorized subjects;
   a blocked pair yields no state while the receipt remains readable;
   an unknown subject yields absence, not an error.

**Verify:**

```bash
cd packages/server && dart run build_runner build -d
cd packages/server && dart test -t pg -j 1 test/domain/use_case/invite_prompt_projection_pg_test.dart
./scripts/check-custom-lints.sh packages/server
```

**Acceptance:** prompt state is fetchable in batch, under its own authorization.

---

## UNIT 11 — Server: prompt invalidation, atomically (m0166)

Implements §2.4.

**Owns:**

```text
packages/server/lib/data/database/migration/m0166.dart                    new
packages/server/lib/data/database/migration/_migrations.dart              edit
packages/server/lib/domain/use_case/invite_seed_attestation_case.dart     edit
packages/server/test/domain/use_case/invite_prompt_invalidation_pg_test.dart  new
```

1. `answer` is wrapped in a transaction (`invite_seed_attestation_case.dart:70-82`);
   `skip` is a standalone write (`:86-95`). Both must emit a recipient-targeted
   invalidation **inside the same transaction as the write**, using the existing
   transactional realtime mechanism. A post-write emission leaves a window where
   the state commits, the emission fails, and another connected device stays
   stale with no later event that would correct it.
2. Tests (`@Tags(['pg'])`): rollback leaves neither the state change nor an
   emission; a committed `skip` is observable on a second connected client with
   no refetch trigger of its own; the same for `answer`.

**Verify:**

```bash
cd packages/server && dart run build_runner build -d
cd packages/server && dart test -t pg -j 1 test/domain/use_case/invite_prompt_invalidation_pg_test.dart
./scripts/check-custom-lints.sh packages/server
```

**Acceptance:** settling a prompt cannot commit without its invalidation.

---

## UNIT 12 — Client: tri-state prompt projection

Implements §2.4 and architecture §4.8.

**Owns:**

```text
packages/client/lib/features/updates/domain/use_case/invite_accepted_setup_case.dart  edit
packages/client/lib/features/updates/domain/entity/prompt_projection.dart             new
packages/client/lib/features/updates/ui/bloc/updates_feed_cubit.dart                  edit
packages/client/lib/features/updates/ui/widget/invite_accepted_receipt_card.dart      edit
packages/client/test/features/updates/prompt_projection_test.dart                     new
```

1. Add `fetchPrompts(Set<String> subjectIds)` to `InviteAcceptedSetupPort`
   alongside the existing per-subject `fetchPrompt` (`:13`), backed by UNIT 10.
2. Introduce a projection with three states — **unknown / known / failed** — held
   by the feed cubit and consumed by **both** placement and the card. The card
   currently refetches only on receipt id or payload change (`:68-77`) and its
   action reads a locally cached `_promptState` (`:123`); point both at the
   shared projection so a row cannot be demoted while its mounted action offers
   a stale choice.
3. Subscribe to UNIT 11's invalidation and refetch the affected subjects.
4. The feed never waits on this: it renders from receipts alone, prompt rows in
   chronological position, and only *known* states become pinning candidates
   (UNIT 15). Never render a prompt as **not pending** because its state is
   unknown.
5. Tests: feed renders fully with the prompt fetch failing; a known state
   promotes placement; `skip` elsewhere converges an already-mounted,
   already-seen receipt's placement **and** its available action with no
   restart; unknown never reads as settled.

**Verify:**

```bash
cd packages/client && dart run build_runner build -d
cd packages/client && flutter test test/features/updates/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** the convergence case of architecture §5 passes, and a failed
prompt fetch costs nothing but pinning.

---

## UNIT 13 — Client: the feed becomes the Activity body

Implements architecture §4.1–4.2.

**Owns:**

```text
packages/client/lib/features/inbox/ui/screen/inbox_screen.dart   edit
packages/client/test/features/inbox/inbox_expanded_chrome_test.dart  edit
packages/client/test/features/inbox/inbox_receipts_fold_test.dart    edit
```

1. Remove the `TenturaPrimaryTabBar` and the three-way `TabBarView`
   (`inbox_screen.dart:411-417` and the bodies around `:176-236`). The branch
   body becomes `UpdatesFeedPane`.
2. Re-point, do not delete, the keep-alive and page-storage machinery
   (`:369`); feed views own their scroll keys (`updates_feed_pane.dart:177-178`).
3. `InboxSort` (`:424`) leaves the branch root — it belongs to the triage route
   (UNIT 14) and to Watching (UNIT 17). Do not drop it.
4. Deep links keep working unchanged: `/home/updates` → `/home/inbox?tab=receipts`
   (`root_router.dart:177-182`) and notification intents (`:553`) now land on the
   feed, which is what they always meant.
5. Update the three `find.byType(TenturaPrimaryTabBar)` assertions rather than
   deleting them — assert the tab bar is **gone**.

**Verify:**

```bash
cd packages/client && flutter test test/features/inbox/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** opening the branch shows the feed. Triage and Watching are
temporarily unreachable — UNITs 14 and 17 restore them, and this is the one
window in the sequence where a surface is missing. Do not release from here.

---

## UNIT 14 — Client: triage row and triage route

Implements architecture §4.3.

**Owns:**

```text
packages/client/lib/features/inbox/ui/widget/inbox_triage_row.dart   new
packages/client/lib/features/inbox/ui/screen/inbox_triage_screen.dart new
packages/client/lib/app/router/root_router.dart                       edit
packages/client/lib/consts.dart                                       edit
packages/client/lib/ui/test_ids.dart                                  edit
packages/client/test/features/inbox/inbox_triage_row_test.dart        new
```

1. A **fixed-height row above the feed**, never a scroll region:
   0 pending → absent; 1 → the Request title on one ellipsized line;
   2+ → `N requests need your response` with stacked avatars.
2. **Tapping always opens the triage route**, at every count. The route carries
   the Needs-me list with full card affordances — Offer help, Forward, Watch,
   Dismiss — the `InboxSort` cycle, and scroll restoration.
3. Both dismissal paths must exist on the triage card, with their existing copy
   (`rejection_dialog.dart:72-89`). They differ only in wording today (see the
   architecture §13 and issue #137) but the copy difference is load-bearing for
   the user and must not be collapsed here.
4. Route path per §6.4; test ids dashed per §6.4.
5. Tests: row absent at 0; shows the title at 1; shows the count at 2+; tap opens
   triage at every count; text scale 1.3 keeps the row single-line and bounded.

**Verify:**

```bash
cd packages/client && dart run build_runner build -d
cd packages/client && flutter test test/features/inbox/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** triage is reachable and bounded; no card renders inline.

---

## UNIT 15 — Client: pinned prompts and the collapsed row

Implements architecture §5, §5.5.1.

**Owns:**

```text
packages/client/lib/features/updates/ui/widget/updates_feed_pane.dart       edit
packages/client/lib/features/updates/ui/widget/prompt_batch_sheet.dart      new
packages/client/lib/ui/test_ids.dart                                        edit
packages/client/test/features/updates/prompt_pinning_test.dart              new
```

1. Sliver order inside the feed scroll is fixed: **pinned prompts → resolved
   tombstones → chronological day groups**.
2. **The two modes are exclusive.** One or two fresh pending prompts render as
   pinned rows. **Three or more render as a single collapsed row instead** —
   `N people joined via your invites — set up access`, `N` counting *all* fresh
   pending prompts — opening a batch sheet. Never pins alongside a collapsed row.
3. Ordering: `(receipt.createdAt DESC, receipt.id DESC)`, the same tiebreak the
   feed uses (`attention_repository.dart:118`).
4. Freshness: `pending` and younger than 7 days by `receipt.createdAt`,
   evaluated **when the feed is built and on app resume** — not on a timer.
5. A pinned prompt is **lifted out** of its chronological position, not
   duplicated. Settling or ageing reinserts it.
6. Only *known* projection states are candidates (UNIT 12).
7. Tests: 1 → one pin; 2 → two pins; 3 → collapsed row `N = 3`, zero pins;
   the 2↔3 boundary flips modes; equal timestamps order deterministically;
   an unknown-state prompt stays chronological; a settled prompt reinserts.

**Verify:**

```bash
cd packages/client && flutter test test/features/updates/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** the mode switch, the ordering and the lift-out all behave as
specified, including at the boundary.

---

## UNIT 16 — Client: resolved section into the feed scroll

Implements architecture §4.5.

**Owns:**

```text
packages/client/lib/features/inbox/ui/widget/inbox_tombstone_card.dart   edit
packages/client/lib/features/updates/ui/widget/updates_feed_pane.dart    edit
packages/client/test/features/inbox/inbox_case_test.dart                 edit
```

1. Move the 24h resolved/tombstone section (`inbox_screen.dart:671-732`,
   `inbox_state.dart:32-52`) into the feed scroll as the **second sliver**, on
   the **All view only**, **collapsed by default** and expanding on tap.
2. It must not join the fixed chrome: at ~180–230dp a card it is unbounded.
3. Dismissal rules and the 24h window are unchanged. Decide and record whether
   dismissal stays on `InboxCubit` — `inbox_case_test.dart:100-109` covers it.
4. It renders independently of the pending count (architecture §4.8).

**Verify:**

```bash
cd packages/client && flutter test test/features/inbox/ test/features/updates/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** resolved Requests remain explainable without costing first-screen
space.

---

## UNIT 17 — Client: Watching and Rejected, and the forward intent

Implements architecture §4.7 and §7.

**Owns:**

```text
packages/client/lib/features/inbox/ui/screen/inbox_watching_screen.dart  new
packages/client/lib/features/inbox/ui/screen/inbox_screen.dart           edit
packages/client/lib/features/forward/ui/message/forward_messages.dart    edit
packages/client/lib/app/router/root_router.dart                          edit
packages/client/lib/consts.dart                                          edit
packages/client/test/features/inbox/inbox_watching_route_test.dart       new
```

1. Watching becomes a pushed route reached from the branch overflow, **carrying a
   count**, alongside Rejected (whose restore operation is preserved,
   `inbox_rejected_screen.dart:97`). Each row keeps Stop watching, Forward,
   Dismiss and Offer help (`inbox_screen.dart:839-859`).
2. **The collection is derived from Inbox rows, never from receipts** — that is
   what keeps preference-muted Requests listed.
3. Authorization loss **does** remove an entry: `InboxFetch` filters by
   `beacon: {can_read_content: {_eq: true}}` (`inbox_fetch.graphql:6`). This is
   intended; do not add a restricted projection to keep showing metadata after
   access is gone.
4. **Re-point the forward-success intent.** `requestInboxWatching(beaconId)`
   (`forward_messages.dart:145-152`) currently animates to the Watching *tab*
   (`inbox_screen.dart:84-94,119-124`), which no longer exists. It must push the
   route and scroll to the named Request. This is the feedback edge of the
   forwarding loop — a broken intent here is a broken product loop, not a detail.
5. Tests: overflow reaches Watching with a count; the forward snackbar lands on
   the named Request; a muted Request stays listed; a blocked one does not;
   `home_tab_reselect_cubit_test.dart` still passes.

**Verify:**

```bash
cd packages/client && dart run build_runner build -d
cd packages/client && flutter test test/features/inbox/ test/features/forward/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** Watching is reachable without the snackbar, and the snackbar
still works.

---

## UNIT 18 — Client: the Activity badge

Implements architecture §6.

**Owns:**

```text
packages/client/lib/features/home/ui/widget/inbox_navbar_item.dart   edit
packages/client/lib/features/home/ui/bloc/home_attention_state.dart  edit
packages/client/test/features/home/inbox_navbar_item_test.dart       new
```

1. Pending triage items > 0 → **numeric** badge with that count; else unread > 0
   → **dot**; never both.
2. Prompts never contribute, at any count or freshness.
3. Distinct accessible descriptions for the two states — "3 requests need your
   response" against "new activity". The badge is inside the `shell_counters`
   contract bucket (`realtime_entity_contract_impacts_test.dart:107-111`);
   update that contract rather than working around it.
4. The `updates-unread-count-$unread` identifier
   (`inbox_receipts_tab_label.dart:25`), pinned at
   `realtime_entity_contract_impacts_test.dart:108-116`, must be **re-homed**,
   not deleted — the tab label that carried it is gone.
5. Tests: number with pending triage; dot with unread only; nothing when both are
   zero; number wins when both are non-zero; semantics differ between states.

**Verify:**

```bash
cd packages/client && flutter test test/features/home/ test/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** one indicator, two states, and the unread signal that never
reached the icon before now does.

---

## UNIT 19 — Client: rename the branch to Activity

Implements architecture §9.

**Owns:**

```text
packages/client/l10n/app_en.arb                 edit
packages/client/l10n/app_ru.arb                 edit
CONTEXT.md                                      edit
scripts/check-user-facing-terminology.sh        edit
```

1. The nav label is the existing l10n key **`inbox`** — its *value* becomes
   `Activity` / «Активность». Do not add a key; do not rename identifiers.
2. Add **Activity** to `CONTEXT.md` §Terminology as a user-facing product noun
   whose internal name is `inbox`, in the same shape as the Request/Beacon and
   discussion/room rows.
3. Update `scripts/check-user-facing-terminology.sh` accordingly and make it pass.
4. Sweep both `.arb` files for strings that name the old branch in prose, not
   only the label.

**Verify:**

```bash
cd packages/client && flutter gen-l10n
bash scripts/check-user-facing-terminology.sh
cd packages/client && flutter test test/
```

**Acceptance:** the branch reads as Activity everywhere a user can see, and as
`inbox` everywhere else.

---

## UNIT 20 — Server: the `expired` settlement kind (m0165)

Implements §2.3, part one. **Ship and deploy this before UNIT 21.**

**Owns:**

```text
packages/server/lib/data/database/migration/m0165.dart        new
packages/server/lib/data/database/migration/_migrations.dart  edit
packages/server/lib/domain/attention/attention_models.dart    edit
packages/server/test/domain/attention/settlement_kind_test.dart  new
```

1. `m0165` extends `notification_outbox__settlement_kind_chk`
   (`m0118.dart:15-18`) to admit `expired`. Leave `settlement_facts_chk` alone.
2. `attention_models.dart:147-160` is a closed enum parsed with `firstWhere`;
   `attention_repository.dart:203-207` converts on read. **A reader that does not
   know `expired` throws.** Add the value to the enum and parser here, and write
   **no** `expired` rows in this unit.
3. Tests: the constraint accepts `expired`; the parser round-trips it; an unknown
   value still throws rather than being silently mapped.

**Verify:**

```bash
cd packages/server && dart run build_runner build -d
cd packages/server && dart test -j 1 test/domain/attention/settlement_kind_test.dart
./scripts/check-custom-lints.sh packages/server
```

**Acceptance:** the schema and every reader tolerate `expired`. Nothing writes
it. **Deploy to completion before UNIT 21** — a reader left on the old build
throws on the first row UNIT 21 writes.

---

## UNIT 21 — Server: settle review obligations on window close

Implements §2.3, part two.

**Owns:**

```text
packages/server/lib/domain/use_case/evaluation/review_finalization_case.dart  edit
packages/server/lib/domain/use_case/evaluation_case.dart                      edit
packages/server/lib/data/repository/attention_repository.dart                 edit
packages/server/test/domain/use_case/review_obligation_settlement_pg_test.dart  new
```

1. Settlement goes **inside** the existing finalization transaction:
   `task_worker_case.dart:191-199` sweeps every minute,
   `evaluation_case.dart:144-145` invokes the same sweep, and
   `attention_expiry_sweep_case.dart:33-48` → `review_finalization_case.dart:73-99`
   is the boundary.
2. Outcomes are keyed on **`beacon_review_status.status = 2`** — the finalized
   *package*, not a single submitted target. `evaluationSubmit` sets `status: 1`
   for one target (`evaluation_case.dart:1348`); only `evaluationFinalize` sets
   `status: 2` (`:1473`); window closure deletes evaluations in packages never
   sent (`evaluation_repository.dart:729`).

   | condition at close | settlement |
   |---|---|
   | package finalized (`status = 2`) | `resolved` |
   | not finalized, including submitted targets in an unsent package | `expired` |
   | review reopened (`evaluation_case.dart:445-455`) | `superseded` |

3. This is a **system** settlement path — `attention_settlement_case.dart:26-28`
   is limited to the two user-driven values. Set `settled_at` (required by
   `settlement_facts_chk`) and preserve `seen_at` / `read_at` untouched.
4. **Backfill, and it is not optional.** The sweep only visits `status = 0`
   (`attention_expiry_repository.dart:19-23`) and the finalizer stops at
   `evaluation_repository.dart:663-664`, so windows closed before this ships are
   never revisited. Under architecture §8.1 their obligations would pin their
   Requests into My Work permanently. Backfill once, in this unit.
5. Tests (`@Tags(['pg'])`): finalized → `resolved`; unsent package containing a
   submitted target → `expired`, **not** `resolved`; reopen → `superseded`;
   seen and unseen receipts both settle; backfill covers a pre-existing closed
   window; `seen_at` and `read_at` survive.

**Verify:**

```bash
cd packages/server && dart run build_runner build -d
cd packages/server && dart test -t pg -j 1 test/domain/use_case/review_obligation_settlement_pg_test.dart
./scripts/check-custom-lints.sh packages/server
```

**Acceptance:** an obligation nobody can discharge stops being counted, and no
historical window is left pinning a Request forever.

---

## UNIT 22 — Client: the My Work obligation badge

Implements §2.5.

**Owns:**

```text
packages/client/lib/features/home/ui/widget/my_work_navbar_item.dart  edit
packages/client/lib/features/home/ui/bloc/home_attention_state.dart   edit
packages/client/test/features/home/my_work_navbar_item_test.dart      new
packages/client/test/features/my_work/my_work_scope_coincidence_test.dart  new
```

1. The badge counts **authorized live obligations**, under the same
   authorization as the scope (UNIT 01). It is **not** an unseen count:
   `isSeen` and `isLiveObligation` are independent
   (`attention_receipt.dart:35`), so one already-read unsettled review would
   vanish from an unseen-based count while still being owed.
2. Implement §2.6's coincidence test here, split as that section requires:
   server-projection assertions over **one snapshot**, and mounted-client
   assertions through My Work. Include the multiplicity fixture — one Request
   with two live receipts is **two obligations and one card**; settling one
   keeps the card; settling the last removes it only if no other source remains.
3. Distinguish the two reasons a Request leaves scope. Settlement is one;
   **authorization loss** is the other (`m0162.dart:15`, `m0117.dart:39`).
   Never write a terminal settlement for an authorization loss.

**Verify:**

```bash
cd packages/client && flutter test test/features/home/ test/features/my_work/
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** the badge is accurate, decays without a janitorial gesture, and
the coincidence between scope and count is asserted rather than assumed.

---

## UNIT 23 — Re-seat the NOW line on `BeaconRoomState`

Implements §4 step 1. **Gates UNIT 24.** Independent of every other unit.

**Owns:**

```text
packages/server/lib/domain/use_case/beacon_room_case.dart                    edit
packages/server/lib/api/controllers/graphql/mutation/mutation_beacon_room.dart edit
packages/client/lib/features/beacon_threads/domain/use_case/beacon_threads_case.dart edit
packages/client/lib/features/beacon_threads/ui/bloc/room_cubit.dart          edit
packages/server/test/domain/use_case/room_now_line_pg_test.dart              new
```

1. Today NOW is a **root `kindPlan` coordination item** whose text is synced onto
   `BeaconRoomState`: `room_cubit.updatePlan` (`room_cubit.dart:738`) →
   `beacon_threads_case.dart:315` → `CoordinationItemCase.updatePlan`
   (`coordination_item_case.dart:203`) → server `UpdatePlanCase`, which calls
   `publishRootPlan(..., syncCurrentLineText:)` and emits `coordinationChanged`
   (`update_plan_case.dart:65-82`).
2. Give NOW its own mutation and use case writing `BeaconRoomState` directly.
   Retire `UpdatePlanCase`, `publishRootPlan` and the client `updatePlan` chain.
3. **Decide and record** whether NOW edits keep emitting `coordinationChanged`
   receipts or gain their own event type (architecture §11.3). Either is
   acceptable; leaving it undecided is not, because it determines what the
   Activity feed shows for a NOW change.
4. Existing root plan rows need a migration decision: this is a data-path change,
   not only code. State what happens to them.
5. Tests (`@Tags(['pg'])`): NOW round-trips without a coordination item; existing
   rows behave per the decision in step 4; the room renders NOW unchanged.

**Verify:**

```bash
cd packages/server && dart run build_runner build -d
cd packages/client && dart run build_runner build -d
cd packages/server && dart test -t pg -j 1 test/domain/use_case/room_now_line_pg_test.dart
cd packages/client && flutter test test/features/beacon_threads/
./scripts/check-custom-lints.sh packages/server
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** NOW works with no coordination-item code in its path. **Do not
start UNIT 24 until this is `complete`** — reversing the order breaks a live
surface.

---

## UNIT 24 — Remove retired coordination machinery

Implements §4 step 2. **Requires UNIT 23 `complete`.**

**Owns:**

```text
packages/server/lib/domain/use_case/coordination_item/            delete
packages/server/lib/api/controllers/graphql/mutation/mutation_coordination_item.dart  delete
packages/server/lib/domain/use_case/attention_intent_case.dart    edit
packages/server/lib/domain/attention/attention_policy.dart        edit
packages/client/lib/features/coordination_item/                   delete
CONTEXT.md                                                        edit
```

1. Ask, Blocker and Promise are in `retiredCoordinationKinds`; Plan is retired by
   product decision, leaving `supportedCoordinationKinds` empty in practice.
   Remove the use cases, their DI registrations and the mutation controller.
2. Remove the `AttentionIntentCase` methods with no surviving caller —
   `needsMe`, `staleReminder`, `blockerChanged`, `commitmentChanged` — and the
   `commitmentRedirected` / `blockerOpened` branches of
   `AttentionPolicy._requiresAction`.
3. Remove the client `features/coordination_item/`, including
   `coordination_item_overflow_menu.dart:276` → `item_actions_cubit.dart:136` →
   `remindItem`, the only live wire into `staleReminder`.
4. Remove the **Plan (coordination item)** entry from `CONTEXT.md` §Language,
   which still describes it as a live structured object on an Items tab.
5. **Persisted kind codes are never renumbered**, and existing rows stay. This is
   a code and surface removal, not a data migration.
6. Re-run server and client codegen; DI will not compile until every registration
   is gone.

**Verify:**

```bash
cd packages/server && dart run build_runner build -d
cd packages/client && dart run build_runner build -d
cd packages/server && dart test -j 1
cd packages/client && flutter test test/
./scripts/check-custom-lints.sh packages/server
./scripts/check-custom-lints.sh packages/client
```

**Acceptance:** the retired machinery is gone, NOW still works, and no test
asserts a dead path.

---

## UNIT 25 — Version bump, terminology, acceptance

**Owns:**

```text
packages/client/pubspec.yaml         edit
packages/client/web/index.html       edit
docs/plans/inbox-activity-ia-implementation-journal.md   edit
```

1. Semver bump in `packages/client/pubspec.yaml` — this is a user-visible client
   change (AGENTS.md:33).
2. **Sync the web cache-buster.** `web/index.html`'s `flutter_bootstrap.js?v=`
   must match the new version (AGENTS.md:34). Run the app once and check
   `git status` for the diff, or hand-verify. A missed bump here has previously
   made a landed fix look like it did not ship.
3. Run the integration suite. `offerHelpFromInbox` and `openRequestFromInbox`
   (`integration_test/support/e2e_test_helpers.dart:588-638`) navigate to
   `kPathInbox` and expect Needs-me cards in the body; add a `goToInboxTriage()`
   step to the helpers rather than rewriting the nine lifecycle specs
   (§5 lists them).
4. Acceptance walk, recorded in the journal:
   - the branch opens on the feed, with a chronological row visible on first
     paint at 360×640 and 1.3× text scale when the fetched page has one;
   - triage is reachable at every pending count and bounded to one row;
   - one, two and three fresh prompts produce one pin, two pins, and a collapsed
     row of three respectively;
   - obligations appear only in My Work, and can be discharged there;
   - the forward snackbar reaches the named Request in Watching;
   - Activity shows a number with pending triage and a dot with unread only.

**Verify:**

```bash
cd packages/client && flutter test test/
./scripts/run_client_integration_web_local.sh
bash scripts/check-user-facing-terminology.sh
./scripts/check-custom-lints.sh packages/client
./scripts/check-custom-lints.sh packages/server
```

**Acceptance:** the walk above passes and the journal records it.
