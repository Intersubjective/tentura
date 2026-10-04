# Post + creating Posts/Requests in Constellation — plan

**Status:** rev 5 (2026-10-02). All owner decisions are taken (§3, §3a). Rev 4 applied the Codex
(gpt-6.1-sol, high) review of rev 3 (18 findings; §10); rev 5 applies the design-level findings of
the Codex review of the step plan (§10). The step-by-step implementation plan is
`docs/plans/post-implementation-steps.md`.
**Baseline:** `main` after the episode-closure + trust redesign was merged (2026-10-02): closure lifecycle, trust ledger, noisy-contact wall,
no review subsystem, migrations up to m0207; `main` (2026-10-02) also has m0208 (`utc_today()`). This plan treats that state as the working product.
**Branch:** `feature/post-constellation` (on top of `main`).
**Spec source:** owner brief (2026-09-30, Russian) — Post as a light social object, forward policy,
creating Posts and Requests directly on the Constellation graph with "web" edges and an audience
radius, post-publish relay spread, activity-based fading, one-way Post → Request.
**UX:** `docs/plans/post-ux-mockups.md` (ASCII mockups, all copy).

**Primary constraint (owner):** maximal reuse, no duplicated code paths. The plan is organised
around *where the existing machinery already does the job* and the smallest seam that lets it do
the job for a Post as well.

---

## 0. TL;DR

1. **A Post is a `beacon` with `kind = 1`** (Requests are `kind = 0`). Not a new table, entity or
   route. Room, forward edges, inbox rows, attention receipts, realtime kinds, attachments, blocks,
   rate limits, deep links, share links and the forward screen are keyed by `beacon.id` and are
   reused. Post → Request is an in-place, validated `kind` flip.
2. **The Post is its room.** Its content is the author's first room message (the *root message*).
   The beacon row carries no title/description. The Post screen is the room only, plus an overflow
   menu.
3. **Forward edge = Post membership.** For `kind = 1`, an active inbound forward edge materialises a
   `beacon_participant` row with role `addressee` (6) and `room_access = admitted` (3), via a DB
   trigger. Existing room gates then work. Blocks are enforced at the room gate (§4.7).
4. **One server transaction publishes a Post** (`postPublish`): publish the draft, forward to the
   recipients (admission happens here), then write the root message (mentions resolve against the
   now-admitted audience). No client-side multi-mutation sequence, so there is no partial state to
   recover from.
5. **Forward policy «Можно пересылать»** — Posts only. Default **on**; the author may switch it off
   before sending; after publish it is one-way (off → on). One column, one policy function used by
   every edge-creating path (forward, invite create, invite accept).
6. **Request-only behaviour is enforced server-side**: one Dart guard
   (`BeaconKindPolicy.requireRequest`) on every Request-only use case and room mutation, `kind = 0`
   in Request-only SQL and Hasura write permissions, and a DB trigger that rejects help offers on
   Posts. An audit pg test proves it.
7. **The graph composer is a second view of the existing create flow**: same `BeaconCreateCubit`,
   same `ForwardCubit` selection. One selection-intent adapter serves both the graph and the list
   picker.
8. **Membership webs on the graph** (only for the selected object): object → *forwarded to* and
   object → *inside*, two colours, only to people already on ego's map; the rest is "+N". The
   forward chain is never drawn on the map; it lives on the existing forward-graph screen.
9. **Fading** uses one new column `beacon.last_activity_at`.

---

## 1. What exists and what is reused (evidence)

| Need from the brief | Existing machinery | Reuse verdict |
|---|---|---|
| Object addressed to chosen people | `beacon` + `beacon_forward_edge` (`m0193.dart:5054`); a published Request's audience is already "forward edges made at create time" (`beacon_create_cubit.dart:983-1021`) | **As is** |
| Own room with replies + reactions | `beacon_room_message`, `_reaction`, `_attachment`, polls, `beacon_room_seen`, realtime `room_*` kinds, `BeaconRoomCase` — all keyed by `beacon_id` | **As is on server** (+ block check, §4.7); client needs the `RoomHost` seam (§5.3) |
| Same relay mechanics + recipient screen | `ForwardCase.forward` (`forward_case.dart:160-339`), `ForwardCubit`, `ForwardRecipientPicker` (`embedded: true`) | **As is**, sections gated by `ForwardTargetProfile` |
| New recipients see history | `listMessages` returns full General history to any admitted member | **As is** once forward ⇒ admission (§4.2) |
| Photo / meme | room message attachments on the root message | **As is** |
| "Not for me" / leave | `inbox_item.status = 2` + `inbox_item_on_rejection_update` | **Extended**: for Posts the status trigger also sets `room_access = left` and back (§4.8) |
| Share via link | `InvitationCase` (accepted invite inserts a forward edge, `user_repository.dart:109-142`) | **As is**, gated by forward policy on every path (§4.3) |
| Forward graph | `ForwardsGraphScreen` (`/graph/forwards/:id`), `BeaconForwardGraphCase.asMap` gated by `beacon_can_read_involvement` (m0197: admitted participant of any role passes) | **As is**; help-offerer path mode not offered for Posts |
| Who is in it (map webs) | `beacon_member`, forward edge recipients, `beacon_room_seen` | New projection `memberWebs` (§6.2) |
| Draft node on graph | Constellation drag presentation (`beginDragNew` `constellation_cubit.dart:513`, `updateDragPresentation` :531) | **As is**, new placement phase without anchor write (§7.2) |
| Object stays where author put it | anchors, target kind `beacon` | **As is**: drop point becomes the author's `beacon` anchor on publish |
| Thin edges added/removed live | `reconcileTopology(requestLayout:false, layoutOnTopologyChange:false)` (`constellation_cubit.dart:2298`) | New edge kinds; painter keyed per kind (§6.4) |
| Radius circle | `GraphView.canvasBackgroundBuilder` (exists in the graph package, not yet wired by Constellation) | New painter only |
| Empty-canvas gestures | **Missing**: `GraphView` has only node callbacks (`graph_view.dart:109-124`) | **New** canvas tap/secondary-tap callbacks in `packages/force_directed_graphview` (§7.1) |
| Mute | `notification_beacon_mute` + `beaconMuteSet/Clear` + `NotificationPreferenceGate` (push/email) | **Extended**: in-app read rule (§5.6a); client UI is new |
| Pin | `beacon_pinned` + favorites pin mutations | **Extended**: `pinned_at`; Favorites stays Request-only |
| Post → Request | `BeaconCreateScreen` form + `BeaconCreationPolicy`; system rows via `system_message_kind` (new value 4) | New mutation, reused form (§4.6, §5.8) |

What does **not** exist and must be built: `kind`, `forward_policy`, `last_activity_at`,
`post_root_message_id`, `pinned_at` columns; forward⇒admission; `postPublish`; the first-response
claim; kind-aware validation and guards; a Post view shell; canvas gestures; a composer placement
phase; web edge kinds; radius selection model; membership webs in the field payload.

---

## 2. Shipped decisions this feature amends

| # | Current rule (source) | Amendment |
|---|---|---|
| A1 | "Beacon is the only first-class object"; comments/1:1 chat out of scope (`Tentura_current_status_quo.md` §3, §4) | Beacon stays the only *table*; it gets two kinds. A Post is addressed (not a feed, not public, not discoverable). Status-quo doc gains "Post". |
| A2 | Chat admission is always explicit; forward never admits (`CONTEXT.md`, `features/beacon_room.md`) | **For `kind = 1` only**, an active inbound forward edge is admission. Requests unchanged. |
| A3 | D5: forward edges are never drawn in Constellation (`constellation-edge-semantics.md:96`) | The forward *chain* is still never drawn on the map (it lives on the forward-graph screen). New, narrower edge class: **membership webs** from the selected object to people already placed on ego's map (D6 unchanged); everyone else collapses into "+N". |
| A4 | D9: only request holders + their path ancestors are drawn (`:100`) | In **composer mode** the composition widens to forward-eligible visible peers (up to the render cap). |
| A5 | §9.2 anti-feed: prominence never encodes recency (`:552`) | A Post's *presence* (fade/expiry) uses conversation recency. Not ranking, not sort order. Requests unaffected. |
| A6 | Pinning D15/D17: no provisional local-only state | One scoped exception: the composer draft node lives only in the session until publish. |
| A7 | `person_bond`: co-members of an open beacon are mutually visible as people (`m0193.dart:3639-3670`); used by forward candidates, the forward gate and shared contexts | `kind = 1` membership does **not** create a bond. |

---

## 3. Owner decisions

| # | Question | Decision |
|---|---|---|
| Q1 | Where do Posts live? | «Для вас» gets **one grouped, non-pinned row per Post**, bumped only by events directed at me (Post sent to me, reply to me, @mention, and for the author: first responses). A second Activity tab **«Разговоры»** lists every Post I'm in («Сейчас» / «Затихли»), no dot. Never My Work. Plus Моё поле. Mockups §Q1, M1–M2. |
| Q2 | Does Post membership create `person_bond`? | **No.** Members still see each other, open profiles and add contacts (§5.7). |
| Q3 | On Post → Request, what happens to addressees? | They keep room access with no stake, as an **intermediate participant state** («Участник из поста»): one tap to *Offer help* (normal offer → author acknowledges → helper) or *Leave chat*. A declined or withdrawn offer returns them to the intermediate state (they stay admitted). Mockup M8. |
| Q4 | Webs on the map | Only on selection; *forwarded to* and *inside*, different colours; no chain. For Requests *forwarded to* only for viewers with involvement read. |
| Q5 | Fade | `kPostActiveWindow = 72h` since `last_activity_at`, visual fade over the last 24h, then out of the active field (history keeps it; pinned Posts keep their anchor). |
| Q6 | Post "Not interested" | = leave: `inbox_item.status = 2` **and** `room_access = left`. Reversible from «Не интересно» («Вернуть»). |
| Q7 | Where the Post content lives | The root message (text + attachments + mentions). The room's top pinned strip links to it. No other surfaces besides the overflow menu. |
| Q8 | Recipient cap | No special server cap — interface limits + the noisy-contact wall (Q15). |
| Q9 | Forward policy for Requests | None. Requests keep today's rules. Converting a closed Post opens forwarding — the convert dialog says so. |
| Q10 | Children / fork | No children of Posts, no fork of Posts. |
| Q11 | Noun | «Пост» / "Post". Its room is "Chat" like a Request's. |
| Q12 | Post «Можно пересылать» | Default **on**. Before sending the author may switch it off (only invited people take part; the author can always invite more). After publish: one-way, off → on. |

### 3a. Interaction with closure and trust (decided)

| # | Question | Decision |
|---|---|---|
| Q15 | Post forwards and the noisy-contact wall (m0206) | Keep the wall for Posts, Post-aware: a recipient's **first room message or reaction** in the Post resolves their pending inbound contact edges as engaged (existing `contact_engage(p_beacon, p_user)`, `m0206.dart:89-127`). «Не интересно» / leave stays declined (existing `contact_inbox_on_decline`). |
| Q16 | Post-phase forwards after conversion | They keep routing / `usefulForward` credit. No filter. |
| Q17 | Ping discount across kinds | Applies across kinds (`forward_candidates_repository.dart:49-66`). |
| Q18 | «Add to contacts» notification | No new event. A one-way add notifies nobody; the add-back ask is an @mention in the chat; reciprocity fires `mutualConnectionFormed`. |

### 3b. Decisions taken in rev 4 (from the review; within the owner's direction)

| # | Topic | Decision |
|---|---|---|
| R4-1 | Publishing | One transactional server mutation `postPublish` (§4.5). The client never chains publish/forward/message mutations for a Post. |
| R4-2 | Conversion | The Request form opens **first**, prefilled from the root; one mutation `beaconConvertToRequest` validates and writes Request content and flips `kind` atomically. Cancel leaves the Post unchanged (§4.6). |
| R4-3 | Deleting the root | While `kind = 1`, deleting the root message deletes the Post (existing `BeaconCase.deleteById`). After conversion the root is an ordinary message. FK `ON DELETE SET NULL`. |
| R4-4 | Mute in-app | A muted Post's receipts are hidden from «Для вас» reads, counts and dismiss-all while the mute is active, except @mentions. Muting changes no receipt; when it expires, uncleared receipts are visible again. |
| R4-5 | Profile history | «Переслано пользователю» on profiles stays Request-only (`kind = 0`). |
| R4-6 | Root mentions | Resolved after admission inside `postPublish`. A recipient who is also mentioned gets one notification (the arrival); the mention is not sent separately to arrival recipients. |

---

## 4. Server design

### 4.1 Schema (migrations from `m0209`, one per server unit)

Each server unit that changes SQL owns **its own** new migration (next free version at the time it
is written; `m0209` is the first). A migration is never extended after it has been applied anywhere
(migrant records a version once). The SQL below is the end state across those migrations.

```sql
ALTER TABLE beacon
  ADD COLUMN kind smallint NOT NULL DEFAULT 0,            -- 0 request, 1 post
  ADD COLUMN forward_policy smallint NOT NULL DEFAULT 1,  -- 1 open, 0 closed (Posts only)
  ADD COLUMN last_activity_at timestamptz,
  ADD COLUMN post_root_message_id text
    REFERENCES beacon_room_message(id) ON DELETE SET NULL;

ALTER TABLE beacon ADD CONSTRAINT beacon_kind_range CHECK (kind IN (0, 1));
ALTER TABLE beacon ADD CONSTRAINT beacon_forward_policy_ck
  CHECK (forward_policy IN (0, 1) AND (kind = 1 OR forward_policy = 1));
-- Posts: only open(0) / deleted(2) / draft(3); never discoverable; no hierarchy, no schedule,
-- no cover; no row content.
ALTER TABLE beacon ADD CONSTRAINT beacon_post_shape_ck CHECK (
  kind = 0 OR (status IN (0, 2, 3) AND is_discoverable = false AND parent_beacon_id IS NULL
               AND start_at IS NULL AND end_at IS NULL AND title = '' AND description = ''
               AND cover_image_id IS NULL));
-- Requests keep their existing title/description CHECKs; no new Request CHECK.
-- One-way forward policy: BEFORE UPDATE trigger rejects forward_policy 1 → 0 when status <> 3.
-- kind is immutable except 1 → 0 (conversion): BEFORE UPDATE trigger rejects 0 → 1.
ALTER TABLE beacon_pinned ADD COLUMN pinned_at timestamptz NOT NULL DEFAULT now();
-- Backfill: last_activity_at = coalesce(latest non-system room message, published_at, created_at).
```

- Check the existing `__title_len` / `__description_len` CHECKs (`m0193.dart:858-859`): if they
  reject an empty string, relax them to `kind = 1 OR <old condition>` in m0209.
- **Status reuse, not a new status.** A live Post is `status = 0`, so `allowsForward`, room write
  policy and the lifecycle write-guard trigger work unchanged. Every Request-only query that filters
  the open family must also filter `kind = 0` (§4.9, audit test).
- `last_activity_at` is generic; `beacon_display_case.dart` can pass it.
- `beacon_participant.role` has no CHECK, so role 6 needs no SQL change. Add
  `BeaconParticipantRoleBits.addressee = 6` (server `lib/consts/beacon_room_consts.dart:2-9`, client
  `lib/domain/entity/beacon_room_consts.dart:2-9`) and `SystemMessageKind convertedToRequest = 4`
  (server `beacon_hierarchy_consts.dart:24-28`, client `beacon_room_consts.dart:61-65`).
- Drift: add the new columns to `packages/server/lib/data/database/table/beacons.dart` and
  `pinned_at` to the pinned table class; the Drift reconciliation tests must stay green. The beacon
  title column's Drift `withLength(min: kTitleMinLength)` (`common_fields.dart`
  `BeaconTitleDescriptionFields`) blocks an empty Post title: lower the Drift minimum to 0 for
  beacons and enforce "Request title required" in the Request branch of `BeaconCreationPolicy`
  (the GraphQL title field becomes nullable for `kind = 1` only).
- `beacon_mapper.dart:11-44` maps the new fields (and fix its existing omission of
  `isDiscoverable`, which the new code relies on).

### 4.2 Forward ⇒ admission for Posts (A2)

Function `post_reconcile_admission(p_beacon text, p_user text)` + triggers on `beacon_forward_edge`
AFTER INSERT and AFTER UPDATE OF `cancelled_at`, mirroring `inbox_item_on_forward_insert`
(`m0193.dart:2073-2092`). Only when `beacon.kind = 1` and `p_user` is not the author. The function
first ensures and locks the participant row (`INSERT … ON CONFLICT (beacon_id, user_id) DO NOTHING`
with `role = 6, room_access = 0`, then `SELECT … FOR UPDATE`), then decides:

- active inbound edge exists (`recipient_id = p_user AND cancelled_at IS NULL`), the row has
  `role = 6` and is not `left` → `room_access = 3`.
- no active inbound edge and the row is `role = 6, room_access = 3` → `room_access = 0`.
- a `left` row (5) is never changed here (voluntary leave survives cancel and resend).
- rows with any other role (steward, helper, candidate, …) are never changed here.

The participant column is `user_id` (`m0193.dart:4891`), unique `(beacon_id, user_id)`.
Locking the participant row serialises concurrent cancellations for the same recipient.

Downstream, each one line of SQL:
- `beacon_member` (`m0193.dart:5233-5249`): already includes `room_access = 3` rows — addressees are
  members (needed by realtime, mentions, read receipts).
- `beacon_admitted_helper` (`:4906-4911`): add `AND role <> 6` (addressees are not helpers).
- `person_bond`, `person_bond_peers`, `person_shared_contexts`: add `AND b.kind = 0` (A7).
- `beacon_can_read_content`: no change (forward edge is already a read path).
- No system room row on admission.

### 4.3 Forward policy (one function, every edge path)

`BeaconForwardPolicy.canForward({required BeaconEntity beacon, required String senderId})` in
`packages/server/lib/domain/policy/`: `beacon.allowsForward && (beacon.forwardPolicy == open ||
senderId == beacon.author.id)`. For a Request `forwardPolicy` is always `open`.

Called from every path that creates a forward edge: `ForwardCase.forward`
(`forward_case.dart:218`), `InvitationCase.create` (`:75`), `InvitationCase.accept` (`:234`) and
`_acceptBeaconInviteOnly` (`:374`), and the invited-user creation paths that call
`_materializeBeaconInviteForward` (`user_repository.dart:109-142`, ~:244, ~:412) — the use case
re-checks the policy (with the invite issuer as sender) before calling them. Today `accept` and
`createInvited*` do not re-check `allowsForward` at all; this is fixed for both kinds.

Exposed on the beacon read model as Hasura computed field `viewer_can_forward`
(`beacon_get_viewer_can_forward(beacon_row, hasura_session)`), the same rule in SQL; a parity test
compares it with the Dart policy. New mutation `beaconForwardingOpen(id)`: author-only, `kind = 1`,
`0 → 1` only.

### 4.4 `last_activity_at` and the first-response claim

- Trigger bumps `last_activity_at = GREATEST(...)` on `beacon_room_message` insert (non-system),
  `beacon_room_message_reaction` insert, `beacon_forward_edge` insert.
- Table `post_first_response(beacon_id, user_id, source_kind smallint /* 1 message, 2 reaction */,
  source_id text, created_at, PRIMARY KEY (beacon_id, user_id))`.
- Function `post_claim_first_response(p_beacon, p_user, p_kind, p_source) RETURNS boolean`:
  returns false for the author or `kind <> 1`; `INSERT … ON CONFLICT DO NOTHING`; when the row was
  inserted, `PERFORM contact_engage(p_beacon, p_user)` (Q15) and return true.
- `BeaconRoomCase.createMessage` and `reactionToggle` call it (through a repository port) inside the
  same transaction as the message/reaction write, for `kind = 1` and non-author actors only. When it
  returns true, the case records `postFirstResponse` for the author. The winner facts are immutable
  (the claim row); removing the reaction or deleting the message later does not reset the claim.
- `reactionToggle` must know whether the reaction was added: `toggleReaction`
  (`beacon_room_repository.dart:1241-1269`) returns `bool added`.
- Undirected messages today persist outside the attention transaction (`beacon_room_case.dart:471`);
  for `kind = 1` the message path always runs inside `runAction`.

### 4.5 `postPublish` (one transaction)

New `PostCase.publish(...)` in `packages/server/lib/domain/use_case/post_case.dart`, V2 mutation
`postPublish(id, body, mentionUserIds, mentionOffsets, mentionLengths, recipientIds, notes,
forwardPolicy, attachment?)`. Mentions use the same three parallel lists as `roomMessageCreate`
(`beacon_room_case.dart:308-310`); recipients map onto the existing `ForwardCase.forward` arguments
(recipient ids + per-recipient note map). The optional `attachment` is the **first** attachment,
uploaded inline exactly as `roomMessageCreate` uploads one (`attachmentBytes`, filename, mime), so a
photo-only Post is valid in one transaction; further attachments are added after publish through
the existing `roomMessageAttachmentAdd`. The draft exists (`beaconCreate(kind: 1)` as a draft).
Inside one `TransactionalAttentionCase.runAction`:

1. Lock (§4.10) and re-read the beacon under the lock; require author and `kind = 1` **first**;
   then, if already published with a root, return the existing ids (idempotent retry); otherwise
   require `status = 3`, non-empty `body` or an attachment, ≥ 1 recipient.
2. Set `forward_policy`; publish (`status = 0`, `published_at`) through the same repository code as
   `BeaconCase.publishDraft`.
3. Forward: the edge-creation core of `ForwardCase.forward` (recipient gate, blocks, notes,
   `relayReceived` intents), extracted into a method that takes the open `AttentionTransaction`
   instead of opening its own. Admission triggers fire here.
4. Root: insert the root message through the core of `BeaconRoomCase.createMessage` (mention
   resolution now sees the admitted audience); set `post_root_message_id`. Mentions of arrival
   recipients produce no separate mention intent (R4-6).
5. Return the beacon id and root message id.

Idempotency: for the author of a `kind = 1` beacon that is already published with a root,
`postPublish` returns the existing ids and does nothing (safe client retry after a lost response);
non-authors and converted Requests are rejected before this branch. All recipient eligibility
checks (blocks, mutual visibility, content access) run **after** the locks.
The Constellation composer (§7.5) calls the same mutation. Whether extraction or nesting is used in
steps 2–4 is decided by spike S0.

### 4.6 `beaconConvertToRequest`

`BeaconCase.convertToRequest(authorId, id, BeaconSaveCommand content, isDiscoverable)`: lock order
as §4.10; require author, `kind = 1`, `status = 0`; validate `content` with the **Request** branch of
`BeaconCreationPolicy` (title, description, needs, schedule); in one transaction write the content,
`kind = 0`, `forward_policy = 1`, `is_discoverable` **in one `UPDATE` statement** (a dedicated
repository operation; writing content first would violate the Post shape CHECK), keep `addressee`
rows, insert the system row (`system_message_kind = 4`, payload `{"event":"convertedToRequest"}`),
emit the realtime `beacon` change. The content command is a server-domain type
(`BeaconConversionContent`: title, description, needs, primary need, schedule). A cover is not part
of conversion: if the author keeps the suggested photo, the client sets it with the existing cover
upload after conversion succeeds (a failure leaves the Request without a cover).
`post_root_message_id` is kept (harmless). The client opens the Request form first (prefilled from
the root) and calls this mutation on submit (§5.8).

### 4.7 Blocks in Post rooms

A Post member may have been admitted through a third person's forward, so edge cleanup between the
blocked pair (`user_block_case.dart:253`) does not remove them. Rule: for `kind = 1`, the room gate
(`BeaconRoomCase._canUseRoom`, `beacon_room_case.dart:125-137`) also requires
`beacon_can_read_content(beacon, viewer)` (which already denies across an author↔viewer block).
The same predicate is added to the Hasura `beacon_participant` select permission branch that admits
room participants (`hasura/metadata.json` ~:1705) **for Posts only** —
`{"_or": [{"beacon": {"kind": {"_eq": 0}}}, {"beacon": {"can_read_content": {"_eq": true}}}]}` — so
Request behaviour is unchanged; likewise for attachment reads and the field projection (§6.2). Member↔member blocks behave as in Request rooms today.

### 4.8 Leave and return

Two V2 mutations, `postLeave(id)` and `postReturn(id)` (`PostCase`), for any viewer whose
participant row has `role = 6` — on a Post, and on a Request converted from a Post (the
intermediate state, §5.9). Under the §4.10 locks: leave sets `inbox_item.status = 2` (which keeps
the existing `contact_inbox_on_decline` behaviour) and `room_access = 5`; return sets the inbox row
back to 1 (watching) and calls `post_reconcile_admission` after setting `room_access = 0`. A trigger
on `inbox_item` is **not** used, because the inbox row would be locked before the hierarchy lock
and invert the lock order. The Hasura `inbox_item` update permission gains `beacon.kind = 0`, so a
Post's inbox row changes only through these mutations. The author has no inbox item and cannot
leave.

### 4.9 Request-only paths reject Posts

`BeaconKindPolicy.requireRequest(BeaconEntity)` throws `BeaconNotRequestException`
(`BeaconExceptionCode` 1321, mirrored on the client). Called at the top of:

- `HelpOfferCase` (`offerHelp`, `setRoleLabel`, `withdraw`), `CoordinationCase`
  (`_prepareAdmissionAction` callers, `releaseCommitment`, `setCoordinationResponse`,
  `setBeaconStatus`, `helpOffersWithCoordination`), `ClosureCase` (in `_requireAuthor` and in every
  public method that loads the beacon), `BeaconCase.beaconCancel`, `fork`,
  `BeaconChildCreateCase._assertParentCreateAllowed` (parent is a Post),
  `BeaconDisplayCase.displayStatuses` (Posts get no display status).
- Room mutations that are Request capabilities: `participantOfferHelp`, `roomAdmit`,
  `stewardPromote`, `nowLineUpdate`, plan update, coordination items, fact cards
  (`beacon_fact_card_case.dart:55`), child promotion. S3 enumerates every mutation in
  `mutation_beacon_room.dart` and classifies it Post-allowed (messages, reactions, attachments,
  polls, seen, edit/delete own message) or Request-only.
- DB: `BEFORE INSERT` trigger on `beacon_help_offer` raising for `kind = 1`.
- Hasura: `beacon_help_offer` insert and update checks (`metadata.json` ~:1553, ~:1628) gain
  `beacon: {kind: {_eq: 0}}`.
- SQL `kind = 0` in: `responsibility_scope_base_beacons` (`m0193.dart:4105-4120`), constellation
  request sections (`constellation_field_snapshot_reader.dart:509,549`,
  `constellation_field_repository.dart:177,207`), deadline reminder candidates
  (`beacon_repository.dart:59,79`), stale-request reminder (`closure_reminder_repository.dart:92`),
  `attention_repository.dart:1027,1075` (verify each), the before-response tombstone function
  (`m0193.dart:510-606`), My Work Hasura query (`my_work_fetch.graphql`), profile shared beacons
  (`profile_shared_beacons_fetch.graphql`, R4-5), Favorites fetch and the Favorites live-update path
  (`favorites_cubit.dart:116`).
- `BeaconCase.deleteById` works for Posts (verified by test).

**Audit test (S3 acceptance):** a pg test seeds one Post and one Request with the same audience and
asserts the Post is absent from every list above and that each Request-only mutation throws
`BeaconNotRequestException` (or is rejected by Hasura/DB) — and present in: inbox, room, attention,
forward graph.

### 4.10 Lock order

One order everywhere a Post edge, participant or kind changes: (1) global hierarchy advisory lock
(`tentura.beacon_hierarchy.v1`, already taken by participant-row statement triggers,
`m0193.dart:1022,6976`) — taken explicitly at the start of `postPublish`, forward to a Post, invite
accept for a Post, `convertToRequest` and leave/return; (2) per-request advisory lock (4242);
(3) beacon row `FOR UPDATE`/`FOR SHARE` (re-read `kind`, `status`, `forward_policy` under the lock);
(4) recipient availability locks (`forward_edge_repository.dart:114`); (5) trust pair locks (inside
`contact_engage`). Block actions already take (1) first. For Posts, `ForwardCase` runs its
authorization and recipient-eligibility checks (blocks, content access, mutual visibility, parent
edges) **after** taking (1)–(3), not before the transaction as today (`forward_case.dart:200-246`).
Concurrency pg tests run forward ∥ block (with the block committed between the first read and the
lock), forward ∥ convert, forward ∥ leave, invite accept ∥ block, cancel ∥ cancel.

### 4.11 API summary

- `beaconCreate(kind, forwardPolicy, …)` — kind-aware validation (`BeaconCreationPolicy` gets a
  Post branch: title/description must be empty; no needs/slug/schedule/cover). Applies to create,
  draft save, publish and edit.
- `postPublish`, `beaconForwardingOpen`, `beaconConvertToRequest` (new).
- Notifications: `relayReceived` takes the beacon kind from its producer (`ForwardCase` /
  `PostCase`) through `AttentionIntentCase.relayReceived` (`:41-60`) into
  `BeaconNotificationIntent.beaconKind`; new `NotificationKind.postFirstResponse`; copy in
  `beacon_notification_copy_builder.dart` and the batch texts in
  `beacon_notification_batch_aggregator.dart:49` ("N posts shared with you", "N replies to your
  posts"). Tests go through generated receipts/jobs/batches, not handcrafted intents.
- Hasura: expose `kind`, `forward_policy`, `last_activity_at`, `post_root_message_id`,
  `viewer_can_forward`; `pinned_at` on `beacon_pinned`.
- Client SDL snapshot `packages/client/lib/data/gql/schema.graphql` is refreshed per
  `DEVELOPMENT.md`.

---

## 5. Client design (non-graph)

### 5.1 Domain

`Beacon` (`lib/domain/entity/beacon.dart`) gains `kind` (`BeaconKind {request, post}`),
`forwardPolicy`, `lastActivityAt`, `viewerCanForward`, `postRootMessageId`. Forward buttons use
`viewerCanForward`. Request-only getters (`canCommitAsViewer`, `allowsCoordination`, …) return false
for Posts via one `isRequest` guard inside the entity.

### 5.2 Create

- A Post is created by **writing its first message**. The create screen is an empty room: the
  room's composer (`BeaconRoomComposer`, `basic_chat_body.dart:707`) plus a «Кому» row that opens
  the recipient picker on a `ForwardCubit(embedded: true)`.
- Flow: `BeaconCreateCubit(kind: post).ensureDraft()` (server draft for a stable id) → the user
  writes, picks recipients, toggles «Можно пересылать» (default on) → ➤ calls `postPublish` once,
  then uploads the composer's attachments to the root message with the existing room attachment API.
  On a lost response the retry is safe (§4.5).
- Cancel: an empty draft is deleted silently; a draft with content asks, then is deleted (Post
  drafts are not kept).
- Requests keep today's form (`BeaconCreateRoute`).

### 5.3 Room reuse: `RoomHost` seam (refactor R1, no behaviour change)

`BeaconRoomSurface` takes `BeaconViewCubit` but reads only admission flags and the author
(`beacon_room_surface.dart:135-187`). `ThreadHostCubit` and `RoomCubit` import it for doc comments
only. Introduce in `features/beacon_threads/domain/`:

```dart
abstract interface class RoomHost {
  String get beaconId;
  Profile get author;
  BeaconStatus get status;
  bool get isAdmissionBlocked;
  bool get coordinationDeniesAdmission;
  RoomCapabilities get capabilities;
  Stream<void> get changes;
}
```

`RoomCapabilities` flags: `facts`, `blocker`, `plan`, `coordinationItems`, `childPromotion`,
`commitmentSheet`, `closure`, `pinnedStrip` (`requestNow` | `postRoot`). `BeaconViewCubit`
implements `RoomHost` with all Request capabilities on (zero behaviour change, proven by the
existing tests). `RoomCubit._fetchFullSnapshot` (`room_cubit.dart:673-718`) skips facts, room state,
blocker, plan and coordination items when the capability is off; `BeaconRoomBody` actions (Turn
into, Child request, Update plan, Jump to plan, Pin fact, View pinned fact) and `RoomMessageTile`
pieces (commitment sheet, child promotion footer, fact history, closure story card) are gated by
the same flags.

### 5.4 Post view = the room

Same route `/beacon/view/:id`. The host screen (`beacon_view_host_screen.dart`) must know the kind
**before** it creates `BeaconViewCubit` and the Request-only hosts (`wrappedRoute` :58-89 creates
them, and `BeaconViewCubit` fetches coordination data at load): it first resolves the beacon kind
(a small query, cached), then builds either the Request providers or the Post providers
(`PostViewCubit`, `ThreadsCubit`, `ThreadHostCubit` with `RoomCapabilities.post()`). `PostViewCubit implements RoomHost` (capabilities off,
`pinnedStrip = postRoot`). The screen is `BeaconRoomSurface` + an app bar with title "author: root
excerpt", 🔕 when muted, and ⋮:
- pin/unpin in «Разговоры», mute, participants, forward graph (existing `ForwardsGraphScreen`),
  show on map, forward (if `viewerCanForward`), «Разрешить пересылку» (author, while closed),
  convert to Request (author), leave (recipient), delete (author).
- The pinned strip shows the root excerpt and scrolls to it; for a forwarded recipient it also shows
  «Вам переслала ‹X›: ‹note›».
- Deleting the root (author) = deleting the Post, with confirmation (R4-3).

### 5.5 Forward screen: `ForwardTargetProfile` (refactor R2)

Derived from `ForwardState.beacon.kind`. For Posts the picker hides: band (`ForwardBandStrip`,
`forward_recipient_picker.dart:568`), reason chips (`_editReasons` :231), lineage (`:714`),
attribution dialog (`:205`), the context strip requirements bar. The offer-help nudge policy
(`forward_draft_policy.dart:39`) returns false for Posts. Candidates, notes, search, invite bar
unchanged.

### 5.6 Activity

- **Server read rule (S10):** for `kind = 1`, receipts group into one row per Post that includes
  `relay_received` arrivals (today excluded, `attention_repository.dart:388`); the group position is
  the **latest** directed event (`MAX(created_at)`, not `MIN`, `:514`); Post `inbox_item.status = 0`
  rows are not pinned decisions (`attention_dismissible_sql.dart:64`); read, count and dismiss-all
  share one predicate. Muted Posts: R4-4.
- **Events:** `relayReceived` (Post variant), `roomMessagePosted` (reply to me; @mention via
  `NotificationKind.roomMention`), and new **`postFirstResponse`** (author; §4.4). Declaration in
  `docs/contracts/updates-event-contract.json` (`eventTypes`, `producers`,
  `eventClassifications`): `recipientPredicate: "reason:postAuthor"`, `scope: "beacon"`,
  `attentionClass: "optional"`, `placement: "primary"`, `groupKey: "beaconId"`,
  `orderingEffect: "stable"`, `accessPolicy: "beacon_content"`, `recoverableVia: "room"`,
  `clearPolicy: "explicit_or_request_open"`, `coalescible: true`. Mirrored in `AttentionEventType`
  (`attention_models.dart:60-98`, `assertDeclared`), the exhaustive switches in
  `attention_policy.dart`, and the client `attention_event_classification.dart`.
- **Projection:** receipts carry the beacon kind, the root excerpt and the first root image
  through the attention SQL projection, `AttentionReceipt` (`attention_models.dart:380`), its SDL,
  the client fragment and mapper (`request_attention_card_mapper.dart:63` keeps Requests as today).
  Live Post inbox rows are never outcome-dismissed: clearing a Post row clears its receipts and
  leaves inbox status and room access unchanged (`attention_dismissible_sql.dart:149,278`, child
  previews `attention_repository.dart:1116`, and sweeps share one kind-aware eligibility).
- **Client:** `PostAttentionRow` variant in `activity_stream_view.dart` (`_ActivityStreamCell`
  switch :992-1073), branch on kind.
- **«Разговоры» tab:** `TenturaPrimaryTabBar` in `InboxScreen` (`inbox_screen.dart:119-135`; example
  `friends_screen.dart:168`); list = new V2 query `myPosts` (server SQL, not Hasura relationships —
  the room tables and mutes are not tracked in Hasura): Posts where the viewer is author or admitted
  addressee and the content is readable, with author, root excerpt, last message excerpt,
  `last_activity_at`, viewer `pinned_at`, viewer `muted_until`, unread count (same source as the
  room unread badge). Pinned first (`pinned_at`), then `last_activity_at`; the client splits at
  `kPostActiveWindow` into «Сейчас» / «Затихли». Refetch after reply, pin, mute, leave. No tab dot.

### 5.6a Mute, pin, leave

- **Mute:** UI on `beaconMuteSet` / `beaconMuteClear` (present in the client schema, no caller
  today). Durations 1h / 3h / 1d / 3d / forever (`null`). Push/email: existing gate. In-app: R4-4.
- **Pin in «Разговоры»:** existing pin/unpin mutations; `pinned_at` orders them. Favorites stays
  Request-only (fetch and live path).
- **Leave / return:** inbox status 2 / back (§4.8); listed in the existing «Не интересно» archive
  (`inbox_rejected_screen.dart`) with «Вернуть». A later re-send produces an arrival row but does not
  re-admit (the §4.2 function keeps `left`).

### 5.7 Meeting people in a Post room

Profiles are gated only by blocks, so any member can open any member's profile (avatar tap →
`ScreenCubit.showProfile`, `room_message_tile.dart:1524`). «Добавить в контакты» is the existing
`ProfileViewCubit.addFriend`. No new event (Q18). The "you are both in this Post" line via
`person_shared_contexts` is dropped for v1 (that view is `kind = 0` now, A7).

### 5.8 Convert to Request

Author ⋮ «Превратить в запрос» → confirm dialog (audience keeps access; forwarding becomes open;
choose discoverability) → `BeaconCreateRoute(convertFromPostId:)` opens the Request form prefilled
from the root (first line → title, cut to the title limit; rest → description; image attachment →
cover suggestion). Submit calls `beaconConvertToRequest` (§4.6). Cancel leaves the Post unchanged.
After conversion the room shows the Request UI; addressees see M8.

### 5.9 Intermediate participant state after conversion (Q3)

- Server: an addressee row keeps `role = 6`. Both offer paths keep the row admitted:
  `participantOfferHelp` (`beacon_room_repository.dart:1036`, today resets access to requested) and
  `inviteOfferUserToBeaconRoom` (`:1121`, returns early for admitted rows) get role-6 branches;
  acknowledgement sets `role = 2` (helper). `declineHelpOffer` (`coordination_case.dart:421`) and
  withdraw **do not revoke** room access for a `role = 6` row. Leave/return = `postLeave` /
  `postReturn` (§4.8). `removeFromRoom` works as for anyone.
- Client: M8 «Участник из поста» card with [Предложить помощь] / «Выйти из чата»; the author's
  People tab gets a section «ИЗ ПОСТА».

---

## 6. Constellation: showing Posts and membership webs

### 6.1 Node model and projection

Posts enter the same Beacon projection as Requests through composition
(`constellation_anchor_composition.dart:155`), holders, caps, labels (a Post's label is its root
excerpt, `node_details.dart:325` today uses the title), anchors, node construction, preview, and
pinned records (`constellation_field_snapshot_reader.dart:457`, kind-aware). An anchored Post that
is past its active window is dormant like a pinned closed Request.


Extend `FieldRequestNode` (`node_details.dart:309-349`) into `FieldBeaconNode(beacon, kind)` (rename
is mechanical). Only the glyph, status marker (none for Posts) and placement rule branch on kind.
`ConstellationRequest` (`constellation_field.dart:56-99`) gets `kind`, `memberIds`, `lastActivityAt`,
`hiddenReachCount`.

### 6.2 Server payload

`ConstellationField` (`custom_types.dart:966-993`) gains:
- `posts`: Posts where the viewer is author or active addressee, `status = 0`, readable
  (`beacon_can_read_content`, §4.7), `last_activity_at > now() - 72h` or pinned by the viewer.
- `memberWebs {beaconId, personId, state: forwarded|inside}` for those Posts; `inside` = admitted
  member who has a `beacon_room_seen` row; `forwarded` = active inbound edge recipient otherwise.
  Persons outside ego's mutually visible peer set (`_allVisiblePeerIds`,
  `constellation_field_snapshot_reader.dart:402`) are dropped and counted in `hiddenReachCount`.
- A lazy query `beaconMemberWebs(id)` for a selected Request: admitted helpers for every content
  reader; forward recipients only with involvement read.

### 6.3 Placement

New rule in `computeConstellationPlacedLayout` (`constellation_layout.dart:219-443`, after request
placement :411-432): a Post with no anchor is placed at the barycenter of its placed members (author
included), then through `_chooseAutomaticPosition` (:517). The author's composer drop point is a
`beacon` anchor.

### 6.4 Rendering

- `ConstellationEdgeKind` (`constellation_cubit.dart:33`) gains `webForwarded`, `webInside`,
  `draftRecipient`; styles in `constellation_edge_style.dart:7-44`; legend
  (`graph_legend_content.dart:104-125`).
- Edge identity becomes a stable semantic id `(src, dst, kind)` carried by `EdgeDetails`
  (`features/graph/domain/entity/edge_details.dart:22` equality/hash), topology reconciliation, the
  controller lookup, the scene edge resolution (`constellation_graph_scene.dart:33`), `addEdge`
  (:2263) and the painter (`constellation_body.dart:982-984`).
- Webs are drawn only for the selected object; star from the object to each placed member.
- Fade: opacity from `lastActivityAt` vs `loadedAt` in the presentation frame; no ordering.
- "+N" chip reuses `constellation_overflow_group.dart`.

---

## 7. Constellation composer (create on the graph)

### 7.1 Entry

- Toolbar button «Создать здесь» (Post / Request) in `constellation_app_bar.dart`.
- Desktop secondary-tap and touch long-press on empty canvas: new `onCanvasTap` /
  `onCanvasSecondaryTap` / `onCanvasLongPress` callbacks in `packages/force_directed_graphview`
  `GraphView` (hit-test miss on all nodes), with scene coordinates. Never long-press alone.

### 7.2 State ownership

```
ConstellationComposerCubit (thin)       — draft position, radius, manual adds/removes, mode
   ├── BeaconCreateCubit (kind)         — server draft (ensureDraft)
   └── ForwardCubit(draftId, embedded)  — candidates, eligibility, selection, notes
```

- **One selection authority:** `RadiusRecipientSelection` (pure, `features/constellation/domain/`):
  `selected = (inRadius ∪ manualAdded) \ manualRemoved`, intersected with eligibility. Every edit —
  graph tap, radius change, **and list-picker toggles** — goes through the composer's intent API
  (`toggle(personId)`, `setRadius(r)`, `moveDraft(p)`), which updates the overrides and pushes the
  result into `ForwardCubit` with a new bulk `setSelection(Set<String>)`. In composer mode the list
  picker's toggle callback is routed to the composer, not to `ForwardCubit.toggleSelection`.
- `ConstellationPlacementPhase.composing` (`constellation_state.dart:20`): the draft is a topology
  node `fd:draft` positioned by a presentation override (as `draggingNew`), no anchor write until
  publish. Person drag-to-pin is suspended in this phase.

### 7.3 Composition widening (A4)

Entering composer mode recomposes with forward candidates (`ForwardCubit` candidates ∩ field peers)
added to the kept set (`constellation_anchor_composition.dart:146-262`), up to the render cap (120).
Exit restores the normal composition. Ineligible people render disabled with the reason on tap.

### 7.4 Gestures (v1)

- Drag the draft: move; radius membership recomputes on drop.
- Tap a person: toggle; edge appears/disappears without relayout.
- Radius handle on the circle rim: resize (scene-space circle via `canvasBackgroundBuilder`); live.
- Deferred: drag a line to a person; drag a person onto the draft.

### 7.5 Sheet and publish

- Post sheet = the same room composer + «Кому» chips + «Можно пересылать» (mockup K4). Send =
  `postPublish` (§4.5), then `ConstellationAnchorCase.upsert(beacon, dropPoint)`
  (`constellation_anchor_case.dart:248`), then field reload.
- Request sheet: title + short description + «Подробнее» (full form with the same draft id; the
  composer's recipients **and notes** are passed into the form's `ForwardCubit` as initial
  selection; `beacon_create_screen.dart:173` creates a fresh cubit today, so it gains initial notes);
  Send = the existing `BeaconCreateCubit.sendRequest`, then the anchor.
- Anchor upsert takes a normalised position and the current anchor generation
  (`constellation_anchor_case.dart:248`); an anchor failure leaves the object published and
  unpinned (snackbar, no retry loop).
- The server draft is created lazily on the first content edit or recipient change; cancelling an
  untouched composer makes no server call; cancelling a touched one deletes the draft; late async
  results after cancel are ignored.
- «Списком» opens `ForwardRecipientPicker` on the same `ForwardCubit` (routed through the composer
  intents, §7.2). A11y: a radius slider in the sheet.
- Starting radius = distance to the 3rd-nearest eligible person (+ margin).

---

## 8. Units

The unit list, order and dependencies live in `docs/plans/post-implementation-steps.md` §1 (the
step plan is authoritative for execution order).

---

## 9. Risks

- **Transaction composition (S0).** Existing use cases open their own `runAction`; `postPublish`
  needs them inside one transaction. Drift nests transactions as savepoints; S0 proves it with a pg
  test before anything depends on it.
- **Status reuse leaks Posts into Request surfaces.** Mitigated by S3's audit test and a CI grep
  for open-family filters without `kind` in `packages/server/lib/data/**`.
- **Lock order (S11).** Participant-row triggers take the global hierarchy lock; every Post path
  takes it first.
- **`RoomHost` refactor touches large files** (`RoomCubit`, `RoomMessageTile` 2723 lines,
  `BeaconRoomBody`). Pure refactor first.
- **Graph package change (K0)** — empty-canvas gestures in `force_directed_graphview` touch hit
  testing used by every graph screen; regression tests on the existing graph screens.
- **Composer widening shifts the layout.** Accept; pins stay.

---

## 10. Review record

Rev 4 applied the Codex (gpt-6.1-sol, high) review of rev 3:

| # | Finding | Resolution |
|---|---|---|
| 1 | Blocks do not revoke Post room access admitted via a third party | §4.7 |
| 2 | Hasura help-offer writes bypass the Dart guard | §4.9 Hasura + DB trigger |
| 3 | Empty Post fails description validation | §4.11 kind-aware `BeaconCreationPolicy` (S5) |
| 4 | Conversion vs Request CHECK | R4-2, §4.6 (form first, atomic validated convert); no new Request CHECK |
| 5 | Claimed conversion lock absent; lock order undefined | §4.10 (S11) |
| 6 | Root delete cannot delete the Post | R4-3, §5.4 (S13) |
| 7 | Client publish sequence has no retry identity; composer bypass | R4-1, §4.5 (idempotent `postPublish`), §7.5 |
| 8 | Leave/return has no server implementation | §4.8 (S9) |
| 9 | Cancel erases leave; concurrent cancels; wrong column | §4.2 (row lock, `left` preserved, `user_id`) |
| 10 | Intermediate state vs decline; helper projection | §4.2 `beacon_admitted_helper`, §5.9 |
| 11 | Request-only room mutations missing | §4.9 room mutation classification |
| 12 | Activity grouping loses arrivals and bumps | §5.6 server read rule (S10) |
| 13 | First response needs durable claim | §4.4 claim table + function (S7) |
| 14 | Mute in-app needs server rule | R4-4 (S10) |
| 15 | Root mentions before admission | §4.5 order (forward before root), R4-6 |
| 16 | Profile history / Favorites live path | R4-5, §4.9 |
| 17 | Two selection authorities | §7.2 one intent API + bulk `setSelection` |
| 18 | Unit ownership | §8 + the step plan |

Rev 5 applied the design-level findings of the Codex (gpt-6.1-sol, high) review of the step plan
rev 1: per-unit migrations (§4.1), Drift/GraphQL title barrier (§4.1), idempotency after
authorization and inline first attachment (§4.5), single-UPDATE conversion (§4.6), locked
leave/return mutations instead of an inbox trigger (§4.8), eligibility checks under the locks
(§4.10), notification pipeline (§4.11), kind-aware route host (§5.4), receipt projection and
`myPosts` (§5.6), role-6 offer branches (§5.9), unified Beacon projection and semantic edge ids
(§6.1, §6.4), composer draft lifecycle and form handoff (§7.5). The remaining findings concern unit
boundaries and tests and are applied in the step plan.
