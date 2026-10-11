# Budding a Request from a Post — architecture

**Status:** rev 1 (2026-10-11), draft for review. Not an implementation plan.
**Product design (decisions, Russian):** [`post-request-budding-design.md`](post-request-budding-design.md) — D1–D7, N1–N6.
This document only turns those decisions into an architecture. It does not re-open them.
**Supersedes:** the in-place Post → Request conversion (`beaconConvertToRequest`, kind 1 → 0;
§4.6 / §5.8 of [`post-and-constellation-composer-plan.md`](post-and-constellation-composer-plan.md))
and the #250 idea (new Request + moved history + closed Post + all pre-ticked).
**Related issues:** #250 (redesign), #239 / #284 (conversion admits without consent; cleanup),
#283 (`BeaconRoomAdmit` without consent), #282 (private usefulness marks — out of scope).
**Baseline:** `main` at `7f535afff` (migrations up to m0236).

**Owner constraint (inherited):** maximal reuse, no duplicated code paths. Every new behaviour below
names the existing machinery it rides on and the smallest seam it needs.

---

## 0. TL;DR

1. **A budded Request is a nested child of the Post.** It reuses child-request promotion
   (`beaconChildCreate`, `beacon_promotions`, the `childCreated` notice, the source-message footer,
   lifecycle notices, `parent_beacon_id`). Q10 ("no children of Posts") is lifted for the create
   path only. Posts still cannot be children.
2. **Who buds:** any admitted Post member (author or addressee), **only from their own message**
   (the Post author may also bud from the root). The Post must be open.
3. **Observers are a snapshot.** For a Post parent, the live `contextChild` grant is replaced by a
   snapshot table `beacon_bud_observer` written at bud time (N3). `contextAncestor` never grants
   read of a **Post** ancestor (otherwise everyone the Request is later forwarded to could read the
   Post).
4. **Invitations are author-confirmed help offers waiting for the helper.** A new table
   `beacon_author_invite` holds the pre-acknowledgement; delivery rides on a normal
   `beacon_forward_edge` author → invitee on the child (inbox row, «Для вас» pin, decline,
   contact/noisy hooks all reused). **Accept** = help offer + acknowledgement + admission in one
   transaction, producing the same rows as `acceptHelpOffer` (the invitee becomes a proper
   committer). **Decline** = the existing inbox decline (no evidence, N2).
5. **Eligibility to invite (N1):** a Post member who **wrote or reacted** in the Post
   (`post_first_response`) is invitable regardless of person visibility; a silent member only if the
   normal forward visibility gate passes. Engaged invitees are "warm": their contact edge gets no
   noisy deadline. Silent invitees are "cold": normal deadline.
6. **One pending invite** per (inviter, invitee, source Post) (N5).
7. **Route credit is inherited (D4):** the invite records the invitee's arrival edge in the Post;
   approval credit and closure routing follow that chain across the Post → Request boundary.
8. **Post fate:** the Post stays open by default. Optional "close the Post and continue in the
   Request" moves it to a new **closed** Post status (read-only, off the field).
9. **Field:** the child inherits the Post's anchor for viewers who had one (offset if the Post stays
   open); a new `grewFrom` edge links them when both are on the field.
10. **The in-place conversion is removed**, `kind` becomes fully immutable, and existing converted
    Requests are repaired once (#284). `BeaconRoomAdmit` gets the two-confirmation rule (#283).

---

## 1. Evidence: what exists

| Need | Existing machinery (file:line) | Verdict |
|---|---|---|
| Child from a message | `beaconChildCreate` → `BeaconChildCreateCase.createChild` (`beacon_child_create_case.dart:57`); publish via `BeaconCase.publishDraft` → `BeaconChildCreateCase.publishDraft` (`:267`) | **Reuse**; relax the parent kind guard (`:476`) |
| One child per message, idempotency | unique `beacon_promotions_published_source_uidx` (m0193:6631); `clientCommandId` + input hash (`:135-161`); `alreadyPromoted` outcome | **As is** |
| Source eligibility | `BeaconPromotionEligibilityPolicy.isEligible`; SQL `beacon_promotions_consistency_guard` (m0193:1121) | **As is** + Post rule "own message" |
| Notice in the parent room | `insertChildCreationNotice` (`beacon_hierarchy_command_repository.dart:397-450`), `system_message_kind = 2` | **Reuse**; payload gains `invitedCount`; no attention receipts for Post parents |
| Footer on the source message | `BeaconChildPromotionFooter`, gated by `RoomCapabilities.childPromotion` | **Reuse**; enable for Posts |
| Lifecycle notices to the parent | `BeaconLifecycleEffectsCase` + hierarchy outbox, `system_message_kind = 1` | **As is** |
| Shared-context read | `beacon_can_read_content` contextChild / contextAncestor (m0193:663-714), `beacon_access_reasons` (bits 64/128), `beacon_readable_ids` (m0226:44-101), `BeaconAccessPolicy` | **Change**: Post parents use a snapshot; Post ancestors never granted |
| A7 (no bond from Post membership) | `person_bond`, `person_bond_peers`, `person_shared_contexts` filter `kind = 0` (m0210:68-121) | **As is** |
| Engaged Post members | `post_first_response(beacon_id, user_id, source_kind, source_id)` (m0214) | **Reuse** as the N1 set |
| Post member list | `postMemberUserIds` (`beacon_repository.dart:648`) | **Reuse** |
| Prefill from a message | client `PostConversionCase.prefill` / `fetchRootContent` | **Reuse**, generalised to any source message |
| Inbox row, «Для вас» pin, decline | `beacon_forward_edge` → `inbox_item_on_forward_insert` (m0193:2073); `eligiblePinned` (`attention_dismissible_sql.dart:65`); `contact_inbox_on_decline` (m0206) | **Reuse** via a real forward edge |
| Committer rows | `CoordinationRepository.acceptHelpOffer` (`coordination_repository.dart:134`), `inviteOfferUserToBeaconRoom` (`beacon_room_repository.dart:1277`), `_recordAcknowledgedIfTransition` (`coordination_case.dart:243`), `recordApprovalEdge` | **Reuse** through actor-agnostic variants (§5.3) |
| Contact / noisy | deadline trigger `contact_edge_set_deadline`, `contact_engage` (fires on help-offer insert), sweep `claimIgnoredContacts` (m0206; `forward_edge_repository.dart:508`) | **Reuse**; warm invites get no deadline |
| Route credit | `selectArrivalEdge` (`closure_repository.dart:785`), `routingSource` (`:905`), `ForwardCausalGraphBuilder` (`forward_causal_graph_builder.dart:24`) | **Change**: cross-beacon arrival for invite-admitted helpers |
| Anchors | `constellation_anchor` (m0236), `constellation_anchor_apply_ops` | **Reuse**; server-side copy at bud time |
| Field edges | client `ConstellationSceneEdgeKind` (`constellation_scene_controller.dart:26`), `constellation_edge_style.dart:61` | **New** edge kind `grewFrom` |

What does **not** exist: `beacon_author_invite`, `beacon_bud_observer`, a closed Post status,
cross-beacon arrival credit, anchor copy, `parentBeaconId` on `ConstellationRequest`.

## 2. Data model

### 2.1 `beacon_bud_observer` (snapshot of Post members, N3)

```
beacon_bud_observer(
  beacon_id   text  -- the child Request (FK beacon ON DELETE CASCADE)
  user_id     text  -- FK user
  created_at  timestamptz
  PRIMARY KEY (beacon_id, user_id)
)
```

Written once, inside the publish transaction of a child whose parent has `kind = 1`:
the Post author + every Post participant with `role = 6 AND room_access = 3`, minus the child's
author. Never added to afterwards. Blocks still override reads (`block_hides`). Leaving the Post
later does **not** remove the row (the snapshot is the point).

### 2.2 `beacon_author_invite` (author-side confirmation, D7)

```
beacon_author_invite(
  id                     text PK
  beacon_id              text  -- child Request
  inviter_id             text  -- == child author
  invitee_id             text
  source_post_id         text  -- parent Post (denormalised for N5)
  forward_edge_id        text  -- delivery edge author→invitee on the child (FK, ON DELETE SET NULL)
  arrival_post_edge_id   text  NULL -- invitee's arrival edge in the Post at bud time (D4)
  warm                   boolean   -- invitee ∈ post_first_response(source_post_id) at bud time
  note                   text NULL -- personal note (shown on the invite card)
  status                 smallint  -- 0 pending, 1 accepted, 2 declined, 3 withdrawn, 4 expired
  created_at, resolved_at
)
UNIQUE (inviter_id, invitee_id, source_post_id) WHERE status = 0   -- N5
UNIQUE (beacon_id, invitee_id) WHERE status = 0
```

Name chosen to avoid the existing `invitation` table (account / share-link invites). The table is
generic (`source_post_id` nullable in principle), but the only writer in this scope is budding:
**a direct author forward is not an author confirmation** (owner decision, design §3).

### 2.3 Closed Post status

`beacon_post_shape_ck` allows Post statuses `{0, 2, 3}` (open, deleted, draft). Add **6 (closed)**
for Posts. Closed Post = read-only room (no messages, reactions, forwards, leave/return), excluded
from the field query (`kind = 1 AND status = 0`, `constellation_field_snapshot_reader.dart:201`) and
from «Сейчас» in Разговоры; still readable by its members; shows a closed notice linking to the child.
Transition only via budding with `closePost = true` (no standalone "close Post" action in this scope).

### 2.4 Kind immutability

Replace `beacon_kind_policy_guard` (m0209:28) so **any** `kind` change is rejected (today 1 → 0 is
allowed for conversion).

## 3. Access model

### 3.1 Who may bud

`BeaconChildCreateCase._assertParentCreateAllowed` gains a Post branch instead of
`requireRequest(parent)`:

- parent `kind = 1`, `status = 0`;
- actor passes `beacon_effective_admission(parent, actor)` (author or role-6 admitted), not blocked;
- `sourceMessageId` is **required** for a Post parent, and the source message's `author_id = actor`
  (the root message counts as the Post author's own);
- existing eligibility rules for the source message apply.

Request parents keep today's rules (any admitted participant, source optional).

### 3.2 Reads of the child (observers)

`beacon_can_read_content`, `beacon_access_reasons`, `beacon_readable_ids` and `BeaconAccessPolicy`
change in one coherent way:

- **contextChild:** if the immediate parent has `kind = 1`, membership is read from
  `beacon_bud_observer` (row for (child, viewer)), not from live parent participation. Parent must
  not be deleted (status 2) — same as today's rule. Draft children stay author-only.
- **contextAncestor:** an ancestor with `kind = 1` is **never** granted. Child members read the
  Post only if they are Post members in their own right.

Observer level grants what contextChild grants today: content, admitted helpers, offer help,
forward, fork; no chat, no involvement. This is exactly N3 + "observers can offer help themselves".

Realtime `beacon_hierarchy` recipients (m0193:3925) may still include live Post addressees; they
get an invalidation hint and a refetch that the read wall answers correctly. Not a leak (hints
carry no data); filtered later only if noise shows up.

### 3.3 Invite eligibility (N1)

Invitee U is eligible when all hold:
- U is a Post member at bud time (`postMemberUserIds` ∪ Post author), U ≠ child author;
- no block between child author and U (`block_hides`);
- U has not left the Post (`room_access <> 5`);
- **either** U ∈ `post_first_response(post)` (or U is the Post author) — **warm**,
  **or** the normal forward gate passes (`personVisiblePeerIds` → mutual visibility or bond) — **cold**.

The visibility bypass applies only to this path; `ForwardCase._checkForward` is unchanged.

## 4. Budding flow (server)

One mutation, **`beaconBudFromPost`**, one transaction (no client-side chaining — same principle as
`postPublish`):

Input: `postId`, `sourceMessageId`, `clientCommandId`, Request draft content (title, description,
needs, schedule, cover, `isDiscoverable` default false), `invitees: [{userId, note?}]`,
`closePost: bool`.

Order inside the transaction (lock order: Post row → hierarchy mutation scope → child):

1. Lock the Post (`FOR UPDATE`), assert §3.1.
2. Create + publish the child through `BeaconChildCreateCase` internals (same code path as
   `beaconChildCreate` + `beaconPublish`; idempotent on `clientCommandId`).
3. Write `beacon_bud_observer` snapshot (§2.1).
4. For each invitee, assert §3.3 and N5; create the delivery forward edge author → U on the child
   (via `ForwardEdgeRepository.createBatch`, parent edge NULL, `contact_deadline_at` cleared when
   warm — §6); insert `beacon_author_invite` with `arrival_post_edge_id` = U's latest active inbound
   forward edge on the Post (NULL for the Post author), `warm`, `note`.
5. Insert the `childCreated` notice into the Post room with payload `{childBeaconId,
   sourceMessageId, invitedCount}` (N6: everyone in the Post sees it). **No attention receipts** to
   Post members for a Post parent; invitees are notified by their invite (step 7).
6. If `closePost`: set Post status 6; insert the closed notice.
7. Attention: an `authorInviteReceived` intent per invitee (optional update; lives in Activity
   «Для вас», **not** an obligation, N4).
8. Anchor copy (§8.1).

Outcomes mirror `beaconChildCreate` (`created`, `alreadyPromoted`, …) plus per-invitee rejections
(`notEligible`, `alreadyInvitedFromThisPost`). Partial invitee failure does not fail the bud; the
result lists rejected invitees.

**Later invites** (after the bud, from the child's People tab) use the same eligibility for
snapshot observers; for everyone else the author forwards as usual (direct forward ≠ invite).

## 5. Invitation lifecycle

### 5.1 Accept — `beaconAuthorInviteAccept(inviteId)`

Actor: invitee. One transaction; produces **exactly** the rows `offerHelp` + `acceptHelpOffer`
would, so every downstream predicate (`everAcknowledged`, `hasCurrentStake`, Cancel/Delete gates,
review composition, `beacon_admitted_helper`) works unchanged:

1. Lock invite row; assert `status = 0`, child open-family, no block, invitee still not blocked by
   author.
2. Upsert `beacon_help_offer` (status 0; offer kind per beacon status, as `offerHelp`).
3. Commitment event `offered`.
4. Upsert `beacon_help_offer_coordination` `response_type = useful`, `author_user_id = inviter`.
5. `inviteOfferUserToBeaconRoom` (role helper, committed, admitted; join reason `accept`).
6. `beacon_help_offer_admission_event` action `accept`.
7. Commitment event `acknowledged` + `applyMembershipEvent` (under `closure.lockRequest`).
8. Approval credit (§7).
9. Invite `status = 1`; inbox item → watching/scope (the beacon enters responsibility scope via the
   active offer, so the «Для вас» pin drops by itself).
10. Attention: `authorInviteAccepted` to the inviter (optional update).

`contact_engage` fires from the help-offer insert trigger (engaged evidence), as for any Request.

### 5.2 Decline

The invite card's «Не смогу» = existing inbox decline (`inbox_item.status = 2`) → `contact_inbox_on_decline`
(outcome declined, no evidence, N2); an `AFTER UPDATE` hook sets the invite `status = 2`. The
inviter sees «не сможет» on the People tab; no notification.

### 5.3 Actor seam

`withMutatingUser` refuses nested actors (`tentura_db.dart:256-263`), and the accept repos run as the
author. Extract **actor-explicit** internals (e.g. `acceptHelpOfferAsAuthorConfirmed(beacon, helper,
authorId)` sharing the body of `CoordinationRepository.acceptHelpOffer`), called inside a
`withMutatingUser(invitee)` unit. `_prepareAdmissionAction`'s "actor is author/steward" check is
replaced in this path by "a pending `beacon_author_invite` from the author exists". One shared
implementation; `acceptHelpOffer` delegates to it.

### 5.4 Withdraw / expiry

- Author withdraws: cancel the forward edge (existing cancel path) + invite `status = 3`.
- Child leaves open-family (close / cancel / delete): pending invites → `status = 4`; inbox
  tombstones already cover the card (`beacon_apply_inbox_before_response_tombstone`).
- Invitee blocked either way: pending invite → `status = 3` in the block cleanup.

### 5.5 Two-confirmation rule elsewhere (#283)

`BeaconRoomCase.admit` on `kind = 0` must require an active help offer from the target, honour
blocks and go through the shared acknowledgement implementation (§5.3), or be removed if no client
surface needs it. Direct author forwards stay as today (offer → author accept).

## 6. Noisy-contact interaction

The delivery edge is a real forward edge, so m0206 applies unchanged except for the deadline:

| Invite | Deadline | Ignore → | Decline → | Accept → |
|---|---|---|---|---|
| Warm (engaged in Post) | none (`contact_deadline_at NULL`) | nothing | declined, no evidence | engaged |
| Cold (silent, visible by normal rules) | normal (7 d ± 1) | noisy (if wall enabled) | declined, no evidence | engaged |

Mechanism: `contact_edge_set_deadline` skips edges flagged warm. Preferred seam: a session setting
(`tentura.contact_warm_edge = '1'`) set by the bud transaction around the warm inserts, read by the
trigger — no new column on the edge. (Alternative: a boolean column; reviewer to choose.)

## 7. Route credit across the Post (D4)

Today both credit paths filter edges on the child's `beacon_id` (`selectArrivalEdge`,
`routingSource`), so an invite-admitted helper's arrival sender is the author → no credit.

Change:
- **Approval credit:** for a helper admitted through `beacon_author_invite`, the arrival edge is
  `arrival_post_edge_id` (the invitee's arrival in the Post). Credit goes to that edge's sender
  unless it is the Request author or the helper (existing skip rules).
- **Closure routing:** `routingSource(child)` unions the parent Post's forward edges created before
  the child's `published_at`, and `ForwardCausalGraphBuilder` accepts a chain whose root sender is
  the **Post author** (not only the Request author) when the helper's arrival is via an invite with
  `arrival_post_edge_id`. The invite delivery edge itself is excluded from the causal graph
  (sender = Request author; it carries no routing).
- Post-phase **usefulness** is not credited (D6).

Sybil exposure is unchanged versus ordinary Requests (forward chains are already cheap to build).

## 8. Constellation

### 8.1 Anchor inheritance

In the bud transaction, for every viewer V with a live anchor on the Post who can read the child
(child author, invitees, snapshot observers): upsert a child anchor at the Post's coordinates —
same position if `closePost`, otherwise offset by a fixed small vector in anchor units. Uses
`constellation_anchor_apply_ops` semantics (revision bump, op log) under a system actor.

### 8.2 `grewFrom` edge

- Server: `ConstellationRequest` gains `parentBeaconId` (only when the parent is a Post readable
  by the viewer; NULL otherwise — never leaks a Post id to non-members).
- Client: new `ConstellationSceneEdgeKind.grewFrom` (enum + both exhaustive switches + legend);
  added when both nodes are in the scene (`addEdge` drops it otherwise).
- Closed Post: not on the field (status filter), so no edge.

### 8.3 Realtime

Bud creates a beacon and edges → existing `beacon` / `forward` hints → debounced field refetch. No
new realtime kind. The Post view refreshes through `childCreated` (room message) and
`beacon_hierarchy` hints.

## 9. Client

| Surface | Change |
|---|---|
| Post room message actions | «Оформить запрос» on **own** messages (and the root for the author); `RoomCapabilities.post()` gets `childPromotion = true` with an own-message predicate |
| Post header / ⋯ | «Оформить запрос» entry (from root message for the author; for others opens a source-message picker of their own messages) |
| Bud screen | `BeaconCreateScreen` in child mode with a Post parent: prefill from the source message (`PostConversionCase.prefill`, generalised); **Invite step**: Post members, writers first, eligibility per §3.3 (silent non-visible members not listed), pre-ticked per D5 heuristic (members the budder @mentioned or who replied to the budder), warning above N ticked, optional note, «Закрыть пост…» checkbox (default per design §5.6), discoverable off + warnings |
| Post room | `childCreated` notice renders «оформил(а) запрос «…», позвал(а) N человек»; footer on the source message; closed notice for closed Posts; composer disabled when closed |
| Child Request | parent link «Вырос из поста» (existing `BeaconHierarchyParentLink`; shown only when the viewer can read the Post, otherwise generic) |
| Activity «Для вас» | invite card variant: inviter, note, «Принять» / «Не смогу» |
| People tab of the child | invite statuses (pending / не сможет) for the author |
| Field | `grewFrom` edge |
| Removed | `PostAction.convertToRequest`, `_confirmConvert`, «Превратить в запрос» tile, convert params on `BeaconCreateRoute`, `submitConversion`, `post_conversion_repository` mutation, `post_view_scope` kind swap, conversations pane kind-change keep-open, l10n `postConvert*` |

## 10. Removal and repair

- Remove `beaconConvertToRequest`, `BeaconCase.convertToRequest`, `convertPostToRequest`,
  `convertPostMembers`, `postConvertedToRequestMessage`, the kind-4 conversion branch of
  `returnToPostAsAddressee`, and their tests. Keep the kind-4 constant + renderer for history rows.
- **#284 repair migration** (one-off, data only) for Requests with a kind-4 system row: for each
  admitted non-author non-steward helper without an active `beacon_help_offer`:
  - if they wrote in the room after conversion → backfill offer + `offered` + `acknowledged`
    events + coordination `useful` + admission event (they took part);
  - otherwise → remove from the room (participant delete; m0224 cleanup trigger handles the rest).
- **Promotion source delete bug** (found during research, applies to Requests too): hard-deleting a
  message that sourced a published child violates `beacon_promotions_source_general_ck`
  (m0193:5267 vs FK `ON DELETE SET NULL` m0193:7588). Fix: forbid deleting a promotion source
  (UI hides delete; server returns a typed error) — or soft-delete the body. Reviewer to choose.

## 11. Invariants and tests

- **I1** Every non-author, non-steward admitted participant on `kind = 0` has an acknowledged
  commitment (pg audit test; covers #283, #284, accept path).
- **I2** No admission without both confirmations: author (ack or invite) + helper (offer or accept).
- **I3** A Post is never readable through `contextAncestor`.
- **I4** Observers of a budded child = snapshot; joining the Post later grants nothing.
- **I5** `kind` never changes.
- **I6** At most one pending invite per (inviter, invitee, source Post).
- **I7** Invite accept produces the same row set as offer + accept (golden comparison test).
- **I8** Silent, non-visible Post members are not invitable; warm invites never produce noisy evidence.
- **I9** Route credit for an invite-admitted helper follows the Post chain; the delivery edge earns nothing.
- Extend `post_request_only_audit_pg_test.dart` (Post may be a parent only via budding; all other
  Request-only guards stay), `beacon_room_admission_matrix_test.dart`.

## 12. Risks and open points for review

1. **Nesting reuse vs. a separate link.** Reuse of `parent_beacon_id` brings lifecycle notices,
   footer, idempotency for free but forces kind branches into four access functions. Alternative:
   a separate `budded_from_post_id` with its own observer clause. This plan picks nesting.
2. **Promotion actor check for Posts.** Today any admitted member may promote any eligible message;
   the Post branch adds "own message only". Make sure the shared promotion source table/guards do
   not let a Request-path call bypass it with a Post parent.
3. **Cross-beacon routing** touches the trust core (`ForwardCausalGraphBuilder`). Needs focused
   tests and possibly a feature flag.
4. **Anchor copy for many viewers** in the bud transaction (bounded by Post size; anchors are rare).
5. **Warm-edge seam** (session setting vs column).
6. **Closed Post status 6** reuses the Request "closed" value; check every `kind`-agnostic status
   switch (inbox tombstones, lifecycle effects, hierarchy notices) for unintended effects.
7. **Activity placement of invites**: `eligiblePinned` requires `inbox_item.status = 0` and
   `kind = 0` — satisfied; confirm the card variant can be derived without a new inbox column.

## 13. Revision history

- rev 1 (2026-10-11): initial architecture from design rev 1.4 and code research.
