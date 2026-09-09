# Inbox → Activity: implementation plan

Status: implementation plan, revision 2. Companion to [`inbox-activity-ia-architecture.md`](inbox-activity-ia-architecture.md), which is the authority on *what* is being built and *why*. This document owns *what has to exist first*, *in what order*, and *what breaks*.

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
- *Invalidation.* `skip` updates only the prompt row (`invite_seed_attestation_case.dart:86`) with no notification trigger (`m0146.dart`), and the client refetches only on notification, catch-up, or block change (`attention_case.dart:95`). A join gives freshness **at fetch time**; it does not cause a fetch. A connected second device re-runs nothing. So the mutation must emit a recipient-targeted invalidation regardless of which freshness branch is chosen — the architecture's earlier "projection **or** batch + invalidation" phrasing was wrong to present invalidation as belonging to only one branch.

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

