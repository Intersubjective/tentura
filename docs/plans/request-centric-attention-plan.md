# Request-centric attention: design and implementation plan

**Baseline:** `feature/events_refac`, `feb2667a9538260fd526b3ebe470dd2f4890e302`, inspected read-only. No implementation or tests were run.

**Terminology:** user-facing Request remains internal `Beacon`; My Desk remains `my_work`; For You/Activity remains `inbox`. No new `Request` domain entity.

**Evidence notation:** `S/` = `packages/server/lib/`; `C/` = `packages/client/lib/`; `ST/` = `packages/server/test/`; `CT/` = `packages/client/test/`. All citations refer to this baseline.

The requested Updates implementation plan now lives at `docs/archive/plans/updates-tab-implementation-plan.md`; its original path is absent. It describes the predecessor’s receipt and realtime architecture, not the current implementation inventory (`docs/archive/plans/updates-tab-implementation-plan.md:26–67`).

GitHub requests for #151 and #179 failed with DNS resolution errors for `api.github.com`. Issue bodies, comments, acceptance criteria, and closure status could not be verified. This plan uses the supplied issue descriptions and inspected code.

**Execution.** The ordered manifest, frozen names, executor rules and gates live in
[`request-centric-attention-implementation-plan.md`](request-centric-attention-implementation-plan.md); §6 here is
its summary and the manifest is authoritative for order and acceptance.

**Provenance and status.** Revision 3, 2026-09-18. This is Astra's independent design (produced read-only against
this baseline) adopted as the base, with three owner decisions applied and three merges from the competing Claude
draft. History: Astra's unedited original is `request-centric-attention-astra.md`; the superseded Claude draft is
`request-centric-attention-claude-rev2.md`.

**Owner decisions (2026-09-18), overriding the base where they conflict:**

- **A. Dismiss all clears only rows that carry a ×.** It never touches anything that requires a *decision* from
  the viewer — unanswered forwards, pending prompts, and any future card of that kind. Consequence: "zero" on
  For You means *no dismissible attention left*, not *no rows* (D07, D18).
- **B. Answered-forward outcome rows stay in For You as dismissible tombstones.** The base's removal of the
  duplicate representation is deferred, not adopted: keep the row, give it a ×, revisit if it proves annoying
  in use (D01).
- **C. No obligation is resolved by a bare acknowledgment.** Every obligation CTA opens a sheet/popup that
  requires a choice or input; the `ask`-style acknowledge-only objects are gone. This confirms the base's removal
  of generic Done on stronger grounds (D04).

**Merges from the Claude draft:** M1 one shared predicate behind every list and its indicator (D09); M2
`recoverableVia` as a required contract field — dismissible implies derivable (§4.3); M3 legacy-client
compatibility is not a constraint (D19, U18).

**Folded in:** a pre-existing defect verified during this review — retention can delete live obligations today
(D17, U06).

## 1. Baseline: shipped behavior and remaining gaps

| Brief requirement | Already exists | Actual gap |
|---|---|---|
| Responsibility determines primary surface | SQL base scope includes authored non-draft Requests and active help offers. The attention query adds visible live obligations and computes surface at read time. Archive is not excluded from the base scope. `S/data/database/migration/m0168.dart:6–24`; `S/data/repository/attention_repository.dart:147–173`. | Preserve this rule. Apply it consistently to **synthetic forward outcomes**, cards, counts, and clearing operations. |
| No Request split across tabs | Receipts belonging to a responsible viewer route to My Work. Activity Request aggregates exclude responsibility scope. `S/data/repository/attention_repository.dart:163–171,457–461`. | Answered-forward SQL deliberately includes in-scope Requests and renders a “helping” outcome in Activity, although their event children are suppressed. This still duplicates the Request across primary surfaces. `S/data/repository/attention_repository.dart:255–279,346–407`; `ST/data/repository/attention_activity_stream_pg_test.dart:143,587`. |
| Coalesce Activity events onto Request cards; #151 | Activity groups Request receipts, merges children into forward rows, and creates `requestActivity` rows for Requests without a forward representative. Existing tests cover coalescing, distinct Requests, and event-driven bumping. `S/data/repository/attention_repository.dart:292–307,413–461`; `ST/data/repository/attention_activity_stream_pg_test.dart:447,493,537`. | **Do not rebuild grouping.** Change eligibility to active attention only, eliminate duplicate representatives, and replace optional-event bumping. |
| Meaningful events update the Request rather than create sibling rows | Forward rows use the later of forward time and latest child-event time; standalone Request rows use latest event time. Pinned offers use the same effective-activity calculation. `S/data/repository/attention_repository.dart:338–341,426,874–901`. | Optional events currently reorder Requests. The brief requires new obligations to bump, optional updates not to bump. |
| Obligations are distinct from optional updates | `requires_action` and independent settlement fields exist. Current policy makes author-facing `helpOfferSubmitted` and `reviewOpened` actionable; informational review events are not actionable. `S/domain/attention/attention_policy.dart:277–292`; `S/data/database/migration/m0118.dart:7–47`. | Classification is incomplete as a future-proof contract: `_requiresAction` defaults every unlisted type to false. Delivery priority and mandatory delivery are separate and must remain separate. |
| Obligation CTAs and automatic resolution | Help-offer subcards provide Respond; review subcards provide Review and deliberately omit Done. Accept/decline settles the author’s help-offer obligation; sending a review package settles the reviewer’s obligation. Review close/reopen also has settlement paths. `C/features/my_work/ui/widget/my_work_obligation_block.dart:139–151,282–305`; `S/domain/use_case/coordination_case.dart:335–361,404–427`; `S/domain/use_case/evaluation_case.dart:474,1616`; `S/data/repository/attention_system_settlement_repository.dart:18–129`. | Non-review subcards still expose generic Done. The public settlement API permits generic settlement for non-review obligations. Withdrawal and other terminal source transitions need a complete lifecycle audit; withdrawal currently updates the offer, access, Inbox state, and receipts without calling the author help-offer settlement method. `S/domain/use_case/attention_settlement_case.dart:18–45`; `S/domain/use_case/help_offer_case.dart:262–325`. |
| Optional updates require deliberate clearing | Explicit receipt seen/unseen controls, surface-scoped mark-all, and Request-scoped mark-seen already exist. `S/api/controllers/graphql/mutation/mutation_attention.dart:24–108`; `C/features/updates/ui/widget/updates_feed_tile.dart:119–150`; `C/features/inbox/ui/screen/inbox_screen.dart:261–283`. | There is **no separate cleared state**. Seen receipts remain in Activity grouping. Reading and cleaning are currently conflated. `S/data/repository/attention_repository.dart:292–305,763–824`. |
| No passive scroll clearing | Inspected feed controls acknowledge through user callbacks; subcard body tapping marks seen. No viewport-based acknowledgment was found in the inspected attention/feed paths. `C/features/updates/ui/widget/updates_feed_tile.dart:119–150`; `CT/features/inbox/activity_event_subcard_block_test.dart:101`. | Preserve this behavior with an explicit invariant test. Do not plan a nonexistent visibility-detector removal. Room read-watermark bridging does update `seen_at`, which must cease affecting primary-surface clearing. `S/data/database/migration/m0120.dart:20–34`. |
| Opening a Request clears its optional events | My Work and Activity entry points call `markSeenForBeacon`. `C/features/my_work/ui/bloc/my_work_cubit.dart:482–492`; `C/features/inbox/ui/widget/activity_stream_view.dart:840–849`; `C/features/inbox/ui/widget/activity_offer_card.dart:140`. | Current acknowledgment happens at individual entry points, sometimes before navigation succeeds, and updates every unseen visible Request receipt without an optional-event filter or arrival boundary. Centralize successful-open clearing. `S/data/repository/attention_repository.dart:1212–1233`. |
| Request and tab indicators | Surface summaries and Request attention projections exist. Activity has a dot; My Work has an obligation count or an unread dot. `S/data/repository/attention_repository.dart:70–143,176–204`; `C/features/home/ui/bloc/home_attention_state.dart:56–71`; `C/features/home/ui/widget/my_work_navbar_item.dart:22–60`. | Unread counts include obligations and settled unread receipts. My Work suppresses its dot when obligations exist; both tabs suppress dots while selected. Request shells do not provide the specified independent obligation-count-plus-optional-dot contract. |
| Full collapsible Request event list; #179 | Activity already embeds event subcards and fetches additional events. My Work already groups help-offer obligations and renders review subcards. `C/features/inbox/ui/widget/activity_event_subcard_block.dart:21–39,78–114,127–159`; `C/features/my_work/domain/group_my_work_obligations.dart:18–38`; `CT/features/my_work/my_work_obligation_subcards_test.dart:177–203`. | Activity expansion is one-way and fetches at most 100 events once. My Work shows obligations plus a latest-unseen summary, not the complete active optional list. Seen/settled entries remain eligible for Activity children. `C/features/inbox/ui/widget/activity_event_subcard_block.dart:127–140`; `C/features/my_work/ui/widget/my_work_whats_new_row.dart:12–48`; `S/data/repository/attention_repository.dart:763–824`. |
| Unanswered forwards pinned | Pinned eligibility already requires `needsMe`, visibility, no tombstone dismissal, and no responsibility-scope membership. Offers have server pagination. `S/data/repository/attention_repository.dart:245–254,843–903`. | Keep pinning. Separate pin status from optional freshness and stop unrelated optional events reordering pinned Requests. |
| Answered-forward outcomes dismissible | Watching, helping, not-interested, and terminal outcomes exist. Not-interested has Restore; only closed/deleted outcomes receive Hide. `C/features/inbox/ui/widget/activity_forward_row.dart:17–84`; `C/features/inbox/ui/widget/activity_stream_view.dart:855–870`. | Add `×` for every outcome. Existing tombstone dismissal is not a general outcome-clear model. |
| For You can reach zero | Activity has Read all, not Dismiss all. It also synthesizes a Watching digest in addition to Request representatives. `C/features/inbox/ui/screen/inbox_screen.dart:133–135,261–283`; `S/data/repository/attention_repository.dart:463–515`. | Sweep must cover Request updates, forward outcomes, pending forwards, network updates, and prompts. Remove digest duplication from the primary stream; preserve Watching as a collection. |
| Reset counters | Settings contains local-auth reset and debug counters, but no attention reconciliation action in the inspected Settings code. `C/features/settings/ui/bloc/settings_cubit.dart:142`; `C/features/settings/ui/bloc/debug_settings_cubit.dart:261–266`. | Add an authenticated reconciliation command and user-visible progress/result. Reset must not mean “clear everything.” |
| Rewarding cleared states | My Work already has contextual empty/orientation copy and navigation actions. `C/features/my_work/ui/widget/my_work_empty_body.dart:49–54,91–152`. | Distinguish “no Requests,” “no matching Requests,” and “attention cleared”; add an illustrated cleared state and truthful clearing feedback. |
| Child Request independence | Child creation already records an optional parent notice via `roomMessagePosted`. `S/domain/use_case/beacon_child_create_case.dart:412–447`; `S/domain/attention/attention_policy.dart:277–292`. | Hierarchy lifecycle delivery also emits attention addressed to the destination Request, including ancestor destinations. With current Activity ranking this can bump that destination. Preserve hierarchy logs but remove recursive attention effects. `S/domain/use_case/beacon_hierarchy_delivery_case.dart:154–177`; `S/domain/use_case/attention_intent_case.dart:844–865`. |
| Review work stays with its Request | Review obligations and informational review events are Beacon-scoped; surface allocation uses `beacon_id`, independently of deep-link destination. `S/domain/attention/attention_models.dart:41–46`; `S/domain/attention/attention_policy.dart:277–290`; `S/data/repository/attention_repository.dart:163–171`. | Reuse this. Ensure every review presentation uses the common Request event block and preserves its specific CTA/deep link. |
| Request timeline and Notification History | Request detail has a chronological activity sheet. Notification History is a separate, unscoped feed session. `C/features/beacon_view/ui/widget/beacon_activity_sheet.dart:9–20,55–77`; `C/features/beacon_view/ui/widget/activity_list.dart:29–54`; `C/features/updates/ui/screen/updates_screen.dart:13–36`. | The timeline is not currently a complete personal receipt history. Cleared/resolved receipts need a private, authorized timeline projection; do not publish recipient-specific updates into shared room activity. |
| Complete history and safe retention | Occurrences, recipient facts, receipts, and delivery jobs exist. However, unseen receipt collapse overwrites presentation, occurrence identity, and creation time. Retention deletes seen, emailed receipts older than 30 days without checking live obligations. `S/data/repository/attention_dispatch_repository.dart:90–148,181–203`; `S/data/repository/notification_outbox_repository.dart:118–130`; `S/domain/use_case/task_worker_case.dart:267–275`. | Stabilize new receipt identity and preserve attention/history records. Clearing must not enable deletion of unresolved work. Previously collapsed or deleted history cannot be promised back. |
| Multi-device convergence | `AttentionCase` listens to notification, help-offer, Inbox, reconnect, and blocking changes. Optimistic acknowledgments already have account-generation and token handling. `C/domain/attention/attention_case.dart:128–148,283–315,370–413`. | Extend these mechanisms to clearing, outcome state, source settlement, and repair. Do not create a second client attention owner. |
| Durable rules and enforcement | Product responsibility rules and D1–D13 exist. Event contracts and server/client architecture tests exist. `CONTEXT.md:202–220`; `docs/plans/work-activity-redesign-plan.md:22–34`; `docs/contracts/updates-event-contract.json:1–19`; `ST/architecture/updates_event_contract_test.dart:165–190`. | Extend the contract beyond producer/destination/muteability fields to exhaustive classification, clearing, action resolution, grouping, and ordering rules. |

### Relationship to predecessor decisions

The existing design is the foundation, not a discarded prototype.

- **Keep D1–D6:** Watching ownership, separate History, network updates in Activity, live-obligation counts, dot-only Activity, established terminology.
- **Keep D7 with discoverability:** archived Requests remain My Desk-owned; their optional attention must be reachable from the tab dot.
- **Complete D8:** source actions resolve obligations; remove generic Done.
- **Keep D9 and D11:** pagination and the single For You entry point.
- **Amend D10:** unanswered forwards remain pinned, but answered Requests have only one primary representative; optional updates do not reorder them.
- **D12 is historical rollout machinery:** introduce a new capability boundary only for this incompatible state transition.
- **Amend D13:** not-interested outcomes remain available until explicitly cleared; they are not permanent primary-stream rows.

Evidence: `docs/plans/work-activity-redesign-plan.md:22–34,154–198`. Its implementation plan explicitly deferred auto-settlement; current code has subsequently implemented important portions, so that old task list cannot be reused as the remaining backlog (`docs/plans/work-activity-redesign-implementation-plan.md:23`; settlement evidence above).

## 2. Net remaining delta

1. Introduce **clearing independent of reading and settlement**.
2. Give newly produced receipts immutable identity; preserve history and unresolved obligations.
3. Extend existing Request aggregates to return only live obligations and uncleared optional events.
4. Apply responsibility scope to **all** Request representatives, including forward outcomes.
5. Replace optional-driven ordering with stable placement and obligation-driven promotion.
6. Finish source-based settlement coverage; remove generic obligation dismissal.
7. Generalize answered-forward dismissal and implement For You sweeping over dismissible attention only (decision A).
8. Centralize successful Request-open clearing, with bounded event membership.
9. Render independent dots and obligation counts; make expandable event lists complete and reversible.
10. Add timeline receipt access, reconciliation, cleared-state rewards, durable documentation, and enforcement.

**Not new work:** responsibility scope, Activity coalescing, pinned-forward pagination, review subcards, help-offer response sheets, review-submit settlement, separate Notification History, and realtime invalidation infrastructure.

## 3. Design decisions

### D01 — One server-derived primary owner

For an authorized viewer `u` and Request `b`:

```text
R(u,b) =
  authored non-draft Request
  OR active help offer
  OR at least one authorized live obligation

primarySurface(u,b) = R(u,b) ? myWork : activity
```

All event rows and outcome notices inherit that ownership. Never store the surface on a receipt.

Drafts remain private My Desk work objects without attention membership.

A "You're helping" outcome is the one deliberate exception, by **owner decision B**: the answered-forward
outcome row stays in For You as a **dismissible tombstone** — non-bumping, non-grouped, no sub-cards, no dot, with
a × (D06, D07). It is a presentational trace of the viewer's own past action, not a second attention object; the
Request's live attention still belongs solely to My Desk. Removing the row entirely — so that For You shows only
transient feedback after offering help — remains the cleaner end state and is retained as a reversible follow-up,
not as part of this plan. Today's duplicate is asserted by existing tests
(`ST/data/repository/attention_activity_stream_pg_test.dart:143,587`), which stay valid under B.

**Rationale/evidence:** ownership already moves dynamically; synthetic forwards are the exception (`S/data/repository/attention_repository.dart:147–173,255–279,388–407`).

### D02 — Three independent state axes

```text
read:        unseen → seen                 // History/chat reading
optional:    uncleared → cleared           // explicit cleaning or successful open
obligation:  live → resolved/superseded/expired
```

- `seen_at` continues to describe reading.
- Optional activity is active iff `!requires_action && cleared_at == null`.
- Obligations are active iff `requires_action && settlement_kind == null`.
- Reading never settles or clears.
- Clearing never settles.
- Settlement removes an obligation even when it remains unread in History.
- “Mark unread” in History never resurrects primary-surface attention.

Opening a Request is an explicit clear boundary, not merely a read operation.

**Rationale/evidence:** seen and settlement already differ, while all existing clearing substitutes use seen (`S/data/database/migration/m0118.dart:7–47`; `S/data/repository/attention_repository.dart:1212–1233`).

### D03 — Immutable event receipts; aggregate cards, not mutable receipt identities

For new canonical events:

- One receipt per `(occurrence_id, account_id)`.
- Event copy, occurrence identity, and event timestamp do not change after insertion.
- Replayed `source_event_key` produces no additional receipt.
- Multiple receipts coalesce in the existing Request projection.
- Channel aggregation may retain its existing collapse key; split it from in-app receipt identity.

For repeated actionable reminders concerning the same unresolved task, maintain one live obligation generation. A semantically renewed obligation supersedes its predecessor transactionally; a delivery retry does neither.

Upgrade obligation identity to include:

```text
event family + beaconId + subjectId + recipientId + lifecycle generation
```

The stable logical task key excludes generation; the receipt identifies a particular generation. Review generations distinguish review windows; offer generations distinguish withdrawal/re-offer cycles.

**Rationale/evidence:** current collapse overwrites the receipt later used for acknowledgment; the current thread-key subject can be `targetEntityId` without including Beacon identity (`S/data/repository/attention_dispatch_repository.dart:90–148`; `S/domain/attention/attention_policy.dart:294–309`).

### D04 — Obligations resolve only through domain transitions

Initial actionable catalog preserves current semantics:

| Obligation | CTA | Resolving transitions |
|---|---|---|
| Author must respond to a help offer | **Respond** → existing response sheet | Accept, decline; withdrawal or terminal invalidation makes the obligation obsolete |
| Eligible reviewer must submit a review package | **Review / Send changes** → existing review flow | Successful package send; window closure or reopen settles/expires/supersedes as appropriate |

Remove generic Done and generic user settlement from both primary surfaces and History. Reject attempts to use the old public mutation to dismiss these obligations after activation.

Opening a CTA, cancelling a sheet, navigation failure, or saving an unsent review draft does not resolve anything.

**Owner confirmation (C).** Generic Done is removed not merely because source transitions are more reliable, but
because **no obligation in the current product can honestly be resolved by acknowledgment**. Every live obligation
kind requires a choice or an input — responding to a help offer, submitting a review package — so its CTA opens a
sheet/popup that captures that decision. The `ask`-style acknowledge-only objects that once justified a bare Done
no longer exist. Every future obligation kind must ship with a decision-capturing CTA; a kind that would need a
bare Done is evidence that it is an optional update, not an obligation.

The source mutation and settlement execute in the same domain transaction. System repair uses the same predicates. Do not infer settlement merely from surface exit.

**Rationale/evidence:** source settlement is already transactional for accept/decline; reviews already prohibit manual Done (`S/domain/use_case/coordination_case.dart:335–361,404–427`; `C/features/my_work/ui/widget/my_work_obligation_block.dart:282–305`; `S/domain/use_case/transactional_attention_case.dart:14–35`).

### D05 — Request opening clears a bounded snapshot after successful display

Replace pre-navigation `markSeenForBeacon` calls with one Request-detail entry lifecycle:

1. Authorize and load the Request.
2. Fetch an opaque, account-bound snapshot of its currently active optional receipt IDs and outcome generation.
3. Once the Request detail successfully mounts in the foreground, clear that snapshot.
4. Preserve events committed after the snapshot.
5. Run once per deliberate Request visit, not on rebuild, tab selection, scrolling, room-watermark advancement, or background refresh.

All entry paths use this: My Desk, For You, push, History, profile, graph, and direct links.

Opening a child clears the child only. Opening a review deep link clears optional Request updates but leaves the review obligation live until submission.

**Rationale/evidence:** current entry-point acknowledgment precedes navigation and has no event boundary (`C/features/inbox/ui/widget/activity_stream_view.dart:840–849`; `S/data/repository/attention_repository.dart:1212–1233`).

### D06 — Every optional event has an explicit clearing affordance

- Event `×`: clear that optional event.
- Request-level `×`: clear that Request’s captured optional set and outcome notice.
- No `×` on an obligation.
- A mixed card labels its control **Dismiss updates**; the Request and obligations remain.
- Clearing a card does not archive the Request, withdraw help, leave Watching, or alter review data.

Forward/prompt actions are the explicitly specified exceptions in D07, not implicit side effects of generic receipt clearing.

**Rationale/evidence:** current subcard tap marks seen, while answered outcomes lack a general dismissal action (`C/features/inbox/ui/widget/activity_event_subcard_block.dart:96–113`; `C/features/inbox/ui/widget/activity_stream_view.dart:855–870`).

### D07 — For You sweeps everything that carries a ×, and nothing that needs a decision

**Owner decision A.** *Dismiss all* clears exactly the rows that expose a × individually. It never applies a
domain transition on the viewer's behalf.

| Item at capture | Sweep effect |
|---|---|
| Request optional events | Clear captured events |
| Answered-forward outcome (tombstone, decision B) | Clear captured outcome generation |
| Network / non-Beacon optional receipt | Clear receipt |
| Timeline-only propagated notice, where surfaced | Clear receipt |
| **Unanswered forward** | **Untouched** — it awaits a decision |
| **Pending invite / setup prompt** | **Untouched** — it awaits a decision |
| Live obligation, or Request now owned by My Desk | Skip; never dismiss |

Rationale: sweeping an unanswered forward answers a person by not answering them — the same private-versus-social
boundary that forbids a × on obligations. Converting pending forwards to *Not interested* in bulk would make the
counterparty see a rejection the viewer never made, and neither disclosure in the button's description nor a
30-second undo repairs a signal that has already been sent.

Consequently **the sweep is defined over dismissible attention, not over the whole surface**: after *Dismiss all*,
For You may legitimately still show its pinned decision zone. That is the cleared state, and D18 must say so in
copy. The button is enabled by server-side eligibility — are there dismissible members? — never by unread counts
or loaded row counts.

Everything else from the base stands: membership is captured server-side and covers unloaded pages; each member's
clearing commits per Request; ownership and authorization are re-checked before applying each member; membership
is never extended on retry; the operation returns applied/skipped/failed totals and is resumable by ID (D12).

Sweeping a Watching update does not stop watching; Watching stays a collection of Inbox stances, not a list of
uncleared events.

### D08 — Stable placement; only new obligations promote existing Requests

Ordering:

1. **My Desk Needs you:** latest live-obligation creation time descending, then Beacon ID.
2. **Remaining My Desk sections:** preserve section membership and user-selected sort, but replace incidental `Beacon.updatedAt` ordering with stable work-entry/creation ordering for Recent.
3. **For You pinned forwards:** stable first-entry order within the pinned zone.
4. **Remaining For You Requests:** stable first-entry order.

An optional event changes a dot, preview, and expandable list. It does not change the existing Request’s ordering key. A previously absent Request can enter the list; its first entry establishes its position.

A new obligation moves the Request to My Desk’s top obligation position. Resolution moves it to its natural section or to For You if responsibility ends and optional attention remains.

Explicit user actions can change zones: rejecting a forward unpins it; restoring it repins it. That is a state transition, not an optional-event bump.

Keep keyset pagination, but version its cursor when changing sort keys. On head refresh, reconcile by Beacon ID.

**Rationale/evidence:** Activity currently orders by latest optional event; My Work uses tier plus mutable Beacon update time (`S/data/repository/attention_repository.dart:338–341,426,874–901`; `C/features/my_work/domain/derive_my_work_cards.dart:15–26,60–82`).

### D09 — Indicators describe active attention, independently

```text
request.dot = exists uncleared optional event or uncleared outcome
request.count = number of live canonical obligation receipts

myDesk.dot = exists owned Request with request.dot
myDesk.count = sum request.count
forYou.dot = exists active optional attention, pending forward, or pending prompt
```

- My Desk can display both dot and count simultaneously.
- Selected tabs retain their indicators.
- For You never displays an obligation count.
- Do not repurpose event totals, forwarded-sender counts, or page lengths as attention badges.
- Archived My Desk attention contributes to the tab dot; the Archive filter exposes the corresponding dot and a direct route to those Requests.

Section/card obligation counts count live obligations, not Request cards or visual subcard groups.

**M1 — one predicate, not two.** The default-visible predicate of a list and the predicate behind its indicator
must be the *same function*, called by both, with a test asserting they cannot diverge. This closes the failure
that predecessor D7 makes easy to reintroduce: the tab lights, the user opens it, the default filter shows
nothing, and there is nothing to clear. Archived attention therefore either contributes to the dot **and** is
reachable through the Archive filter, as specified above, or it contributes to neither.

**Rationale/evidence:** current My Desk dot is conditional on zero obligations and inactive-tab status; surface unread counts include every unseen receipt (`C/features/home/ui/bloc/home_attention_state.dart:56–71`; `S/data/repository/attention_repository.dart:184–193`).

### D10 — One reusable, paginated active-event block

Extend the existing components into a common domain-backed Request attention block:

- Collapsed preview: bounded, obligations first.
- Expand and collapse controls both exist.
- Expanded list includes all live obligations and uncleared optional events.
- Cursor pagination continues past 100 events.
- Counts are server totals, not loaded-row counts.
- Resolved/cleared entries disappear from this block.
- Review events use the same block; their event kind selects the existing action/deep link.
- Preserve focused controls and screen-reader position when an event disappears.

Keep presentation in UI and classification/action descriptors in domain; repositories return domain projections.

**Rationale/evidence:** current Activity expansion has no collapse path and makes a single capped request; My Work already supplies useful obligation grouping and review presentation (`C/features/inbox/ui/widget/activity_event_subcard_block.dart:127–159`; `C/features/my_work/domain/group_my_work_obligations.dart:18–38`).

### D11 — Authorization governs every projection and mutation

Every card, child-event page, summary, snapshot, clear, undo, repair, and timeline read reuses current receipt/Request authorization.

- Account identity comes from credentials, never an input account ID.
- Loss of access removes restricted content and its contribution to indicators.
- Authorization loss alone does not settle a real obligation.
- Permanent source invalidation settles through its domain transition.
- Regained authorization may reveal still-live or still-uncleared attention.
- Safe terminal receipts keep their existing restricted-copy policy.
- A denied clear/undo does not disclose whether an inaccessible Request or receipt exists.

**Rationale/evidence:** visibility is centralized and includes content/tombstone policy and preference filtering (`S/data/database/migration/m0117.dart:7–65`); current acknowledgment already derives account identity from credentials (`S/api/controllers/graphql/mutation/mutation_attention.dart:31–45`).

### D12 — Race-safe, idempotent clearing with recoverable bulk progress

Use client-generated operation IDs and server-bound membership.

For a sweep:

1. Persist the operation and the finite eligible member set in a database snapshot.
2. Process bounded batches; each Request’s source transition, receipt clearing, and outcome clearing commit together.
3. Recheck authorization and primary ownership before applying each Request member.
4. Skip Requests moved to My Desk since capture.
5. Do not extend membership during retries.
6. Return applied/skipped/failed totals and authoritative summaries.
7. Resume a timed-out operation by ID.

A new receipt has a new immutable identity and cannot be swallowed by clearing an older one. A new forward generation cannot be hidden by clearing an earlier outcome generation.

Bulk clearing need not be globally atomic across thousands of Requests. The UI shows progress and does not announce “All clear” until completion and a fresh summary confirm it.

**Rationale/evidence:** existing acknowledgments address mutable receipt IDs, and For You is paginated (`S/data/repository/attention_dispatch_repository.dart:125–148`; `S/data/repository/attention_repository.dart:843–903`).

### D13 — Undo is bounded and never reverses somebody else’s work

Provide a 30-second server-enforced undo token for explicit dismiss operations.

- Restore only members changed by that operation.
- Check current authorization, outcome generation, and per-object decision revision.
- A subsequent open, clear, stance change, or source action invalidates undo for that object.
- Partial undo returns an explicit result; do not silently overwrite newer state.
- Undo never reverses accepting help, submitting a review, source expiration, or another user’s mutation.
- Successful-open clearing has no snackbar undo; History remains available.
- Not-interested Restore remains a separate durable Inbox action after the undo window.

The conservative rule is deliberate: later intent wins, even when that means some items cannot be restored.

**Rationale/evidence:** the client already distinguishes acknowledgment tokens and account generations, but that protects local optimism rather than cross-device undo (`C/domain/attention/attention_case.dart:283–315,370–413`).

### D14 — Realtime invalidates; the server remains authoritative

Extend existing notification invalidations to clear state, outcome generation, repair, and relevant ownership changes.

- Reuse `AttentionCase`, its account generation, and destination sessions.
- Apply optimistic removal only for identified members; roll back only the matching operation.
- Do not zero unloaded-page totals optimistically.
- After mutation completion, refresh summaries and affected Request projections.
- Reconnect refreshes head pages and summaries.
- Stale page/summary responses cannot overwrite a newer mutation result.
- Offline gestures report failure and retain attention; do not silently queue destructive-looking sweeps.

Coordinate ownership refreshes by Beacon ID so clients do not temporarily retain both old and new representatives after a successful move.

**Rationale/evidence:** invalidation and reconnect machinery already exists (`C/domain/attention/attention_case.dart:128–148`).

### D15 — Reset counters means reconcile, not erase

Settings **Reset counters**:

1. Reconcile current help-offer and review obligations against their source state.
2. Create missing current obligation generations idempotently.
3. Settle obsolete generations using their actual source reason.
4. Recompute authorized Request projections and summaries.
5. Invalidate all sessions for that account.
6. Replace client cached indicators with the returned authoritative snapshot.

Preserve optional clear state, Inbox stance, source actions, and History.

A correct result may still contain dots and counts. Copy must say “Counters refreshed” and show an error if repair failed, never claim the user has no work.

**Rationale/evidence:** summaries are already derived; source-specific review backfill exists and can be generalized (`S/data/repository/attention_repository.dart:176–204`; `S/domain/use_case/review_obligation_backfill_case.dart:18–25`).

### D16 — Child attention does not propagate recursively

- Keep the existing optional child-created notice on the **direct parent**.
- Subsequent child events belong to the child’s attention object.
- Preserve hierarchy lifecycle notices in destination Request logs.
- Classify propagated hierarchy notices as **timeline-only**, with no primary-surface dot, count, or ordering effect.
- A separate real obligation on a parent remains a parent obligation; it must be produced explicitly by that parent’s domain transition.

“Timeline-only” is a placement policy, not a third actionable class.

**Rationale/evidence:** child creation and propagated lifecycle attention are separate existing producers (`S/domain/use_case/beacon_child_create_case.dart:422–447`; `S/domain/use_case/beacon_hierarchy_delivery_case.dart:154–177`).

### D17 — Clearing is not deletion; History and timeline remain complete within authorization

For post-cutover data:

- Retain receipts and their clear/settlement metadata.
- Stop age-based deletion of attention-bearing receipt history.
- Never delete live obligations or uncleared optional events through delivery retention.
- Delivery-job cleanup can remain separate from receipt-history retention.
- Account erasure and explicit source/privacy deletion rules still apply.

Notification History remains chronological across surfaces and includes cleared/resolved receipts. The Request timeline adds the viewer’s authorized receipt history without publishing it to other participants.

When a receipt corresponds to an existing timeline event, merge by a stable source identifier where available; do not duplicate the same event. Otherwise render a clearly personal update entry.

Do not fabricate pre-cutover events lost to collapse or retention. Preserve existing legacy rows and their collapsed-count metadata.

**Verified pre-existing defect — fix regardless of this plan.** `deleteSettledOlderThan` filters on
`seen_at IS NOT NULL AND emailed_at IS NOT NULL AND created_at < $1` plus the absence of a pending/leased
delivery; it does **not** check `requires_action` or settlement state
(`S/data/repository/notification_outbox_repository.dart:118–131`). A live obligation that has been seen and
emailed is deletable today — outstanding work vanishes and the count drops with no explanation. This is not
introduced by the clearing model; U06 fixes it as a precondition for it.

**Rationale/evidence:** current receipt retention conflicts with the complete-log requirement and can remove live obligations; the existing Request timeline is built from different event sources (`S/data/repository/notification_outbox_repository.dart:118–130`; `C/features/beacon_view/ui/widget/activity_list.dart:29–54`).

### D18 — Cleared states reward attention completion, not disappearance of work

- My Desk can be attention-clear while authored/active-help Requests remain.
- For You can become an empty attention surface while Watching and Not interested collections remain accessible.
- Show a lightweight illustration and “You’re caught up.”
- After an explicit sweep, show the actual number cleared.
- Optional “Cleared N today” counts distinct currently cleared items from explicit sweep operations, in the viewer’s calendar day; opening, repair, duplicate retries, and undo must not inflate it.
- No streak pressure or fabricated success while loading, offline, failed, or partially cleared.

**Cleared state under owner decision A.** "Caught up" means *no dismissible attention left*, which is not the
same as an empty screen: the pinned decision zone may still hold unanswered forwards and prompts. Copy must
distinguish three states — *nothing here*, *nothing new* (cleared, decision zone still shown), and *nothing
matching this filter* — and must never celebrate while decisions are pending, while loading, offline, or after a
partial sweep.

Use existing design-system tokens and components, scaled text, meaningful semantics, and reduced-motion behavior.

**Rationale/evidence:** existing empty states already distinguish filters and provide useful navigation; build on them (`C/features/my_work/ui/widget/my_work_empty_body.dart:49–54,91–152`; `docs/tentura-design-system.md:193–206`).

### D19 — Coordinated cutover; no silent legacy-state reinterpretation

Additive rollout precedes activation.

At cutover:

- Existing optional receipts with `seen_at != null` become cleared with reason `legacy_seen`.
- Existing unseen optional receipts remain active.
- Legacy settled obligations remain historical; source reconciliation creates a fresh generation if the task is actually still unresolved.
- Existing answered-forward outcomes become clearable outcomes; prior tombstone dismissals remain cleared.
- In-scope helping outcomes migrate to My Desk ownership.
- New receipts use immutable identities.
- Old read mutations remain read-only and cannot clear new attention.
- Legacy-client compatibility is **not** a constraint (M3): no users, web-only client. The cutover is one release
  plus a `kDefaultMinClientVersion` bump. Old read mutations still lose the ability to clear new attention, but no
  dual-behaviour period is designed and no effort is spent on clients that will never run.

Backfill uses a fixed cutover boundary and is restartable. It does not replay push/email delivery.

**Rationale/evidence:** the old model has only `seen_at`, mutable collapse, and a public settlement API; client version gating is the established compatibility mechanism (`S/data/repository/attention_dispatch_repository.dart:125–148`; `S/api/controllers/graphql/mutation/mutation_attention.dart:98–108`; `DEV_GUIDELINES.md:241–267`).

## 4. Storage, API, and event-contract changes

### 4.1 Minimal storage extensions

| Object | Proposed addition | Purpose |
|---|---|---|
| `notification_outbox` | `cleared_at`, `clear_reason`, `cleared_by_operation_id`; immutable canonical `(occurrence_id, account_id)` identity | Separate optional clearing from History reading |
| Obligation receipt identity | Beacon-scoped logical key and lifecycle generation; one live receipt per logical task | Prevent duplicate counts and cross-Request key collisions |
| Per-viewer Request attention state | Stable first-entry time; outcome generation, clear state, decision revision | Stable ordering, clearable synthetic outcomes, conservative undo |
| Clear operation and members | Account, operation ID, captured members/generations, status/results, undo deadline | Idempotency, pagination-independent sweep, resumable progress |
| Classification metadata | Contract version and placement policy where needed | Persist event-time classification; do not reinterpret history through current viewer roles |

Do **not** store `primary_surface`. Derive it using D01.

Required constraints and indexes:

- Clear metadata is valid only for optional receipts.
- Settlement metadata is valid only for obligations.
- Unique canonical occurrence/recipient identity for new receipts.
- Unique live logical obligation task.
- Partial indexes for active optional receipts and live obligations by account/Beacon.
- Operation membership uniqueness.
- Outcome identity includes its generation.

Extend existing realtime trigger change detection; it already includes settlement columns (`S/data/database/migration/m0164.dart:3–64`).

Current migration registry ends at `m0177`; allocate the next available IDs at implementation time rather than reserving an assumed number in parallel work (`S/data/database/migration/_migrations.dart:360–369`).

### 4.2 Domain/API contract

Names below are proposed additive API names, not existing endpoints.

| Operation | Contract |
|---|---|
| `requestAttention(beaconId, cursor, limit)` | Surface, independent indicators, ordering metadata, active-event page, snapshot token |
| `requestAttentionHistory(beaconId, cursor, limit)` | Authorized personal receipt timeline, including cleared/resolved records |
| `attentionClear(snapshotToken, operationId)` | Clear captured optional members; typed partial/stale/denied result |
| `attentionDismissAll(surface: activity, operationId)` | Capture entire eligible surface, execute/resume sweep, return progress and summaries |
| `attentionUndo(operationId, undoToken)` | Restore eligible operation members only |
| `attentionReconcile(operationId)` | Repair source-derived obligation state and return authoritative projections |
| Extended surface summary | My Desk obligation count and optional-dot state; For You dot state; eligible sweep presence |

Keep existing feed/history APIs compatible during expansion. Primary surfaces stop deriving indicators from `unread_total`.

GraphQL controllers validate bounds and credentials; domain cases orchestrate; data repositories own SQL. Client Cubits consume cases and domain entities. Reuse `AttentionCase` rather than adding an independent attention cache.

### 4.3 Classification contract for every future event

Extend `docs/contracts/updates-event-contract.json` with a versioned schema covering **every** `AttentionEventType` and every producer/recipient variant.

Required fields:

| Field | Required meaning |
|---|---|
| `scope` | Beacon or account |
| `recipientPredicate` | Exact role/reason condition for this variant |
| `attentionClass` | Obligation or optional |
| `placement` | Primary attention or timeline-only |
| `groupKey` | Beacon ID for every Request event |
| `actionDescriptor` | Typed CTA and target requirements; required for obligations |
| `logicalTaskKey` | Required for obligations; includes Beacon scope |
| `resolutionTransitions` | Source transitions that settle each obligation |
| `clearPolicy` | Optional explicit/open; obligations forbidden |
| `orderingEffect` | New obligation promotes; optional does not |
| `accessPolicy` | Existing authorized-content/safe-terminal policy |
| `recoverableVia` | `request_timeline` / `people` / `room` / `history_only` / `none` — where this variant's content survives after clearing (M2) |
| `producerTests` / `transitionTests` | Executable coverage, not merely filenames |

Rules:

1. Exhaustive enum coverage; no default-false classification branch.
2. An obligation must have a CTA, logical identity, and resolution lifecycle.
3. Mandatory delivery does not imply obligation.
4. Beacon events cannot select a tab independently of responsibility scope.
5. Optional events cannot declare a bump effect.
6. Hierarchy-propagated events cannot declare primary attention.
7. A producer must declare a covered event variant or an explicit silent reason.
8. Client presentation/action mappings must be exhaustive for supported event kinds.
9. SQL projections, domain policy, and contract fixtures must agree through executable tests.
10. **Dismissible implies derivable (M2).** An optional event may be clearable only if its content survives
    somewhere the viewer can reach. A variant declaring `recoverableVia: none` must either not have clearing as
    its only exit, or be exempt from retention deletion under D17; the contract test fails on `none` without a
    declared exemption.

Upgrade the existing server/client contract tests rather than creating a parallel registry. Current tests describe a fixed six-field contract and do not establish these semantics (`ST/architecture/updates_event_contract_test.dart:165–190`). Include existing hierarchy, deadline, and coordination types from the runtime enum, not just the older contract’s headline list (`S/domain/attention/attention_models.dart:9–38`).

## 5. Surface specifications

### My Desk

- Keep existing filters, Request cards, and responsibility sections.
- Needs you sorts by new live obligations.
- Each Request shows an independent optional dot and obligation count.
- Mixed cards expose **Dismiss updates**, never an obligation-dismiss control.
- Common active-event block replaces the split between obligation list and latest-unseen summary.
- Existing Respond/Review flows remain the action implementation.
- Settled/cleared events leave the block immediately after confirmed state change.
- Attention-clear reward can appear above ongoing work; it does not hide work.
- Archive filter remains discoverable when archived optional attention causes the tab dot.

Basis: existing sections preserve pre-sorted card order and count live receipts (`C/features/my_work/domain/derive_my_work_sections.dart:26–56`).

### For You / Activity

- Pinned zone contains remaining unanswered forwards and existing fresh actionable prompts.
- One durable primary representative per Request.
- Existing Requests do not move because optional events arrive.
- Every outcome and optional event has `×`; items awaiting a decision never do (decision A).
- Header action is **Dismiss all**, enabled by server eligibility rather than unread count or loaded rows.
- No numeric attention badge on tab or Request.
- Remove Watching digest from the primary stream; keep Watching and Not interested collections in navigation.
- Clean state replaces the attention *stream* when no dismissible attention remains; the pinned decision zone stays visible above it (decision A).
- Network updates remain independent optional items because they have no Beacon.

Basis: the current stream already supports Request aggregates and independent non-Beacon receipts (`S/data/repository/attention_repository.dart:309–324,413–515`).

### Request detail

- Successful foreground entry clears the captured optional set.
- Obligations remain actionable.
- Timeline shows retained authorized history, including clear/settlement status where useful.
- Review links preserve their target.
- Child opening and child event history remain scoped to the child.
- A forbidden or failed route clears nothing.

Basis: existing activity sheet and navigation callbacks provide the integration points (`C/features/beacon_view/ui/widget/beacon_activity_sheet.dart:9–36`).

### Notification History

- Preserve separate route, search, chronology, and per-destination session.
- Include all retained authorized receipts, irrespective of primary surface or clear state.
- Read/unread controls affect History only.
- Remove generic obligation Done.
- Opening a Request from History invokes the same successful-open boundary.
- Reading a profile update does not implicitly sweep it from For You.

Basis: `C/features/updates/ui/screen/updates_screen.dart:13–36`.

### Settings

- Add **Reset counters** with explanation: “Recheck your updates and outstanding actions.”
- Disable duplicate in-flight requests; show progress.
- Success refreshes all attention projections.
- Failure retains current attention and offers retry.
- Do not expose implementation terminology such as outbox, reconciliation, or projection to users.

## 6. Ordered implementation units

Each unit owns the listed area, lands with focused evidence, and preserves unrelated worktree changes. Generated files are refreshed through codegen.

| Unit | Depends on | Ownership and deliverable | Review boundary |
|---|---|---|---|
| **U01 Product contract** | — | New durable `docs/features/request-attention.md`; update `CONTEXT.md`, `docs/README.md`, indicator spec, predecessor supersession notes | D01–D19, state diagrams, exact sweep/ownership rules |
| **U02 Characterization tests** | U01 | Existing attention PG tests and client widget tests | Record shipped coalescing, grouping, settlement, History, pinning; identify expected behavior changes |
| **U03 Exhaustive classification** | U02 | Server attention policy/models, event JSON, server/client architecture tests | Complete recipient-specific event catalog; no implicit optional fallback |
| **U04 Additive schema** | U03 | Server migrations/table mappings | Clear columns, outcome generations, operation/member tables, indexes, new identity constraints; migration restart proof |
| **U05 Immutable dispatch** | U04 | `attention_dispatch_repository.dart`, channel decision boundary | Immutable in-app identity; preserve source-event replay dedup and channel aggregation behavior |
| **U06 Safe retention and history read** | U05 | Outbox retention, attention query port/repository | Protect active work; retain post-cutover history; authorized Request-history pagination |
| **U07 Obligation lifecycle completion** | U03–U05 | Help-offer, coordination, evaluation, system settlement cases | Withdrawal/terminal transitions; logical task generations; remove generic settlement after capability activation |
| **U08 Optional clear/open command** | U04–U07 | New clear domain case/port/repository; GraphQL mutation | Exact snapshot membership, credential binding, idempotency, concurrent-arrival protection |
| **U09 Outcomes, sweep, undo** | U08 | Inbox outcome state; clear operation processing; prompt transition adapter | All outcome kinds clearable; unloaded-page sweep; no new residual outcome; conservative undo |
| **U10 Primary projections and ordering** | U05–U09 | Attention repository/query DTOs; My Work ordering inputs | One Request owner, active-only pages, stable optional ordering, obligation promotion, matching summaries |
| **U11 Child propagation policy** | U03,U10 | Hierarchy delivery/intents | Direct child-created optional notice; propagated lifecycle events timeline-only |
| **U12 Reconciliation** | U07–U10 | Generalized obligation repair case and authenticated endpoint | Missing/stale source obligations repaired; clear state preserved; repeat invocation idempotent |
| **U13 Client data/domain integration** | U08–U12 | Client GraphQL documents/repository, attention entities, `AttentionCase`, sessions | Typed APIs; account/revision protection; realtime refresh; no second cache owner |
| **U14 Shared event block and indicators** | U13 | Design-system component if needed; event presenter; home indicators | Expand/collapse and pagination; per-kind CTA/×; dot plus count; accessibility |
| **U15 My Desk integration** | U14 | My Work case/Cubit/cards/section derivation | Active-event block, source actions, stable sorting, archived attention discoverability |
| **U16 For You integration** | U14 | Inbox offers/stream/Cubits/chrome | One representative, stable pinning, all outcome `×`, Dismiss all, no digest duplication |
| **U17 Detail, History, Settings, rewards** | U13–U16 | Beacon view entry lifecycle/timeline; Updates; Settings; l10n/assets | All-route open clearing, history independence, repair control, truthful cleared-state reward |
| **U18 Backfill and activation** | U05–U17 | Restartable migration/backfill tooling; single-release `kDefaultMinClientVersion` bump (M3 — no dual-behaviour window) | Fixed cutover, no notification replay, legacy cleanup, old-client behavior explicitly blocked |
| **U19 Acceptance and release** | U18 | Integration journeys, documentation, release metadata | Independent PG/client/browser gates; client version and tracked web cache-buster synchronized |

U17 may be split into four small commits—detail entry, timeline/History, Settings, rewards—without changing dependencies. U09 should likewise separate outcome storage, sweep execution, and undo review.

No unit should combine retention changes, obligation lifecycle changes, and widget changes in one review.

## 7. Decision-linked test plan

### 7.1 Required behavior tests

| Decisions | Required evidence |
|---|---|
| **D01** | Author/helper/obligation-only/neither matrix; archived and draft cases; offering and withdrawing help; answered forward never leaves a second primary card |
| **D02** | Seen optional still active until cleared; cleared optional retained in History; seen obligation still counted; settled unread obligation absent from primary attention; mark-unread does not resurrect |
| **D03** | Same source-event replay inserts once; distinct occurrences retain distinct immutable receipts; new event survives old clear; same person offering on two Requests has distinct task keys; new lifecycle generation does not revive old settlement |
| **D04** | Accept/decline/withdraw/terminal invalidation; review draft versus send; reopen/expire; cancelled CTA; mutation rollback also rolls back settlement; public generic settlement rejected |
| **D05** | My Desk, For You, graph, profile, History, push, and direct-link opening; failed authorization/navigation clears nothing; later arrival survives; rebuild/scroll/room read does not clear |
| **D06** | Event `×` clears one; card `×` clears optional snapshot; mixed card preserves obligations; no obligation dismiss affordance anywhere |
| **D07** | Sweep across multiple unloaded pages and every dismissible item kind; unanswered forwards and pending prompts survive the sweep untouched; Watching stance survives; responsibility gained during sweep causes skip; cleared state is reported with a pending decision zone still present |
| **D08** | Optional events leave ordering keys unchanged; new obligation promotes; resolution demotes naturally; repeated forward does not reorder an existing pinned card; cursor/head-refetch dedup |
| **D09** | Independent dot/count combinations; selected-tab indicators; For You never has a count; archived attention discoverable; server totals equal complete authorized projections |
| **D10** | More than 100 active events; expand/collapse; page failures/retry; newly settled event disappears while expanded; review action still targets the correct review |
| **D11** | Foreign receipt IDs, foreign operation IDs, block/unblock, access removal/restoration, safe terminal copy, authorization lost between capture and apply |
| **D12** | Barrier-controlled concurrent arrival, source mutation, and sweep; timeout after commit; operation replay; worker restart; partial batch failure; fixed membership across retry |
| **D13** | Undo original operation; undo after another device opens/clears; outcome changed after sweep; expired token; partial restore; undo cannot reverse review/help acceptance |
| **D14** | Two device sessions converge; reconnect catch-up; stale summary/page response rejected; account switch during pending mutation; optimistic failure restores only matching members |
| **D15** | Corrupted/missing obligation projection repair; obsolete task settlement; repeated reset; concurrent source action; reset preserves optional clearing and returns nonzero counts when correct |
| **D16** | Child creation adds one optional direct-parent notice; child message/review/status changes do not affect parent attention or rank; ancestor log notice remains available |
| **D17** | Retention run preserves live obligations, uncleared updates, and retained cleared history; account erasure still works; timeline authorization; no recipient-state leakage; legacy collapse limitation represented honestly |
| **D18** | Empty versus clear versus filtered-empty states; partial/offline/error state never celebrates; retry/undo does not inflate reward count; localized day-boundary calculation if daily count ships |
| **D19** | Backfill restart, fixed boundary, previously seen/unseen data, manually settled but still-real source task, old/new clients, gate activation, rollback safety, no delivery replay |

### 7.2 Extend existing suites

Primary starting points:

- Server: `attention_surface_pg_test.dart`, `attention_activity_stream_pg_test.dart`, `my_work_attention_pg_test.dart`, `attention_mark_seen_for_beacon_pg_test.dart`, `attention_retention_pg_test.dart`, `review_obligation_settlement_pg_test.dart`, policy and contract tests.
- Client: `attention_case_test.dart`, `attention_surfaces_test.dart`, `activity_stream_view_test.dart`, `activity_event_subcard_block_test.dart`, My Work obligation/subcard/section tests, home navigation indicator tests.
- New focused suites: clear-operation races, outcome sweep/undo, reconciliation, successful-detail-open lifecycle, personal receipt timeline.

Update existing optional-bump and helping-forward expectations intentionally; those are currently asserted behaviors, not accidental test noise (`ST/data/repository/attention_activity_stream_pg_test.dart:143,537,587,645`).

### 7.3 Runtime acceptance journeys

Use real UI entry points and stable `TestIds`:

1. Forward a Request; receive several optional events; observe one pinned card with a dot and no reordering.
2. Offer help; observe one My Desk card and no durable For You duplicate.
3. Receive two actionable tasks on different Requests; verify newest obligation promotion and matching counts.
4. Open a Request while another device creates an optional event; only the captured set clears.
5. Submit review work; obligation disappears on both devices; informational review events remain on the same Request.
6. Dismiss every forward outcome kind; run Dismiss all with multiple pages and pending prompts; reach the cleared state.
7. Undo a sweep, then repeat with a conflicting action on the second device.
8. Create a child and generate child activity; verify parent attention is unaffected after the creation notice.
9. Inspect History and Request timeline after clearing and settlement.
10. Trigger Reset counters against a controlled inconsistent test fixture; verify correct nonzero or zero result.

Test compact 360/390 widths, expanded layout, EN/RU, increased text scale, keyboard/screen-reader controls, and reduced motion. Browser proof must exercise the actual controls, not just seed final database state.

### 7.4 Execution gates

All local test/analyzer commands use `scripts/run_with_test_cleanup.sh`.

Examples, from the relevant package directory:

```bash
../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --exclude-tags pg

../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  dart test --tags pg -j 1 \
  test/data/repository/attention_activity_stream_pg_test.dart \
  test/domain/use_case/review_obligation_settlement_pg_test.dart

../../scripts/run_with_test_cleanup.sh --timeout 45m -- \
  flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env
```

From repository root:

```bash
./scripts/run_with_test_cleanup.sh --timeout 10m -- \
  ./scripts/check-custom-lints.sh packages/client

./scripts/run_with_test_cleanup.sh --timeout 10m -- \
  ./scripts/check-custom-lints.sh packages/server

bash scripts/check-user-facing-terminology.sh
```

Use disposable PostgreSQL targets; a skipped PG suite is **blocked**, not passed. The current Activity PG suite explicitly skips when its admin database is unreachable (`ST/data/repository/attention_activity_stream_pg_test.dart:13–24`).

Keep four acceptance results separate: focused tests, PostgreSQL integration, browser journeys, release compatibility. None substitutes for another.

## 8. Durable documentation and release boundaries

U01 makes `docs/features/request-attention.md` the durable product source, linked from `docs/README.md`, `CONTEXT.md`, and the existing indicator specification.

It must contain:

- Responsibility formula and single-primary-surface invariant.
- Read/clear/settle distinction.
- Indicator formulas.
- Ordering and pinning rules.
- Exact opening and sweep boundaries.
- Forward outcome and prompt behavior.
- Child and review rules.
- History/retention guarantees and legacy limitations.
- Event-classification requirements and links to executable enforcement.

Plan documents retain implementation history and explicitly identify superseded predecessor decisions. Product rules must not live only in this implementation plan.

Release activation requires:

- Backfill/reconciliation dry-run evidence and restart proof.
- No unresolved live-obligation deletion path.
- No primary-surface use of `seen_at` as optional-cleared state.
- No generic obligation dismissal route.
- No durable cross-surface Request duplicate.
- Verified source settlement and multi-device behavior.
- Semver bump, appropriate minimum-client gate, and matching tracked `flutter_bootstrap.js?v=` in `packages/client/web/index.html`, following `.cursor/rules/versioning.mdc` and `DEV_GUIDELINES.md:241–267`.

Rollback may restore compatible presentation temporarily; it must not drop clear/history data, re-enable unsafe receipt deletion, or reopen settled source work.

## 9. Out of scope

- Redesigning Request ownership, help-offer admission, review scoring, or review eligibility.
- Promoting every mandatory notification into an obligation.
- Replacing the occurrence, dispatch, realtime, or channel-delivery systems.
- Changing push/email frequency or notification preferences.
- Deleting Watching/Not interested collections when their attention is cleared.
- Recursive child attention propagation.
- Reconstructing historical events already overwritten or deleted.
- Cross-account counters, leaderboards, streaks, or reward pressure.
- Renaming internal Beacon/Inbox entities or performing unrelated navigation redesigns.

## 10. Owner questions and proposed defaults

Three of these were answered by the owner on 2026-09-18 and are recorded as decisions, not questions. The rest keep proposed defaults.

| Question | Proposed default |
|---|---|
| Does “For You” replace the Activity tab label, or remain its section name? | Preserve current labels for this feature; behavior is independent of the naming decision. Predecessor D6 names the section, not the branch. |
| Does Dismiss all reject unanswered forwards and skip pending prompts? | **Answered: no (decision A).** The sweep touches only rows carrying a ×; anything awaiting a decision is left alone, and "cleared" is redefined as no dismissible attention left (D07, D18). |
| How should "You’re helping" coexist with the one-primary-surface rule? | **Answered: keep the row (decision B).** It stays in For You as a dismissible tombstone; removing the duplicate entirely is a reversible follow-up if it proves annoying (D01). |
| Must complete history have a finite retention period? | Retain post-cutover receipt history until account/source privacy deletion. Any shorter period requires an explicit product promise and separate retention design. |
| Is generic Done removed from every surface at once? | **Answered: yes (decision C).** Nothing in the product can be honestly resolved by acknowledgment today; every obligation CTA captures a choice or input (D04). |
| Is historical `seen_at` an acceptable migration approximation for “already cleared”? | **Yes**, with a fixed cutover and `legacy_seen` reason; avoid resurrecting a lifetime backlog. |
| Should launch include a daily clearing number? | **Owner wants the reward**: illustration plus the per-operation cleared count are mandatory; "cleared N today" ships only if the timezone and undo-accounting tests in D18 pass. |

The owner’s stated requirements — dismissible terminal outcomes, a For You sweep confined to dismissible rows, no passive clearing, obligation-only promotion, and Request-level ownership — are fixed requirements, not open questions.