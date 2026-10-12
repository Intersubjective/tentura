# Budding a Request from a Post — architecture

**Status:** rev 2.3 (2026-10-12). D3 amended: unlimited budding for any open-Post member (optional own-message prefill only). Astra review applied (§14); rev 2.1–2.2 fold in the plan-level reviews (implementation plan §9, §10). Not an implementation plan.
**Product design (decisions, Russian):** [`post-request-budding-design.md`](post-request-budding-design.md) — D1–D7, N1–N6.
This document turns those decisions into an architecture. It does not re-open them.
**Supersedes:** the in-place Post → Request conversion (`beaconConvertToRequest`, kind 1 → 0;
§4.6 / §5.8 of [`post-and-constellation-composer-plan.md`](post-and-constellation-composer-plan.md))
and the #250 idea (new Request + moved history + closed Post + all pre-ticked).
**Related issues:** #250 (redesign), #239 / #284 (conversion admits without consent; cleanup),
#283 (`BeaconRoomAdmit` without consent), #282 (private usefulness marks — out of scope).
**Baseline:** `main` at `7f535afff` (migrations up to m0236).

**Owner constraint (inherited):** maximal reuse, no duplicated code paths. Every new behaviour names
the existing machinery it rides on and the smallest seam it needs.

---

## 0. TL;DR

1. **A budded Request is a nested child of the Post** (`parent_beacon_id`), created by the **one**
   child-publication pipeline that `beaconChildCreate` already uses. Q10 is lifted for that path
   only. Posts still cannot be children.
2. **Who buds:** any effectively admitted member of an **open** Post, **unlimited** times (no
   own-message gate, no one-child-per-message cap on the Post path). An own message may optionally
   prefill the form; others' messages cannot be quoted. Request→Request promotion stays one child
   per source message.
3. **Observers are a snapshot** (`beacon_bud_observer`) of the Post's *effective, unblocked* members
   at bud time (N3). `contextAncestor` never grants read of a **Post**. Realtime hierarchy recipients
   follow the same snapshot.
4. **Invitations** (`beacon_author_invite`) hold the author's confirmation; delivery rides on a real
   `beacon_forward_edge` (inbox row, «Для вас» pin, decline, contact hooks reused). **Accept** runs one
   shared admission operation that writes exactly the rows offer + acknowledgement write. Invite
   withdrawal revokes the confirmation independently of edge cancellation.
5. **N1:** writers/reactors are invitable regardless of person visibility; silent members only through
   the normal visibility gate. Warm invites are **exempt from the ignore sweep** (persisted flag), not
   deadline-less, so engage/decline accounting still works.
6. **N5:** one pending invite per (inviter, invitee, source Post).
7. **D4 route credit:** per-helper provenance anchored to the accepted invite's arrival edge in the
   Post; only that chain earns credit (the delivery edge is sent by the author and earns nothing).
8. **Post fate:** stays open by default; optional close → new Post status **closed (6)**, read-only,
   still listed, off the field.
9. **Field:** anchor inheritance runs in a periodic sweep, nudged after the bud commits (insert-if-absent); `grewFrom` edge.
10. **Removal/repair:** conversion removed, `kind` immutable; converted Requests repaired from
    commitment history (#284) — helpers without their own confirmation become **pending invitees**;
    `BeaconRoomAdmit` gets the two-confirmation rule (#283); promotion-source deletion fixed by
    allowing a detached published promotion.

---

## 1. Evidence: what exists

| Need | Existing machinery (file:line) | Verdict |
|---|---|---|
| Child from a message | `beaconChildCreate` → `BeaconChildCreateCase.createChild` (`beacon_child_create_case.dart:57`); publish via `publishDraft` (`:267`, hierarchy lock first `:293`) | **Reuse** the pipeline; relax parent kind guard (`:476`) |
| Idempotency | `clientCommandId` + input hash (`:135-161`, hash `:562`) | **Extend**: hash covers the full bud input (§4.2) |
| One child per message | `beacon_promotions_published_source_uidx` (m0193:6631) | **Request path as is**; Post buds leave `source_message_id` null so the unique index does not cap them |
| Notice + attention on publish | `insertChildCreationNotice` (`beacon_hierarchy_command_repository.dart:397`), attention (`beacon_child_create_case.dart:406-449`) | **Reuse, single owner**: payload gains `invitedCount`; no attention receipts for Post parents |
| Footer on the source message | `BeaconChildPromotionFooter`, `RoomCapabilities.childPromotion` | **Reuse**; enable for Posts |
| Lifecycle notices | `BeaconLifecycleEffectsCase`, hierarchy outbox | **As is** (Request children); Posts excluded as *sources* |
| Shared-context read | `beacon_can_read_content` (m0193:663-714), `beacon_access_reasons` (bits 64/128), `beacon_readable_ids` (m0226:44), `BeaconAccessPolicy` | **Change** (§3.2) |
| Hierarchy realtime recipients | `realtime_beacon_hierarchy_*` (m0193:3925-3990, live membership `:3953`) | **Change** (§3.4) |
| Post locks | `PostLockPort.lockForPostMutation` (`post_lock_repository.dart:17`): global hierarchy lock → beacon advisory `4242` → row `FOR UPDATE` | **Reuse**; one lock order (§4.1) |
| Room gate for Posts | `_isBlockedFromPost` (`beacon_room_case.dart:156`) — block with the **Post author** | **Reuse** in the effective-member set |
| Engaged members | `post_first_response` (m0214) | **Reuse** (N1) |
| Committer rows | `CoordinationRepository.acceptHelpOffer` (`coordination_repository.dart:134`), `inviteOfferUserToBeaconRoom` (`beacon_room_repository.dart:1277`, author-scoped `:1284`), commitment recording (`commitment_repository.dart:51`, actor-scoped), `_recordAcknowledgedIfTransition` (`coordination_case.dart:243`) | **Extract** one admission operation (§5.3) |
| Inbox / «Для вас» / decline | `inbox_item_on_forward_insert` (m0193:2073, keeps existing status `:2080`), `eligiblePinned` (`attention_dismissible_sql.dart:65`), `contact_inbox_on_decline` (m0206) | **Reuse** + explicit re-pin on invite (§5.1) |
| Contact / noisy | `contact_edge_set_deadline`, `contact_engage` and decline (both need a deadline, m0206:68,99), sweep `claimIgnoredContacts` (`forward_edge_repository.dart:508`); noisy evidence written even with the wall off (`contact_resolution_sweep_case.dart:36`) | **Reuse** + sweep exemption flag (§6) |
| Forward cancel | `ForwardCase` cancel refuses read / forwarded-on / offered edges (`forward_case.dart:82`) | Not a withdrawal mechanism (§5.4) |
| Route credit | `selectArrivalEdge` (`closure_repository.dart:785`), `routingSource` (`:905`, attribution `:931`), `ForwardCausalGraphBuilder` (all inbound paths `:74`, missing parent rejected `:49`) | **Change**: per-helper provenance (§7) |
| Post lists | `post_my_posts` status 0 only (m0215:41), `postSummary` uses it (`beacon_repository.dart:74`), `PostSummary` DTO (client `post_summary.dart:6`) | **Change** for closed Posts (§2.3) |
| Anchors | `constellation_anchor` (m0236), viewer-scoped apply with lock/cursor/op log (`constellation_anchor_repository.dart:45`) | **Reuse** via a periodic sweep (§8.1) |

## 2. Data model

### 2.1 `beacon_bud_observer` (N3)

```
beacon_bud_observer(beacon_id text FK beacon ON DELETE CASCADE,  -- child Request
                    user_id   text FK user,
                    created_at timestamptz,
                    PRIMARY KEY (beacon_id, user_id))
```

Written once in the publication pipeline when the parent has `kind = 1`, from the **effective Post
member set** `E(post)`:
- the Post author (no participant row required), plus
- participants with `room_access = 3` (role 6 or steward) that pass `beacon_effective_admission(post, u)`,
- minus users blocked with the **Post author** (`_isBlockedFromPost` predicate) and minus users
  blocked with the **child author**, minus the child author.

Never extended. Leaving the Post later does not remove the row; a later block hides reads
(`block_hides`) as everywhere.

### 2.2 `beacon_author_invite` (D7 author confirmation)

```
beacon_author_invite(
  id text PK,
  beacon_id text,              -- child Request
  inviter_id text,             -- recorded author confirmation (== child author at creation)
  invitee_id text,
  source_post_id text,         -- parent Post (N5)
  forward_edge_id text NULL,   -- delivery edge author→invitee on the child
  arrival_post_edge_id text NULL, -- invitee's arrival edge in the Post at bud time (D4)
  warm boolean,                -- invitee ∈ post_first_response(source_post_id) or Post author
  note text NULL,              -- visible to inviter + invitee only
  status smallint,             -- 0 pending, 1 accepted, 2 declined, 3 withdrawn, 4 expired, 5 superseded
  -- source_post_id is NULL for repair invites (§10.2)
  created_at, resolved_at, resolved_by)
UNIQUE (inviter_id, invitee_id, source_post_id) WHERE status = 0     -- N5
UNIQUE (beacon_id, invitee_id) WHERE status = 0
```

Immutable provenance: `inviter_id`, `source_post_id`, `arrival_post_edge_id`, `warm` never change.
Read projection: the invitee sees their own invite (incl. note); the child author sees invites on
their child (status, note); **observers and others see nothing** (no Hasura select; served by V2
queries only). Named to avoid the existing `invitation` table.

### 2.3 Closed Post (status 6)

- `beacon_post_shape_ck`: Post statuses `{0, 2, 3, 6}`.
- Read-only guards (server, typed error): room message send/edit, reactions, forward, polls,
  `postLeave` / `postReturn`, further budding — all require `status = 0` for `kind = 1`.
- `post_my_posts` / `postSummary` return status 6 too; `PostSummary` gains `status`; Разговоры shows
  closed Posts in «Затихли» with a «закрыт» marker; the room shows a closed notice with a link to the
  child and the composer disabled.
- Field: excluded (`status = 0` filter already, `constellation_field_snapshot_reader.dart:201`).
- Lifecycle effects / inbox tombstone triggers are `kind = 0`-guarded already (m0213); audit every
  status switch that is kind-agnostic (§12.3).
- Only reachable through budding with `closePost = true`.

### 2.4 Kind immutability

`beacon_kind_policy_guard` (m0209:28) rejects **any** `kind` change.

### 2.5 Forward edge sweep exemption

`beacon_forward_edge.contact_sweep_exempt boolean NOT NULL DEFAULT false`. The deadline is still set
(so `contact_engage` and decline resolve normally); `claimIgnoredContacts` skips exempt edges.

### 2.6 Bud command record

One idempotency table: the existing `beacon_child_commands` (PK `(actor_user_id, client_command_id)`)
gains `bud_result jsonb` (child id, per-invitee outcome) and `anchor_inherited_at`. The hash of the
full normalised bud input (content, invitees + notes, `isDiscoverable`, `closePost`) goes into the
existing `normalized_input_hash` with a `bud:` prefix, so a `clientCommandId` reused across endpoints
conflicts. The already-promoted outcome also stores a `bud_result`. Replay
runs right after the global lock and **before** any parent assert, so it also works after
`closePost`.

## 3. Access model

### 3.1 Who may bud

`_assertParentCreateAllowed` gains a Post branch (instead of `requireRequest(parent)`):
- parent `kind = 1`, `status = 0`; actor ∈ `E(post)`;
- `sourceMessageId` **optional** (prefill / notice only). When set: `source.author_id = actor` and
  existing source eligibility; the promotion row still stores `source_message_id = NULL` so many
  buds may share the same (or no) message. Request parents: unchanged (one published child per
  source).

The Post branch is enforced inside the shared pipeline, so neither `beaconChildCreate` nor the new
mutation can create a Post child without it.

### 3.2 Reads of the child

In `beacon_can_read_content`, `beacon_access_reasons`, `beacon_readable_ids`, `BeaconAccessPolicy`:
- **contextChild:** immediate parent `kind = 1` → membership is a `beacon_bud_observer` row for
  (child, viewer); parent not deleted (status 2) — as today. Parent `kind = 0` → unchanged.
- **contextAncestor:** an ancestor with `kind = 1` is never granted.

Observer level = today's contextChild level: content, admitted helpers, offer help, forward, fork; no
chat, no involvement, no invite rows.

### 3.3 Invite eligibility (N1)

U is invitable on child C (parent Post P) iff, evaluated under the locks of §4.1:
- U ∈ `E(P)` at bud time, U ≠ C author, no block between C author and U;
- **warm:** U ∈ `post_first_response(P)` or U is P's author; **or cold:** the normal forward visibility
  gate passes (`personVisiblePeerIds`: mutual visibility or bond);
- U is not availability-paused (else outcome `recipientPaused`);
- N5 slot free.

Later invites from the child's People tab (`beaconAuthorInviteCreate`): only for C's snapshot observers, same rules. Everyone else:
ordinary forward (a direct author forward is **not** a confirmation).

### 3.4 Realtime

For a Post parent, `beacon_hierarchy` recipients are the child's direct audience + snapshot observers,
not live Post membership. Former recipients are included only for revocation invalidation (block,
parent deletion). Child-specific hints are never sent to live Post members outside the snapshot.

## 4. Budding (server)

### 4.1 Lock order (all operations touching a bud)

`global hierarchy lock → Post advisory(4242) + Post row FOR UPDATE (PostLockPort) → child advisory(4242)
(= closure.lockRequest key) + child row FOR UPDATE → invite rows FOR UPDATE (ordered by id)`.

Used by: bud, invite accept, invite withdraw, child close/cancel/delete (they already take the
hierarchy lock first), Post close, block cleanup touching invites. A concurrency test runs bud ∥
accept ∥ cancel ∥ delete ∥ block.

### 4.2 `beaconBudFromPost`

Input: `postId`, `sourceMessageId`, `clientCommandId`, Request draft content (`isDiscoverable` default
false), `invitees: [{userId, note?}]`, `closePost`.

One transaction:
0. Global lock, then the replay check on `beacon_child_commands` (§2.6), before any parent assert.
1. Remaining locks per §4.1; assert §3.1.
2. **Shared publication pipeline**, entered through `createChildUnderPost` (`beaconChildCreate` on a
   Post parent is refused). For a Post parent it keeps the client's title/description (no override
   from the source body) and takes `isDiscoverable` (default false; the column default is true).
   A Post-parent stage then, inside the same transaction:
   a. writes `beacon_bud_observer` (§2.1);
   b. for each invitee: assert §3.3; create the delivery edge author → U on the child via
      `ForwardEdgeRepository.createBatch` (no parent edge; `contact_sweep_exempt = warm`); set U's
      `inbox_item` to `status 0` and clear `tombstone_dismissed_at` (explicit re-pin, because the
      insert trigger keeps an existing status); insert `beacon_author_invite`;
   c. inserts the **single** `childCreated` notice with payload `{childBeaconId, sourceMessageId,
      title, invitedCount}` (title snapshot: non-observers cannot read the child) — visible to everyone in the Post (N6) — and **no** attention receipts for a
      Post parent;
   d. emits `authorInviteReceived` per created invite (optional update, Activity «Для вас», N4).
3. If `closePost`: Post status 6 + closed notice.
4. Store the result in `beacon_child_commands.bud_result` (hash in `normalized_input_hash`, `bud:` prefix).
5. After commit, nudge the anchor sweep (§8.1); no anchor work inside the bud transaction.

Hierarchy lifecycle deliveries whose **target** is a Post insert the notice row but emit no attention
(no pushes to live Post members, design §5.5).

Per-invitee failure (`PostBudInviteOutcome`: `notEligible`, `alreadyInvited`, `recipientPaused`, `blocked`) does
not fail the bud; it is part of the stored result.

## 5. Invitation lifecycle

### 5.1 Accept — `beaconAuthorInviteAccept(inviteId)`

Authenticated actor: the invitee. Under §4.1 locks, re-validate: invite `status = 0`, child
open-family, no block (inviter ↔ invitee), no existing acknowledged stake. Then call the shared
admission operation (§5.3) with `authorConfirmation = invite`. Mark invite accepted. Idempotent:
a repeated accept returns the accepted result without new events.

`contact_engage` fires from the help-offer insert (engaged evidence) as for any Request.

### 5.2 Decline

«Не смогу» = existing inbox decline (`inbox_item.status = 2`, `contact_inbox_on_decline` → declined,
no evidence, N2) + invite `status = 2` (same transaction via the use case, not a trigger).

### 5.3 Shared admission operation

`AdmissionOperation.admitWithConfirmations(beacon, helper, authorConfirmation, actor)` — one
implementation spanning: help offer upsert + `offered` event (if not active), coordination
`useful` (`author_user_id` = confirming author), room admission, admission event `accept`,
`acknowledged` event + `applyMembershipEvent`, approval credit (§7). It runs inside **one** mutating
unit for the authenticated actor and records the confirming author as data (no nested
`withMutatingUser`; the author-scoped wrappers in `inviteOfferUserToBeaconRoom` and commitment
recording get actor-explicit internals). `acceptHelpOffer` (author actor, confirmation = the helper's
active offer) delegates to the same operation. One code path, two entry points.

### 5.4 Withdraw, supersede, expiry

- **Withdraw** (author): invite `status = 3` revokes the confirmation regardless of the edge; the edge
  is cancelled only if `ForwardCase` cancel rules allow, else it stays as an ordinary forward.
- **Supersede:** if the invitee offers help through the ordinary path while an invite is pending, both
  confirmations exist → the offer is admitted through §5.3 and the invite becomes `accepted`. If the
  author accepts an ordinary offer from a pending invitee, the invite becomes `superseded (5)`.
  Either way the N5 slot frees.
- **Expiry:** one `AFTER UPDATE OF status` trigger on `beacon`: when a `kind = 0` beacon goes
  **terminal** (`{1, 2, 6}`), pending invites → `expired`, their delivery edges' contacts are resolved
  without noisy evidence and their receipts are cleared, in the same transaction. Review (5) does not
  expire invites (it can reopen); accept is refused while in review.
- **Block cleanup:** pending invites between the pair → `withdrawn`.

### 5.5 Two-confirmation rule elsewhere (#283)

`BeaconRoomCase.admit` is removed (no client caller; plan A3). Direct author forwards unchanged.

### 5.6 Attention catalog

New `AttentionEventType`s `authorInviteReceived`, `authorInviteAccepted`, `authorInviteDeclined`
(author-side optional update, no push); accept/decline/withdraw/supersede/expiry/block cleanup
clear the invitee's receipt via `AttentionSystemSettlementPort.clearAuthorInviteReceived`, declared in `AttentionEventTypeCatalog.assertDeclared`
(`attention_models.dart:18`), policy switches, `NotificationKind`, the updates contract
(`docs/contracts/updates-event-contract.json`) and the client classification.

## 6. Noisy-contact interaction

| Invite | Deadline | Ignore | Decline | Accept |
|---|---|---|---|---|
| Warm | set | **exempt** from the sweep | declined, no evidence | engaged |
| Cold | set | noisy evidence written (published only if the wall is enabled) | declined, no evidence | engaged |
| Expired (child terminal) | — | resolved, no evidence | — | — |

## 7. Route credit across the Post (D4)

Per-helper provenance, anchored to the accepted invite:
- **Approval credit:** for a helper admitted via an invite, the arrival edge is
  `arrival_post_edge_id`; credit to its sender unless it is the Request author or the helper
  (existing skip rules). NULL arrival (Post author, or arrival lost) → no approval credit.
- **Closure routing:** for that helper, the causal input is **only** the chain reached by walking
  `parent_edge_id` from `arrival_post_edge_id` inside the Post (edges created before the child's
  `published_at`, not cancelled before it), with its forward attributions loaded from the Post's
  batches, plus the helper's own child-side chain as usual. Other Post paths do not count.
- The invite **delivery edge** stays in the child's edge map as the root of onward forwards from the
  invitee; it is sent by the Request author, so it earns nothing (no flag needed).
- The Post chain enters closure routing as a per-helper extra segment with its own root sender (the
  Post author) and cutoff (the child's `published_at`), inside the same budget. Scope: invites with a
  `source_post_id`; repair invites (§10.2) keep today's routing.
- Reuse the existing normaliser and budgets; tests: unrelated Post paths, cancelled Post edges, later
  invites, onward forwards from an invitee.

## 8. Constellation

### 8.1 Anchor inheritance

There is no after-commit task mechanism (`TaskRepository` supports only image hashing), and anchor
writes go through the constellation scheduler in their own viewer-scoped transactions, so nothing runs
inside the bud transaction. A periodic sweep in `task_worker_case.dart` (nudged after the bud commits)
selects, without a row lock, `beacon_child_commands` rows with a `bud_result`, `result_state = 0` and
NULL `anchor_inherited_at`, and iterates viewers (budder included), each in its own transaction, in `viewer_id` order who have a live Post
anchor and can read the child; for each, applies an **insert-if-absent** child anchor through the
existing apply machinery in that viewer's scope (op id `bud:<child>:<viewer>`, replay-safe; never
overwrites a child anchor the viewer already moved). Coordinates: the Post's if `closePost`, else a
fixed small offset.

### 8.2 `grewFrom` edge

`ConstellationRequest.parentBeaconId` (only when the parent is a Post readable by the viewer); client
edge kind `grewFrom` (enum, both exhaustive switches, legend); drawn when both nodes are present.

### 8.3 Realtime

Existing `beacon` / `forward` hints → debounced field refetch. No new realtime kind.

## 9. Client

| Surface | Change |
|---|---|
| Post room message actions | «Оформить запрос» on own messages (optional prefill); `RoomCapabilities.post()` keeps `childPromotionOwnOnly` for that entry only |
| Post header / ⋯ | «Оформить запрос» for any member of an open Post (no own-message gate; form may open empty) |
| Bud screen | `BeaconCreateScreen` child mode with a Post parent; optional prefill from an own message; invite step: `E(P)` members, writers first, ineligible silent members hidden, D5 pre-tick heuristic, warning above N, note, «Закрыть пост…» (default per design §5.6), discoverable off + warnings |
| Post room | `childCreated` notice text «оформил(а) запрос «…», позвал(а) N человек»; closed notice + disabled composer. Post buds do not bind `beacon_promotions.source_message_id`, so there is no per-message child footer cap |
| Разговоры | closed Posts in «Затихли» with a marker (`PostSummary.status`) |
| Child Request | «Вырос из поста» parent link when the viewer can read the Post |
| Activity «Для вас» | invite card: inviter, note, «Принять» / «Не смогу» |
| Child People tab | invite statuses for the author; withdraw |
| Field | `grewFrom` edge |
| Removed | conversion UI, route params, cubit paths, `post_conversion_repository` mutation, `post_view_scope` kind swap, conversations keep-open on kind change, l10n `postConvert*` (keep `_ConvertedToRequestNotice`, used by `batonTaken`) |

## 10. Removal and repair

### 10.1 Removal

`beaconConvertToRequest`, `BeaconCase.convertToRequest`, `convertPostToRequest`,
`convertPostMembers`, `postConvertedToRequestMessage`, the kind-0 branch of `returnToPostAsAddressee`,
their tests. Keep the kind-4 constant + renderer for historical rows.

### 10.2 Repair of converted Requests (#284)

Scope: every open-family `kind = 0` beacon with an admitted non-author, non-steward participant
without an `acknowledged` event (converted Requests and historical `BeaconRoomAdmit` admits). Audit
each from commitment + admission history:
- has an `acknowledged` event (with or without later exit) → leave as is (history is consistent);
- has an active offer but no acknowledgement → keep the offer, **revert room access** to the
  ordinary "offer pending" state; the author decides as for any offer;
- no own confirmation at all (the conversion case) → remove room access and create a **pending
  `beacon_author_invite`** (the author's pick is the author confirmation; `warm = true`,
  `arrival_post_edge_id` NULL); the person accepts or declines like any invitee.
- Beacons in review (status 5) or closed/cancelled: **not modified** (frozen review membership and
  history stay as they are); listed in the migration report.

### 10.3 Promotion source deletion

Allow a **published** promotion to keep its child/parent identity after its source message is
deleted: drop `beacon_promotions_source_general_ck` (it forbids NULL sources on published rows; the
existing FK already sets the source to NULL on delete, and unpublished NULL rows are legal today).
`publishDraft` keeps rejecting a draft whose source is gone. The footer disappears with
the message; the child keeps its parent. Root-message deletion keeps deleting the Post (R4-3); the
child survives (soft delete, non-cascading).

## 11. Invariants and tests

- **I1** Every non-author, non-steward admitted participant on an open-family `kind = 0` beacon has an
  acknowledged commitment (pg audit; covers #283, #284, accept).
- **I2** No admission without both confirmations.
- **I3** A Post is never readable through `contextAncestor`.
- **I4** Observers = snapshot of `E(P)` at bud time; joining later grants nothing; blocked members never.
- **I5** `kind` never changes.
- **I6** ≤ 1 pending invite per (inviter, invitee, source Post).
- **I7** Invite accept and offer+accept produce identical row sets (golden comparison).
- **I8** Silent non-visible members are not invitable; warm invites never yield noisy evidence;
  expired invites never yield noisy evidence.
- **I9** Invite-admitted helpers credit only their recorded Post arrival chain; the delivery edge
  earns nothing.
- **I10** Bud replay returns the stored result with no new effects.
- **I11** Hierarchy realtime for Post children reaches only the snapshot + direct audience.
- Concurrency: bud ∥ accept ∥ cancel ∥ delete ∥ block ∥ Post close.
- Extend `post_request_only_audit_pg_test.dart`, `beacon_room_admission_matrix_test.dart`.

## 12. Remaining risks

1. Cross-beacon routing touches the trust core; consider a flag for §7 closure routing.
2. Anchor task volume (bounded by Post size; anchors are rare).
3. Status 6 on Posts: audit kind-agnostic status switches (client status menus, inbox, constellation
   status sets, lifecycle effects).
4. Invite card derivation in «Для вас» without a new inbox column (join on pending invite).

## 13. Revision history

- rev 1 (2026-10-11): initial architecture from design rev 1.4 and code research.
- rev 2 (2026-10-11): Astra review applied (§14).
- rev 2.2 (2026-10-11): third review folded in (anchor sweep without in-transaction work, terminal-only
  expiry, extra routing segments, single hash column, A1 drops the check).
- rev 2.1 (2026-10-11): plan-level review folded in (single idempotency table, Post content kept,
  discoverable default, notice title, lifecycle attention suppression, later-invite mutation,
  expiry trigger, anchor sweep, repair scope).

## 14. Astra review (gpt-6-astra, high, read-only) — disposition

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | blocker | Post-row-before-hierarchy lock order deadlocks with `PostLockPort` / child publish | §4.1 single order via `PostLockPort` + concurrency test |
| 2 | blocker | Accept validates outside the lifecycle lock; races Cancel/Delete | §5.1 locks first, re-validates inside |
| 3 | blocker | Raw role-6/access-3 rows are not an authorization snapshot (blocked members, access 0) | §2.1 effective unblocked set `E(P)`, author without a row |
| 4 | major | Child idempotency hash misses bud fields; double notice | §2.6 command record; single pipeline owns notice (§4.2) |
| 5 | major | Actor extraction incomplete (room admission and commitments are actor-scoped) | §5.3 one admission operation, confirming author as data |
| 6 | major | NULL deadline disables engage/decline; noisy written even with wall off | §2.5 sweep-exempt flag, deadline kept; §6 table corrected |
| 7 | major | Forward cancel ≠ withdrawal; stale invites hold N5 slot | §5.4 authoritative withdraw + supersede |
| 8 | major | Inbox status not reset on re-invite; paused/dedup; catalog and projections missing | §4.2 b re-pin; §3.3 paused; §2.2 projections; §5.6 catalog |
| 9 | major | Expired invites can still be swept as noisy | §5.4 expiry resolves contacts without evidence |
| 10 | major | Unioning Post edges credits unrelated paths; delivery edge removal breaks onward chains | §7 per-helper provenance; delivery edge structural |
| 11 | major | Repair keyed on "no active offer" is wrong; frozen review epochs | §10.2 history-based audit; invites for unconfirmed; review/closed untouched |
| 12 | major | Closed Posts vanish from `post_my_posts`/`postSummary`; guards missing | §2.3 enumerated |
| 13 | major | Reject forbidding source deletion; keep a detached published promotion | §10.3 adopted |
| 14 | major | Hierarchy realtime uses live membership and carries metadata | §3.4 snapshot recipients |
| 15 | major | Anchor copy can't run as a nested system actor | §8.1 after-commit task, insert-if-absent |
