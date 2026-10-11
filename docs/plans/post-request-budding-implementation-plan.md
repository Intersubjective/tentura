# Budding a Request from a Post — step-by-step implementation plan

**Status:** rev 1 (2026-10-11), draft.
**Baseline:** `main` at `7f535afff` (latest migration `m0236`).
**For:** an implementer (human or model) who follows units literally, test-first, one unit at a time.
Each unit lists goal, files, tests to write **first**, steps, and "done when".

**Sources of truth (read before any unit):**
1. [`post-request-budding-architecture.md`](post-request-budding-architecture.md) rev 2 — "Arch §N" points there.
2. [`post-request-budding-design.md`](post-request-budding-design.md) — owner decisions D1–D7, N1–N6 (Russian).
3. [`post-implementation-steps.md`](post-implementation-steps.md) **§0 (rules for every unit) applies verbatim**:
   conventions, migrations (one new migration per unit, next free number, upgrade-path test),
   transactions, exceptions, policies, V2 mutation pattern, Hasura two-test rule, client schema,
   design system, l10n, mocks, wrapped serial test runs (§0.2), definition of done (§0.3).

If a step contradicts the architecture, stop and report; do not guess. Line numbers are from
2026-10-11; if a quoted line drifted, search for the named symbol; if the symbol is gone, stop.

---

## 0. Deltas to the shared rules

- **Lock order (Arch §4.1):** global hierarchy lock → Post advisory `4242` + Post row (`PostLockPort.lockForPostMutation`) → child advisory `4242` + child row → invite rows `FOR UPDATE` ordered by `id` → recipient availability locks → trust pair locks. Every new path follows it and re-validates mutable state **after** locking.
- **Feature gate:** `packages/client/lib/consts.dart` → `const kPostBuddingEnabled = false;` (unit D0). Every client entry that starts a bud checks it. Unit E3 flips it. Server paths are not gated (nobody reaches them without the client), except §7 closure routing which reads env `TRUST_BUD_ROUTE_CREDIT_ENABLED` (default `true`) as a kill switch.
- **Alloy gate tests are not permanent** (memory: counts/SHAs/plan-text/subprocess tests do not land on `main`). Tests in this plan are behavioural only.
- **Russian copy** (use verbatim; English is a faithful translation):

| Key (suggested) | RU | Where |
|---|---|---|
| `postBudAction` | Оформить запрос | message action, ⋯ menu |
| `postBudPickMessageTitle` | Из какого сообщения оформить запрос? | non-author source picker |
| `postBudInviteTitle` | Кого позвать | invite step |
| `postBudInviteExplanation` | Позванные получат приглашение и сами решат, участвовать ли. Остальные участники поста увидят запрос и смогут предложить помощь сами. | invite step |
| `postBudInviteManyWarning` | Каждый отмеченный получит просьбу. Отмечено: {count} | above N = 5 |
| `postBudInviteNoteHint` | Почему зовёте (необязательно) | per-invitee note |
| `postBudClosePost` | Закрыть пост и продолжить в запросе | checkbox |
| `postBudDiscoverableWarning` | Пост видели только его участники. Если сделать запрос видимым для всех, его увидят и другие. | discoverable toggle |
| `postBudForwardingWarning` | В посте пересылка была выключена. Запрос можно пересылать. | when Post forward policy off |
| `roomBudNotice` | {name} оформил(а) запрос «{title}» и позвал(а) {count, plural, one{# человека} few{# человек} many{# человек} other{# человека}} | Post room notice |
| `roomBudNoticeNoInvites` | {name} оформил(а) запрос «{title}» | Post room notice, count 0 |
| `roomPostClosedNotice` | Пост закрыт. Разговор продолжается в запросе «{title}». | closed Post |
| `postClosedMarker` | закрыт | Разговоры |
| `beaconGrewFromPost` | Вырос из поста | child parent link |
| `inviteCardTitle` | {name} зовёт вас помочь | Activity card |
| `inviteAccept` | Принять | Activity card |
| `inviteDecline` | Не смогу | Activity card |
| `inviteStatusPending` | приглашён(а) | child People tab |
| `inviteStatusDeclined` | не сможет | child People tab |
| `inviteWithdraw` | Отозвать приглашение | child People tab |

## 1. Unit map (execution order)

| Unit | Title | Depends on |
|---|---|---|
| A1 | Detached published promotion (source delete fix) | — |
| A2 | Shared admission operation (refactor, no behaviour change) | — |
| A3 | Remove `BeaconRoomAdmit` (#283) | A2 |
| B1 | Schema: observers, invites, bud commands, sweep exemption, closed Post status | — |
| B2 | Effective Post members `E(P)` and invite eligibility (SQL + port) | B1 |
| B3 | Read wall: snapshot contextChild, no Post contextAncestor | B1 |
| B4 | Hierarchy realtime recipients for Post children | B3 |
| B5 | Contact sweep exemption + invite expiry resolution | B1 |
| C1 | Post-parent branch in the child pipeline (own message, locks, notice, no receipts) | B2 |
| C2 | Attention catalog: invite events | — |
| C3 | `beaconBudFromPost` | C1, C2, B3, B5 |
| C4 | Invite accept / decline / withdraw / supersede / expiry | A2, C3 |
| C5 | Closed Post | B1, C3 |
| C6 | Invite read projections + «Для вас» invite card data | C4 |
| C7 | Route credit provenance (approval + closure routing) | C4 |
| C8 | Constellation: `parentBeaconId`, anchor inheritance task | C3 |
| C9 | Concurrency suite | C3–C5 |
| D0 | Gate + client schema/gql/data layer | C3–C8 |
| D1 | Bud flow UI | D0 |
| D2 | Post room: notice, footer, closed state; Разговоры marker | D0, C5 |
| D3 | Activity invite card | D0, C6 |
| D4 | Child Request: parent link, People-tab invites | D0, C6 |
| D5 | Field `grewFrom` edge | D0, C8 |
| E1 | Remove conversion (client + server) + kind immutability | D1 |
| E2 | Repair converted Requests (#284) | E1, C4 |
| E3 | Flip gate, full suites, docs | all |

A1–A3 and B1–B5 can land on `main` before anything user-visible.

---

## 2. Prerequisites

### A1 — Detached published promotion

**Goal (Arch §10.3):** deleting a message that sourced a published child no longer violates `beacon_promotions_source_general_ck`.
**Files:** new migration `m0237.dart`; `test/data/database/m0237_promotion_source_detach_pg_test.dart`.
**Tests first (pg):**
1. Publish a child from a Request message, hard-delete the source message → succeeds; `beacon_promotions.source_message_id IS NULL`, `published_at` kept; child `parent_beacon_id` unchanged.
2. Inserting an **unpublished** promotion with NULL source still fails.
3. Upgrade path through `0236`.
**Steps:** drop + re-add the check as `CHECK (published_at IS NOT NULL OR source_message_id IS NOT NULL)` (read the current definition at m0193:5267 and keep its other clauses). Client: `isRedundantChildCreatedNotice` / footer must tolerate a missing source (widget test: notice with `sourceMessageId` of a deleted message renders without crash).
**Done when:** the pg test and `test/features/beacon_threads/` footer tests pass.

### A2 — Shared admission operation

**Goal (Arch §5.3):** one implementation of "admit with both confirmations"; `acceptHelpOffer` delegates; behaviour unchanged.
**Files:** `lib/domain/use_case/admission_operation.dart` (new, domain service using ports), `lib/domain/port/…` (actor-explicit methods), `coordination_repository.dart`, `beacon_room_repository.dart` (`inviteOfferUserToBeaconRoom` body extracted to an actor-explicit internal taking `confirmingAuthorId`), `commitment_repository.dart` (record with explicit actor, no nested `withMutatingUser`), `coordination_case.dart`.
**Tests first:**
1. **Golden row-set characterization (pg)** `test/domain/use_case/admission_row_set_pg_test.dart`: offer → `acceptHelpOffer`; snapshot rows in `beacon_help_offer`, `beacon_commitment_event`, `beacon_help_offer_coordination`, `beacon_help_offer_admission_event`, `beacon_participant`, room-joined activity, `trust_evidence` (approval). Passes before the refactor (characterization) and after.
2. Calling the operation with actor = helper and `confirmingAuthorId = author` inside one `withMutatingUser(helper)` unit produces the same row set (no `Nested mutating actor mismatch`).
3. Existing: `coordination_case_test.dart`, `help_offer_case_test.dart`, `beacon_room_admission_matrix_test.dart`, closure tests that read commitment facts.
**Steps:**
- `AdmissionOperation.admitWithConfirmations({beaconId, helperId, confirmingAuthorId, actorId, offerKind?})`: (a) ensure active offer + `offered` event (only if none active); (b) coordination `useful`, `author_user_id = confirmingAuthorId`; (c) room admission (role helper, committed, admitted; join reason `accept`); (d) admission event `accept`; (e) under `closure.lockRequest`: `acknowledged` event if transition + `applyMembershipEvent`; (f) `recordApprovalEdge`; (g) settle the author's `helpOfferSubmitted` obligation. Returns a result value; idempotent when already acknowledged.
- `CoordinationCase.acceptHelpOffer` keeps its pre-checks and delegates (a) is a no-op there (offer exists).
**Done when:** golden test + listed suites pass.

### A3 — Remove `BeaconRoomAdmit` (#283)

**Goal:** no admission path without both confirmations. The client has no caller (`BeaconThreadsCase.admit`, `beacon_threads_case.dart:301`, is unused).
**Files:** server `mutation_beacon_room.dart:235` (remove `beaconRoomAdmit`), `BeaconRoomCase.admit`, `BeaconRoomRepository.admitParticipant`, port, mocks; client `beacon_room_admit.graphql` + `_g`, `BeaconThreadsCase.admit`, repository method, `schema.graphql`.
**Tests first:** admission-matrix case "no V2 mutation admits without an active offer" (assert the field is absent from the schema); delete tests that only covered `admit`.
**Done when:** server non-pg + pg admission tests, client `test/features/beacon_threads/` pass; `grep -rn admitParticipant packages` empty. Close #283 in the commit.

## 3. Schema and access

### B1 — Schema

**Files:** new migration (next free, e.g. `m0238`), Drift table classes `beacon_bud_observers.dart`, `beacon_author_invites.dart`, `beacon_bud_commands.dart`; `beacon_forward_edges.dart` (add `contact_sweep_exempt`); `_migrations.dart`; pg test.
**SQL (Arch §2):**
- `beacon_bud_observer` (PK `(beacon_id, user_id)`, FKs, cascade on beacon).
- `beacon_author_invite` with the two partial unique indexes; FK `forward_edge_id ON DELETE SET NULL`; CHECK `status IN (0..5)`; trigger rejecting updates of `inviter_id, invitee_id, source_post_id, arrival_post_edge_id, warm, beacon_id`.
- `beacon_bud_command` (PK `(actor_id, client_command_id)`, `input_hash text`, `result jsonb`).
- `beacon_forward_edge.contact_sweep_exempt boolean NOT NULL DEFAULT false`.
- `beacon_post_shape_ck`: Post statuses `{0, 2, 3, 6}`.
- No Hasura tracking for the new tables (served by V2 only); add them to the "closure tables untracked" architecture test list.
**Tests first (pg):** each constraint (N5 uniqueness, immutable provenance, status check, shape check accepts 6 for Posts and still rejects 1/5/7/8), upgrade path.

### B2 — `E(P)` and invite eligibility

**Files:** same-unit migration with SQL functions; `lib/domain/port/post_bud_port.dart`; `lib/data/repository/post_bud_repository.dart`; pg tests.
**SQL:**
- `post_effective_members(p_post text) RETURNS TABLE(user_id text)` — author ∪ participants with `room_access = 3` passing `beacon_effective_admission`, minus `block_hides(post_author, u)`.
- `post_bud_invite_candidates(p_post text, p_budder text) RETURNS TABLE(user_id, warm boolean, eligible boolean, reason smallint)` — over `E(P) \ {budder}`: blocked with budder → ineligible; warm = in `post_first_response` or Post author; cold = `personVisiblePeerIds` predicate (`NOT block_hides AND (person_are_mutually_visible OR person_bond)`, reuse the SQL used by `person_visibility_repository.dart:82-130`); paused → reason `paused`; pending N5 slot → reason `alreadyInvited`.
- `post_bud_pretick(p_post, p_budder) RETURNS TABLE(user_id)` — D5: users the budder @mentioned in the Post (`beacon_room_message.mentions` on budder's messages) ∪ authors of messages with `reply_to_message_id` pointing at a budder message, intersected with eligible.
**Tests first (pg):** member blocked with Post author excluded; member blocked with budder ineligible; access-0 (cancelled forward) excluded; left (5) excluded; author included without a participant row; warm/cold classification; silent non-visible ineligible; pretick contents.

### B3 — Read wall

**Files:** new migration redefining `beacon_can_read_content`, `beacon_access_reasons`, `beacon_readable_ids`; `lib/domain/beacon_access_policy.dart`; tests.
**Change (Arch §3.2):** contextChild clause: when the immediate parent has `kind = 1`, require `EXISTS beacon_bud_observer(child, viewer)` instead of live parent membership (parent status not 2/3 still required). contextAncestor: add `AND anc.kind = 0`.
**Tests first (pg leak matrix)** `post_bud_read_wall_pg_test.dart`: snapshot observer reads child; member who joined the Post after the bud cannot; blocked observer cannot; Request helper/forward recipient of the child **cannot** read the Post; Request-parent shared context unchanged (existing #146 tests pass); `beacon_readable_ids` agrees with `beacon_can_read_content` on every row of the matrix; `BeaconAccessPolicy` unit test mirrors it.
**Note:** keep the function COST from m0227 and the perf characteristics of `beacon_readable_ids` (m0226); run the existing readable-ids perf/consistency tests.

### B4 — Hierarchy realtime recipients

**Files:** migration redefining the hierarchy recipient function (m0193:3925-3990); pg test.
**Change (Arch §3.4):** if the owner's parent (or the owner) is a Post-parented child, recipients = child direct audience ∪ `beacon_bud_observer`; for block / parent-deletion events include former recipients for invalidation.
**Tests first (pg):** later Post member receives no child hint; snapshot observer who left the Post still receives it; blocked observer receives only the invalidation.

### B5 — Contact sweep exemption + expiry resolution

**Files:** `forward_edge_repository.dart` `claimIgnoredContacts` (:508); migration with `contact_resolve_without_evidence(p_edge text)`; pg tests.
**Change:** sweep adds `AND NOT e.contact_sweep_exempt`. New function resolves an unresolved contact edge (outcome = cancelled/NULL as `contact_edge_on_cancel` does) without evidence.
**Tests first (pg):** exempt edge past deadline → no noisy; exempt edge + help offer → engaged; exempt edge + inbox decline → declined; `contact_resolve_without_evidence` on a past-deadline edge before the sweep → sweep skips it.

## 4. Server use cases

### C1 — Post-parent branch in the child pipeline

**Files:** `beacon_child_create_case.dart` (`_assertParentCreateAllowed` :464-487, publish :267/:293, notice + attention :406-449), `beacon_hierarchy_command_repository.dart` (`insertChildCreationNotice` payload), `BeaconPromotionEligibilityPolicy`, exceptions (`postChildRequiresBud`, `budSourceNotOwnMessage`, `postNotOpen`).
**Behaviour:**
- `beaconChildCreate` with a Post parent → `PostChildRequiresBudException` (the only Post entry is C3). The shared pipeline exposes a `PostParentStage` hook used by C3.
- Post branch asserts (Arch §3.1): parent `kind = 1, status = 0`; actor ∈ `E(P)`; `sourceMessageId` required; `source.author_id = actor`.
- Locks via `PostLockPort` first for Post parents (Arch §4.1).
- Notice payload adds `invitedCount` (int, default 0); for Post parents **no** attention receipts.
**Tests first:** use-case pg tests for each guard; Request-parent behaviour unchanged (existing hierarchy tests); `post_request_only_audit_pg_test.dart:324` updated: `beaconChildCreate` on a Post still rejected (now with the new code).

### C2 — Attention catalog

**Files:** `attention_models.dart` (`AttentionEventType` + `assertDeclared` :18-61), `attention_policy.dart`, `notification_kind.dart`, `docs/contracts/updates-event-contract.json` (bump schema), client `attention_event_classification.dart`, client mirrors + mirror tests.
**Events:** `authorInviteReceived` (to invitee; optional update; Activity; push allowed as for `relayReceived`), `authorInviteAccepted` (to inviter; optional update; no push), `authorInviteDeclined` (to inviter; optional update; no push), `authorInviteWithdrawn` (to invitee; clears the received receipt).
**Tests first:** catalog/contract tests fail on undeclared kinds; policy unit tests for recipients and `requiresAction = false`.

### C3 — `beaconBudFromPost`

**Files:** `lib/domain/use_case/post_bud_case.dart`, `lib/api/controllers/graphql/mutation/mutation_post_bud.dart` (+ `_mutations_all.dart`), input/result types, ports, `ForwardEdgeRepository.createBatch` option `sweepExempt`, inbox re-pin repository method, `beacon_bud_command` repository, exceptions.
**Input/Result:** Arch §4.2. Result: `{outcome, childBeaconId, invitees: [{userId, outcome: invited|notEligible|alreadyInvited|paused|blocked}]}`.
**Steps (one `runAction(actor = budder)` transaction):** replay check → locks → C1 Post-parent pipeline (create + publish child with content; discoverable default false) → observers snapshot (`post_effective_members` minus budder, minus blocked-with-budder) → per invitee: `post_bud_invite_candidates` row must be eligible; `createBatch` author→U on child, `sweepExempt = warm`, no parent edge; re-pin inbox (`status = 0`, `tombstone_dismissed_at = NULL`); `arrival_post_edge_id` = U's latest active inbound edge on the Post; insert invite; emit `authorInviteReceived` → notice with `invitedCount` → `closePost` (C5 function) → store command result → after-commit enqueue `anchor_inherit_bud` (C8).
**Tests first (pg, real attention dispatch):** happy path rows (child parent, observers, invites, edges with exempt flags, inbox pinned in «Для вас» via `eligiblePinned`, one notice with count, zero receipts to non-invited members); replay returns identical result with no new rows; replay with different input under the same `clientCommandId` → typed conflict; per-invitee failures; non-author budder from own message; budder from someone else's message rejected; closed Post rejected.

### C4 — Invite lifecycle

**Files:** `lib/domain/use_case/author_invite_case.dart`, mutations `beaconAuthorInviteAccept`, `beaconAuthorInviteDecline`, `beaconAuthorInviteWithdraw`; hooks in `HelpOfferCase.offerHelp` (supersede), `CoordinationCase.acceptHelpOffer` (supersede), lifecycle transitions (close/cancel/delete use cases — expiry), block cleanup.
**Behaviour (Arch §5):**
- Accept: locks → re-validate → `AdmissionOperation.admitWithConfirmations(actor = invitee, confirmingAuthorId = inviter)` → invite accepted → `authorInviteAccepted`. Idempotent.
- Decline: inbox decline path (`status = 2`) + invite declined + `authorInviteDeclined`.
- Withdraw (author): invite withdrawn; cancel the edge only if `ForwardCase` cancel rules allow; `authorInviteWithdrawn` clears the invitee's receipt; inbox item back to the state it would have as a plain forward.
- Supersede: invitee `offerHelp` with a pending invite → admitted via the operation, invite accepted. Author accepts an ordinary offer from a pending invitee → invite superseded.
- Expiry: child → cancelled / reviewOpen / closed / deleted → pending invites expired + `contact_resolve_without_evidence` on their edges, same transaction.
- Block cleanup: pending invites between the pair → withdrawn.
**Tests first:** golden row-set equality (accept vs offer+accept, reuse A2 snapshot helper) — **I7**; accept after cancel → typed error, no rows; double accept idempotent; decline → no evidence; withdraw of a read edge leaves the edge but the invite cannot be accepted; supersede both ways; expiry → no noisy after sweep (**I8**); Cancel gate: after accept, Cancel refused and Delete refused (`everAcknowledged`).

### C5 — Closed Post

**Files:** `post_case.dart` (leave/return guards :156-200), `beacon_room_case.dart` (send/edit/react/poll guards for `kind = 1 AND status <> 0`), forward guard (`ForwardCase._checkForward`), migration redefining `post_my_posts` (m0215:41) to include status 6 + `status` column, `beacon_repository.dart:74` `postSummary`, `PostSummary` server type; system notice kind for "Post closed" (or reuse hierarchy notice with a new payload kind — prefer a new `system_message_kind = 5` with payload `{childBeaconId}`, mirrored on client).
**Function:** `PostCloseOperation.closeForBud(post, child)` — status 6 + notice; called only from C3.
**Tests first:** every write path on a closed Post → typed error; reads still work for members; `post_my_posts` returns it with status 6; field query excludes it; kind-agnostic status audit list (Arch §12.3) each with a test or a written "not affected" reason in the commit.

### C6 — Invite read projections

**Files:** V2 queries `myPendingAuthorInvites` (invitee: invite id, beacon summary, inviter, note, created_at) and `beaconAuthorInvites(beaconId)` (author only: invitee, status, note); attention SQL so the «Для вас» row for an inbox item with a pending invite carries `inviteId` (join, no new inbox column).
**Tests first:** invitee sees own invite + note; author sees all invites on their child; observer/other gets empty/forbidden; Hasura has no select on the table (metadata test).

### C7 — Route credit provenance

**Files:** `closure_repository.dart` (`selectArrivalEdge` :785, `routingSource` :905, attribution :931), `closure_case.dart:860-886`, `closure_finalize_case.dart:238-261`, `forward_causal_graph_builder.dart`, env knob `TRUST_BUD_ROUTE_CREDIT_ENABLED`.
**Behaviour (Arch §7):** for a helper with an accepted invite: approval arrival = `arrival_post_edge_id`; closure causal input for that helper = the Post chain walked via `parent_edge_id` from the arrival edge (created before child `published_at`, not cancelled before), its attributions from Post batches, plus the helper's child-side chain. The delivery edge is a structural, non-crediting root. Flag off → today's behaviour.
**Tests first (pg + unit):** A→B→C in the Post, C invited and accepts → approval credit to B; closure routed evidence for A→B and B→C only; an unrelated Post path to C (D→C) earns nothing; cancelled Post edge excluded; C forwards the child onward to E, E helps → chain via the delivery edge root works, delivery edge earns nothing (**I9**); flag off → no cross-beacon credit.

### C8 — Constellation

**Files:** server `constellation_field_snapshot_reader.dart` + `custom_types.dart` (`ConstellationRequest.parentBeaconId`, only when the parent is a Post readable by the viewer), `constellationRequestSelectColumns`; task `anchor_inherit_bud` in `task_worker_case.dart` using `constellation_anchor_apply_ops` per viewer in `viewer_id` order, op id `bud:<child>:<viewer>`, insert-if-absent.
**Tests first (pg):** viewer with a Post anchor gets a child anchor at offset (open Post) / same coordinates (closed Post); viewer who already anchored the child keeps theirs; replay no-op; non-reader gets nothing; `parentBeaconId` NULL for a viewer who cannot read the Post.

### C9 — Concurrency suite

`post_bud_concurrency_pg_test.dart`: bud ∥ bud (same source message → one child, `alreadyPromoted`); accept ∥ child cancel; accept ∥ child delete; accept ∥ block; bud ∥ Post leave of an invitee; bud ∥ Post close; withdraw ∥ accept. No deadlocks (statement timeout set), invariants I1, I2, I6 hold after each race.

## 5. Client

### D0 — Gate, schema, data layer

`kPostBuddingEnabled = false`; fetch schema (§0 rule) or hand-edit `schema.graphql`; `.graphql` docs: `post_bud_from_post`, `author_invite_accept/decline/withdraw`, `my_pending_author_invites`, `beacon_author_invites`; domain entities `AuthorInvite`, `PostBudCommand`, `PostBudResult`; port + repository + use case `PostBudCase`, `AuthorInviteCase`; exception code mirrors; `PostSummary.status`; `ConstellationRequest.parentBeaconId` mapper. Tests: repository wire tests (variables, mapping, exception mapping).

### D1 — Bud flow UI

Invoke the `material-3-flutter` skill first.
- Entry: room message action «Оформить запрос» on own messages (`RoomCapabilities.post()` → `childPromotion` with `isOwnMessage` predicate; secondary-tap + visible action, never long-press only); Post ⋯ menu entry (author → root; others → source picker of own eligible messages).
- `BeaconCreateScreen` child mode with a Post parent (`BeaconCreateRoute(parentBeaconId:, sourceMessageId:)` reused; the cubit detects a Post parent): prefill via generalised `PostConversionCase.prefill` (rename to `MessagePrefillCase`), invite step (candidates from `post_bud_invite_candidates` via a V2 query added in C3 or D0; writers first; ineligible hidden; pre-tick from `post_bud_pretick`; warning above 5; per-invitee note), «Закрыть пост…» (default on iff all eligible members ticked or `E(P)` ≤ 2), discoverable off + warnings, submit → `beaconBudFromPost` with a stable `clientCommandId` per screen session (repeat-tap safe; pattern `request_publish_repeat_tap_test.dart`).
- Result: navigate to the child; snackbar lists invitees not invited (per-invitee outcomes).
**Tests:** cubit tests (prefill, pretick, default of the close checkbox, payload), widget tests (entry visibility own vs others, gate off hides everything, invite step ordering, warnings).

### D2 — Post room and Разговоры

`childCreated` notice for Post rooms renders `roomBudNotice` / `roomBudNoticeNoInvites` (payload `invitedCount`); footer on the source message (existing widget); closed Post: notice kind 5 + disabled composer + hidden write actions; Разговоры: closed Posts in «Затихли» with `postClosedMarker`. Tests: widget tests per state; closed Post hides reactions/forward/leave.

### D3 — Activity invite card

«Для вас» row with `inviteId` renders the invite card (inviter, note, Принять / Не смогу). Accept → `AuthorInviteCase.accept` → the row leaves the pinned zone (the Request is now in scope) and appears on My Work. Decline → existing decline UX. Tests: cubit + widget; optimistic state rollback on typed errors (invite expired/withdrawn).

### D4 — Child Request

Parent link «Вырос из поста» via `BeaconHierarchyParentLink` (shown only when the parent is readable; otherwise the generic reference); People tab: invites section for the author (status, note, withdraw). Tests: widget tests for author vs non-author.

### D5 — Field `grewFrom`

`ConstellationSceneEdgeKind.grewFrom` + both exhaustive switches (`constellation_scene_controller.dart:506-545`, `constellation_edge_style.dart:61-111`) + legend; `addEdge(srcId: parentBeaconId, dstId: childId)` when both nodes are present. Tests: scene-controller unit test (edge present iff both nodes), style test.

## 6. Removal, repair, ship

### E1 — Remove conversion + kind immutability

Server: Arch §10.1 list; migration replacing `beacon_kind_policy_guard` to reject any kind change. Client: Arch §9 "Removed" row; `_ConvertedToRequestNotice` stays. Tests: delete conversion tests listed in the research inventory (server 6 files + partials, client 10 files + partials — adjust partials, do not delete them); pg test: any `UPDATE beacon SET kind` → error (**I5**); kind-4 historical row still renders.

### E2 — Repair converted Requests (#284)

Data migration per Arch §10.2 + a report table or `RAISE NOTICE` summary. **Tests first (pg)** with fixtures for each class: acknowledged helper untouched; offer-without-ack → access reverted, offer pending, author obligation present; no-confirmation → access removed + pending invite (warm, arrival NULL) + inbox pinned; status-5/closed beacons untouched. Then I1 audit over the whole DB passes. Close #284.

### E3 — Ship

Flip `kPostBuddingEnabled`; run all suites (§0.2 of the shared rules, serially); custom lints; update docs: `CONTEXT.md` (Post children, budding, author invite, observers snapshot, two-confirmation rule, closed Post), `.cursor/rules/terminology.mdc` (no new nouns; «Оформить запрос» copy), `docs/Tentura_current_status_quo.md`, mark Q10 / A7 amendments in `post-and-constellation-composer-plan.md`, close #250 with a link to the design. Local e2e: budding happy path on the local stack (`local-debug` skill, QA login; email OTP sink).

## 7. Invariant → test map

| Invariant (Arch §11) | Unit / test |
|---|---|
| I1 committers acknowledged | A3, E2 audit pg test |
| I2 two confirmations | A2, A3, C4 |
| I3 no Post via contextAncestor | B3 |
| I4 snapshot observers | B2, B3 |
| I5 kind immutable | E1 |
| I6 one pending invite | B1, C3 |
| I7 identical row sets | A2, C4 |
| I8 warm / expired → no noisy | B5, C4 |
| I9 route credit chain only | C7 |
| I10 bud replay | C3 |
| I11 realtime snapshot | B4 |

## 8. Revision history

- rev 1 (2026-10-11): initial plan from architecture rev 2.
