# Post + creating Posts/Requests in Constellation — plan

**Status:** draft rev 1 (2026-09-30), awaiting owner decisions (§3).
**Branch:** `feature/post-constellation`.
**Spec source:** owner brief (2026-09-30, Russian) — Post as a light social object, forward policy,
creating Posts and Requests directly on the Constellation graph with "web" edges and an
audience radius, post-publish relay spread, activity-based fading, one-way Post → Request.

**Primary constraint (owner):** maximal reuse, no duplicated code paths. The plan is therefore
organised around *where the existing machinery already does the job* and what the smallest
seam is that lets it do the job for a Post as well.

---

## 0. TL;DR

1. **A Post is a `beacon` with `kind = post`.** Not a new table, entity or route. Room, forward
   edges, inbox rows, attention receipts, realtime kinds, images, blocks, rate limits, deep links,
   share links and the forward screen are all keyed by `beacon.id` and work unchanged. Post → Request
   is an in-place `kind` flip, which is exactly why "one-way conversion" is cheap.
2. **Forward edge = Post membership.** For `kind = post`, an active inbound forward edge
   materialises a `beacon_participant` row with `room_access = admitted` (DB trigger, same
   pattern as `inbox_item_on_forward_insert`). Every existing room gate (`_canUseRoom`,
   `beacon_effective_admission`, `realtime_room_recipients`, mention resolution, read receipts)
   then works with no Post branch.
3. **Forward policy — «Можно пересылать», Posts only**, default **on**; the author may switch it
   off before sending. After publish it is one-way (off → on only).
   Requests are untouched (always forwardable, as today). One new column `beacon.forward_policy`
   (`closed | open`) enforced by
   one server policy function used by `ForwardCase` *and* `InvitationCase`, and mirrored by one
   client getter.
4. **The graph composer is a second view of the existing create flow**, not a second create flow:
   same `BeaconCreateCubit` (server draft), same `ForwardCubit` (selection, eligibility, notes,
   send). The graph only *renders* `ForwardCubit` selection as edges and *writes* to it on
   tap/radius. The list picker stays the accessible alternative on the same cubit.
5. **Three refactors carry the reuse** and land before any Post UI: a `RoomHost` seam out of
   `BeaconViewCubit` (so the 1447-line `RoomCubit` + room widgets serve a Post view), a
   `ForwardTargetProfile` on the forward screen (hide band/reasons/lineage/offer nudge for Posts),
   and a `kind` parameter on `BeaconCreateCubit`.
6. **Membership webs on the graph** (only for the selected object): object → *forwarded to* and
   object → *inside*, two colours, only to people already on ego's map (D6/§9.1); the rest is "+N".
   The forward chain is never drawn.
7. **Fading** uses one new column `beacon.last_activity_at`, bumped by triggers on room messages,
   reactions and forwards (it also fixes today's `BeaconDisplayStatus.lastActivityAt` fallback to
   `updated_at`).

Several shipped decisions are amended by this feature (§2) — they need an explicit owner sign-off,
not a silent override.

---

## 1. What exists and what is reused (evidence)

| Need from the brief | Existing machinery | Reuse verdict |
|---|---|---|
| Object addressed to chosen people | `beacon` + `beacon_forward_edge` (`m0193.dart:5054`); audience of a published Request is already "forward edges made at create time" (`beacon_create_cubit.dart:984-1020` publish → `forwardCubit.forward()`) | **As is** |
| Own Room with replies + reactions (the Post itself = the root message) | `beacon_room_message`, `_reaction`, `_attachment`, polls, `beacon_room_seen`, realtime `room_*` kinds, `BeaconRoomCase` — all keyed by `beacon_id` | **As is on server**; client needs the `RoomHost` seam (§5.3) |
| Same relay mechanics + recipient screen | `ForwardCase.forward` (`forward_case.dart:160-339`), `ForwardCubit`, `ForwardRecipientPicker` (`embedded: true` already used by the create wizard's Recipients step) | **As is**, sections gated by `ForwardTargetProfile` |
| New recipients join the same Post and see history | `listMessages` returns full General history to any admitted member | **As is** once forward ⇒ admission (§4.2) |
| Photo / meme | room message attachments (`beacon_room_message_attachment`) on the root message | **As is** |
| "Not for me" | `inbox_item.status = 2` + `inbox_item_on_rejection_update` | **As is**, plus room leave (`room_access = left`) for Posts |
| Share via link | `InvitationCase` (accepted invite *inserts a forward edge*, `user_repository.dart:120-160`) | **As is**, gated by forward policy |
| Who is in it (for map webs) | `beacon_member` (inside), `beacon_forward_edge` recipients (forwarded), `beacon_room_seen` (opened), `beacon_admitted_helper` (m0174) for Requests | New projection `memberWebs`, no chain data (§6.2) |
| Draft node draggable on graph | Constellation drag presentation (`beginDragNew`, `updateDragPresentation`, `FD/scene/scene_presentation.dart` overrides/holds), `spawnPositionResolver` | **As is**, new placement phase without anchor write (§7.2) |
| Object stays where author put it | Constellation anchors, target kind `beacon` (`ConstellationAnchorTargetKind`) — a Post *is* a beacon | **As is**: the draft drop point becomes the author's `beacon` anchor on publish |
| Thin edges added/removed live | `reconcileTopology(requestLayout:false, layoutOnTopologyChange:false)`; `ConstellationEdgePainter` + `constellation_edge_style.dart` | New edge kind only |
| Radius circle | `GraphView.canvasBackgroundBuilder` (scene space, unused today); `sceneToViewportLocal` | New painter only |
| Forward graph («Граф пересылок») | `ForwardsGraphScreen` (`/graph/forwards/:id`), `BeaconForwardGraphCase.asMap` (gate `canReadInvolvement`: author, forward edge, or room-admitted — Post `addressee` rows pass), `beacon_overflow_menu` `forwards_graph` item | **As is** for Posts; help-offerer path mode (`?committer=`) not offered (§5.4a) |
| Post → Request | In-place: `kind` flip + edit form (`BeaconCreateRoute(editId:)`); room system row via `system_message_kind` | New mutation, reused UI |
| Last activity | `beacon_activity_event`, `latestMainRoomMessageCreatedAt` exist but no stored column | **New column** (§4.4) |

What does **not** exist and must be built: `kind` + `forward_policy` + `last_activity_at` columns,
forward-⇒-admission for Posts, a Post view shell, a composer placement phase, a draft recipient
edge kind, radius selection model, membership webs in the field payload, fade presentation.

---

## 2. Shipped decisions this feature amends (need explicit sign-off)

| # | Current rule (source) | Amendment proposed |
|---|---|---|
| A1 | "Beacon is the only first-class object"; "forwarding matters more than posting"; comments/1:1 chat out of scope (`Tentura_current_status_quo.md` §3, §4.1, §4.2) | Beacon stays the only *table*; it gets two kinds. A Post is addressed (not a feed, not public, not discoverable), so the anti-feed axioms hold. Status-quo doc §4 gains "Post". |
| A2 | Chat admission is always explicit; forward never admits (`CONTEXT.md` § Commitment facts, `features/beacon_room.md:96,165`) | **For `kind = post` only**, an active inbound forward edge *is* admission. Requests unchanged. |
| A3 | D5 / §9.1: forward edges are never drawn in Constellation (`constellation-edge-semantics.md`) | **Decided 2026-09-30:** the forward *chain* is still never drawn on the map (it lives on the existing forward-graph screen, §5.4). New, narrower edge class: **membership webs** from the selected object to people, drawn **only while a Post/Request is selected**, **only to people already placed on ego's map** (D6 unchanged); everyone else collapses into "+N". Two colours: *forwarded to* (has it, not inside) and *inside* (in the room). |
| A4 | D9: only request holders + their path ancestors are drawn | In **composer mode** the composition widens to all forward-eligible visible peers (up to the render cap), otherwise nobody can be picked on the graph. |
| A5 | §9.2 anti-feed: prominence never encodes recency/engagement | A Post's *presence* (fade/expiry) uses conversation recency. Not ranking, not badges, not sort order. Requests unaffected. |
| A6 | Pinning D15/D17: no provisional local-only state | One scoped exception: the composer draft node lives only in the session until publish; on publish it becomes a normal `beacon` anchor. |
| A7 | `person_bond`: co-members of an open beacon are "mutually visible as people" (`m0193.dart:3639-3670`). Used **only** by forwarding: bond peers appear in forward candidates (`forward_candidates_case.dart:41`) and pass the forward recipient gate (`forward_case.dart:236`, `personVisiblePeerIds`); plus the shared-contexts query. It does **not** gate profile reads (Hasura `user` = block check only) and does not feed Constellation. | `kind = post` membership does **not** create a bond. Seeing and contacting each other inside a Post room needs no bond (§5.7); the bond would only add *forward reach*, and for Posts that reach would be unbounded (see Q2). |

---

## 3. Owner decisions (with recommendations)

| # | Question | Recommendation |
|---|---|---|
| Q1 | Where do Posts live for the author and for recipients? | **Decided direction 2026-09-30 (rev 3):** «Для вас» gets **one grouped, non-pinned row per Post**, bumped only by events directed at me (Post sent to me, reply to me, @mention); a second Activity tab **«Разговоры»** lists every Post I'm in («Сейчас» / «Затихли») with per-row counters and no dot. Never My Work (`responsibility_scope_base_beacons` excludes `kind = post`). Plus Моё поле. Details: `post-ux-mockups.md` §Q1, M1–M2. |
| Q2 | Does Post membership create `person_bond`? | **Decided 2026-09-30: no bond.** (Rationale: a Post never closes and an open-forward audience is uncurated, so a bond would be permanent, unbounded forward reach.) Members still see each other, open profiles and add contacts from the room (§5.7). |
| Q3 | On Post → Request, what happens to members admitted "by address"? | **Decided 2026-09-30 (direction):** keep room access with no stake, as an explicit **intermediate participant state** («Участник из поста») from which one tap leads to *Offer help* (normal offer → author acknowledges → helper with stake; already admitted, so no re-admission) or *Leave chat*. UX in `post-ux-mockups.md` §M8. |
| Q4 | Webs on the map | **Decided 2026-09-30:** only on selection; object → *forwarded to* and object → *inside*, different colours; no forward chain. For Requests the *forwarded to* colour is shown only to viewers with involvement read; others see *inside* (admitted helpers — already a content-audience right) only. |
| Q5 | Fade parameters | **Decided 2026-09-30:** `kPostActiveWindow = 72h` since `last_activity_at`, visual fade over the last 24h, then out of the active field (Posts history keeps it; pinned Posts keep their anchor). Any new message/reaction/forward revives it. |
| Q6 | Post "Not interested" | = leave: `inbox_item.status = 2` (existing) **and** `room_access = left` (existing constant). Reversible from Rejected ("Return"). |
| Q7 | Where the Post content lives | **Decided 2026-10-01 (owner):** the Post *is* its room. The Post content is the **author's first message** in the room (text + attachments + mentions) — the *root message*. The beacon row carries no content for Posts (`title`/`description` empty); the room's top pinned strip (the place the Request uses for NOW / plan) becomes a link to the root message. No other surfaces besides the overflow menu. |
| Q8 | Recipient cap per Post send | **Decided 2026-09-30:** no special server cap — handled by interface limits (explicit count + list before Send) and by the separate in-progress "noisy forwarder" MR damping feature. |
| Q9 | Forward policy for Requests | **Decided 2026-10-01 (owner): none.** Requests keep today's rules exactly (any content reader may forward; discoverable by default). «Можно пересылать» is a Post-only mechanic. Converting a closed Post to a Request therefore **opens** forwarding — the convert dialog says so. |
| Q12 | Post «Можно пересылать» | **Decided 2026-10-01 (owner), revised the same day: default on.** A new Post can be forwarded: any member may forward it to anyone mutually visible to them (today's forward rules), and those people join and may forward further. Before sending, the author may switch it **off**, and then only the people the author invited take part (the author can always invite more). After publish the setting is **one-way**: a closed Post can be opened (`beaconForwardingOpen`), but an open Post can never be closed — forwards already made cannot be taken back. |
| Q10 | Can a Post have child Requests / be forked? | No children (hierarchy policy rejects `kind = post`); "Convert to Request" covers the need. Fork allowed only for Requests. |
| Q11 | User-facing noun | «Пост» / "Post" (l10n + `check-user-facing-terminology.sh` allowlist). Its room is "Chat" like a Request's. |

The rest of the plan assumes the recommendations; each unit names the decision it depends on.

---

## 4. Server design

### 4.1 Schema (one migration, `m0201`)

```sql
ALTER TABLE beacon
  ADD COLUMN kind smallint NOT NULL DEFAULT 0,            -- 0 request, 1 post
  ADD COLUMN forward_policy smallint NOT NULL DEFAULT 1,  -- Posts: 1 open (create default), 0 closed (author opt-out); one-way 0 → 1
  ADD COLUMN last_activity_at timestamptz;                -- backfill: coalesce(latest room msg, published_at, created_at)

-- Posts: only draft(3) / open(0) / deleted(2); never discoverable; request-only columns unused.
ALTER TABLE beacon ADD CONSTRAINT beacon_post_shape_ck CHECK (
  kind = 0 OR (status IN (0, 2, 3) AND is_discoverable = false
               AND parent_beacon_id IS NULL AND end_at IS NULL AND start_at IS NULL)
);
-- Requests keep a non-empty title; Posts carry no content on the row (Q7):
--   CHECK (kind = 0 AND title <> '' OR kind = 1 AND title = '' AND description = '')
ALTER TABLE beacon ADD COLUMN post_root_message_id text REFERENCES beacon_room_message(id);
-- Set by trigger on the author's first non-system message in a kind = 1 room; immutable after.
-- Requests are always open: CHECK (kind = 1 OR forward_policy = 1). Existing rows get 1 by the default.
-- One-way is enforced by a BEFORE UPDATE trigger rejecting 1 → 0 on published rows.
```

- **Status reuse, not a new status.** A live Post is `status = 0`, so `allowsForward`,
  `allowsDiscussionWrites`, `BeaconRoomLifecycleWritePolicy` and the lifecycle write-guard trigger work
  with no branch. The cost is that every Request-only query filtering `status IN (0,7,8)` must also
  filter `kind = 0` — handled by the audit unit (S3) and an audit test, not by hoping.
  *Rejected alternative:* a new status value `9 = live post`. It excludes Posts everywhere by default,
  but then every shared gate (forward, room writes, write-guard trigger, client status getters, Hasura
  filters) needs `OR status = 9`, which is the larger and more scattered diff.
- `last_activity_at` is generic (Requests get it too) — `beacon_display_case.dart:82-91` can finally
  pass a real value.

### 4.2 Forward ⇒ admission for Posts (A2)

Trigger on `beacon_forward_edge` (AFTER INSERT, and AFTER UPDATE OF `cancelled_at`), mirroring
`inbox_item_on_forward_insert`:

- insert: if `beacon.kind = 1` → upsert `beacon_participant(beacon_id, recipient_id, role = addressee (new, 6),
  room_access = 3)` unless the row is `left` by the user's own choice. A new role rather than
  `helper`, so no stake/review/People query can mistake an addressee for a helper.
- cancel: if no other active inbound edge remains → `room_access = none`.

Why a trigger and not `ForwardCase`: there are two insertion paths (`ForwardEdgeRepository.createBatch`
and invite acceptance via `UserRepository.bindMutual`), and the trigger covers both plus any future one.
The author is already a member by authorship.

Downstream consequences, each one line of SQL:
- `beacon_member` view: includes `addressee` — needed so realtime/mentions/read-receipts see them.
- `person_bond` / `person_bond_peers`: add `AND b.kind = 0` (A7).
- `beacon_can_read_content`: no change (forward edge is already a read path; discoverability branch is
  dead for Posts by the CHECK).
- Role `addressee` must be ignored by every commitment/review/People-tab query (they filter by
  `beacon_help_offer` / committer roles today — verify in S3).
- Admission writes **no system room row** (decided 2026-10-01): forwards and joins leave no trace in
  the chat. «Участники» shows who joined and who brought them, and lists by name the members who
  have not opened the Post yet (from `room_seen`). Every member sees this list.

### 4.3 Forward policy (single function)

`BeaconForwardPolicy.canForward({beacon, senderId})` in `packages/server/lib/domain/policy/`:
`beacon.allowsForward && (beacon.forwardPolicy == open || senderId == beacon.authorId)`. For a
Request `forwardPolicy` is always `open`, so the function reduces to today's check.
Called from `ForwardCase.forward` (next to the existing `allowsForward` check, `forward_case.dart:218`)
and `InvitationCase.create/_acceptBeaconInviteOnly` (`invitation_case.dart:75,374`). Exposed on the
beacon read model as `viewer_can_forward` (Hasura computed field) so the client never re-derives it.
New mutation `beaconForwardingOpen(id)`: author-only, `kind = post`, `closed → open` only; no
inverse exists anywhere in the API. `beaconCreate(kind: post)` accepts `forwardPolicy` (default
open, Q12).

### 4.4 `last_activity_at`

Trigger bumps on: `beacon_room_message` insert (non-system rows), `beacon_room_message_reaction`
insert, `beacon_forward_edge` insert. Monotonic (`GREATEST`). Debounce is unnecessary at our volume.

### 4.5 Request-only paths reject Posts (one guard)

`BeaconKindPolicy.requireRequest(beacon)` throws a domain exception; called at the top of:
`HelpOfferCase` (offer/withdraw), `CoordinationCase` (accept/decline/remove/release/setResponse/
setBeaconStatus), `EvaluationCase` (close/closeNow/reopen/extend/…), `BeaconCase.beaconCancel`,
`BeaconCase.fork`, `BeaconChildCreateCase`, `beacon_hierarchy_policy.dart`,
`DeadlineReminderSweepCase` query, `beacon_display_case.dart`. `BeaconCase.deleteById` works for Posts
(no committer gate applies — the gate function returns false for Posts naturally, verify).

SQL filters that need `kind = 0`: `constellation_field_snapshot_reader.dart` request list (Posts get their
own section, §6.2), `responsibility_scope_base_beacons` (Q1), `derive_beacon_display_status`, My Work
Hasura query (`my_work_fetch.graphql`), deadline sweep, inbox before-response tombstone trigger (Posts:
no tombstones — they have no close).

**Audit test (S3 acceptance):** a pg test seeds one Post and one Request with the same audience and
asserts the Post is absent from: My Work, the Constellation request section, discoverability, display
status, deadline sweep, help-offer/coordination/evaluation mutations (each throws), person bond — and
present in: inbox, room, attention, forward graph.

### 4.6 API

- `beaconCreate(kind, forwardPolicy, …)` — `kind` immutable afterwards except via convert.
  `BeaconCreationPolicy` skips needs/primary-slug/schedule normalisation for Posts; the create rate
  limit is shared.
- `beaconConvertToRequest(id, isDiscoverable)` — author-only, `kind = post AND status = 0`; in one
  transaction: `kind = 0`, `forward_policy = 1` (Requests are always forwardable, Q9),
  `is_discoverable = arg`, re-derive status (open),
  keep `addressee` members (Q3: role stays `addressee`, which Request code already ignores for stake),
  insert a system room row (`system_message_kind = convertedToRequest`, structural payload only),
  emit `beacon` realtime change. Then the client opens the edit form to add needs/schedule.
- Attention: `relayReceived` copy/category branch on kind ("X shared a post with you" / batch "N posts
  shared with you") in `beacon_notification_copy_builder.dart`; deep link unchanged
  (`/beacon/view/:id`, the view dispatches by kind). No per-message receipts for Posts in v1 (same as
  Requests: unread badge only).
- Hasura: expose `kind`, `forward_policy`, `last_activity_at`, `viewer_can_forward`.

---

## 5. Client design (non-graph)

### 5.1 Domain

`Beacon` gains `kind` (`BeaconKind {request, post}`), `forwardPolicy`, `lastActivityAt`,
`viewerCanForward`. `allowsForward` call sites that decide *whether to show Forward* switch to
`viewerCanForward`. Request-only getters (`canCommitAsViewer`, `allowsCoordination`, …) return false for
Posts — one `isRequest` guard inside the entity, not at every call site.

### 5.2 Create (reuse `BeaconCreateCubit` + the room composer)

- A Post is created by **writing its first message**. The create screen is an empty room: the room's
  own composer (text, attachments, mentions — the same widget as in chat) plus a «Кому» row that
  opens the recipient picker. No Post form, no `InfoTab` variant, no `beacon_image` for Posts
  (photos are message attachments).
- Sequence, reusing existing mutations only: `beaconCreate(kind: post, draft: true)` (for a stable
  id) → `beaconPublish` → `roomMessageCreate` (root; first attachment inline) →
  `roomMessageAttachmentAdd` × n → `beaconForward` (recipients). Until the forward, nobody but the
  author is a member, so no one can see a half-built Post. The trigger in §4.1 stamps
  `post_root_message_id`.
- Recovery: a published Post with no root or no recipients is **unsent** — it shows only to the
  author in «Разговоры» as «Не отправлено · Дописать / Удалить» and resumes the same sequence.
  (Alternative if this proves flaky: one server `PostCase.publish` doing the same steps in one
  transaction — same repositories, no new tables.)
- Requests keep today's form and rules unchanged (`BeaconCreateRoute(kind: request)`).
- Post only: `ForwardingSwitch` («Можно пересылать», default **on**) in the «Кому» row; the author
  may switch it off before sending. After publish a closed Post shows a one-way «Разрешить
  пересылку» author action with a confirmation; an open Post shows a locked state.
- Entry points: My Work "+" becomes a small menu (Post / Request); Activity app bar gets "New post";
  Constellation composer (§7).

### 5.3 Room reuse: the `RoomHost` seam (refactor R1, no behaviour change)

Today `BeaconRoomSurface` needs `BeaconViewCubit`; `ThreadHostCubit` pulls `BeaconStatus` from it;
`RoomCubit.load` fetches facts/room state/blocker/plan; `BeaconRoomBody` and `RoomMessageTile` import
Request-only sheets (commitment, child promotion, facts, blocker).

Introduce in `features/beacon_threads/domain/`:

```dart
abstract interface class RoomHost {
  String get beaconId;
  String get authorId;
  BeaconStatus get status;           // write gate
  bool get isAdmitted;               // replaces isRoomAdmissionBlocked / coordinationDeniesRoomAdmission
  RoomCapabilities get capabilities; // facts, blocker, promoteToChild, commitmentSheet, currentLine
  Stream<void> get changes;
}
```

`BeaconViewCubit` implements it with all capabilities on (Requests: zero behaviour change, proven by
the existing widget tests). `PostViewCubit` implements it with capabilities off. `RoomCubit` skips the
fact/state/blocker/plan loads when the capability is off; tile/body actions are gated by the same
flags. The `listThreads`-before-render prerequisite becomes a Request capability (a Post always has
General).

### 5.4 Post view = the room

Same route `/beacon/view/:id`; `BeaconViewScreen` dispatches by `kind` (deep links, notifications,
share links unchanged). A Post screen **is** `BeaconRoomSurface` via `RoomHost` and nothing else: no
header card, no tabs, no HUD/STATUS/NOW/People/Log.
- The room's top pinned strip (where a Request shows NOW / pinned facts) shows the root message
  excerpt; tap scrolls to the root. `RoomCapabilities.pinnedStrip = postRoot`.
- The root is an ordinary message: reactions, replies (`reply_to_message_id`), edit and delete use
  the existing message actions. Deleting the root = deleting the Post (author only, confirm).
- Forward provenance for a forwarded recipient («Вам переслала Мария: …») is a quiet line inside
  the pinned strip.
- Overflow ⋮ carries all management: pin/unpin, mute, participants, forward graph, show on map, forward (if
  `viewerCanForward`), enable forwarding (author, one-way), convert to Request (author), leave
  (recipient), delete (author).
- **Forward graph (decided 2026-10-01).** Any member opens the existing `ForwardsGraphScreen` for
  the Post (⋮ «Граф пересылок», and «Как пост дошёл до людей ›» in «Участники»). No new screen,
  query or permission: `canReadInvolvement` already admits every Post member. Post differences
  only: no help-offerer path mode and no commitment colours (no offers exist). This is the one place
  the forward chain is shown. The map still never draws it (A3), and the chat carries no
  forward rows (§4.2).
- Previews elsewhere (Activity rows, «Разговоры», map node, notifications) read the root message:
  server surfaces join `post_root_message_id`; the client «Разговоры» list gets the excerpt + last
  message from the existing `inboxRoomContextBatch` query (extended with the root excerpt).

### 5.5 Forward screen: `ForwardTargetProfile` (refactor R2)

Derived from `Beacon.kind` inside `ForwardCubit`; `ForwardRecipientPicker` reads it to hide:
capability band (`ForwardBandStrip`), reason chips, lineage section, attribution dialog, offer-help
nudge, requirements bar in `CompactBeaconContextStrip`. Candidates, involvement, notes, availability,
invite bar, search — unchanged. Server `forward_band_case` is simply not called for Posts.

### 5.6 Activity

- **«Для вас»:** one grouped row per Post (reuse of the per-object grouping of `requestActivity`
  rows, `attention_repository.dart:~545`), **never** in the pinned «unanswered forward» zone: the
  synthetic `forward` row (`inbox_item` → `item_kind 'forward'`) is excluded for `kind = post`, and the
  arrival is an optional update instead. Events: `relayReceived` (Post variant), `roomMessagePosted`
  (reply to me), `roomMentioned` (@mention) — all already exist — plus one new event
  **`postFirstResponse`** for the author: emitted on a person's **first response** to the author's
  Post — their first message in the room **or** their first emoji reaction on the root message,
  whichever comes first (one event per person; later messages/reactions by the same person don't
  emit). Emitted from the existing attention blocks of `BeaconRoomCase.createMessage`
  (`beacon_room_case.dart:430-478`) and the reaction toggle; the grouped row lists names and
  reactions; they get Post declarations in
  `docs/contracts/updates-event-contract.json` (scope: object; class: optional update; group key: the
  Post; clear: open or ×; never promotes; recoverable via «Разговоры»). Client: `PostAttentionRow`
  variant in `for_you_stream_entries.dart` / `activity_stream_view.dart` (branch on kind, not a new
  list).
- **«Разговоры» tab:** `TenturaPrimaryTabBar` in the Activity top bar; list = Hasura query of beacons
  where `kind = post` and viewer is author or active addressee, ordered by `last_activity_at`, split at
  `kPostActiveWindow` into «Сейчас» / «Затихли»; per-row unread count from `beacon_room_seen`. No tab
  dot.

### 5.6a Mute, pin, leave (all reuse)

- **Mute:** `notification_beacon_mute(account_id, beacon_id, muted_until)` + V2 `beaconMuteSet` /
  `beaconMuteClear` already exist (`mutation_notification_preferences.dart:60-78`) and
  `NotificationPreferenceGate` already blocks push/email for muted beacons. Missing: client UI (none
  today) and the in-app rule — for a muted Post, the «Для вас» row is suppressed for every event
  except `roomMentioned` (visible, no push). Durations 1h / 3h / 1d / 3d / forever (`null`).
  The same UI can later be offered on Requests.
- **Pin in «Разговоры»:** reuse `beacon_pinned` + existing pin/unpin mutations
  (`features/favorites/data/gql/beacon_pin_by_id.graphql`). For `kind = post` it means "pinned on
  top of «Разговоры», never ages out of the list"; the Favorites screen keeps filtering to Requests
  (`kind = 0`), so the two meanings never mix on one screen. Needs a `pinned_at` column for pin-time
  ordering (the table has none today).
- **Leave:** `inbox_item.status = 2` + `room_access = left` (plan §4.2); lists in the existing
  «Не интересно» archive with «Вернуть» (re-admits). No system row. A later re-send from someone
  else produces an arrival row with «Вернуться в разговор» and does **not** re-admit automatically
  (the §4.2 trigger already skips `left` rows). Author cannot leave.

### 5.7 Meeting people inside a Post room

Goal (owner): everyone in the room sees each other; I can open the profile of someone far away on my
graph and add them to contacts right from the chat, and they can add me back.

All of this already works without any visibility change:
- Profile reads are gated only by blocks (Hasura `user.hidden_for_viewer` → `block_hides`), so any
  member can open any other member's profile.
- Room members (author + `addressee`s) are listed through the same participant projection as Request
  chat; message author avatars open the profile sheet.
- "Add to contacts" = the existing `vote_user` trust action from the profile.
- The other person receives the existing `trustReceivedChanged` Activity event and can add back;
  reciprocity fires `mutualConnectionFormed`. That reciprocal explicit trust is what makes the two
  mutually visible (and forwardable) from then on — through the normal, deliberate path.

Work here is UI only: make sure the room message author tap → profile sheet with "Add to contacts"
exists for Post rooms (reused from Request chat via `RoomHost`), and optionally a small "you both are
in this Post" line on that sheet (reuse `sharedContexts`, extended to include `kind = post`).
A dedicated "ask them to add me" request does not exist today and is not needed for v1: adding them
already notifies them with an add-back action.

### 5.8 Convert to Request

Author action on the Post view → confirm dialog (states: audience keeps access, forwarding becomes
open because every Request is forwardable, choose discoverability) → `beaconConvertToRequest` → open
`BeaconCreateRoute(editId:)` on the now-open Request (edit of an open Request is already supported,
`loadEdit`). The form is **prefilled from the root message** (first line → title, rest →
description, image attachments offered as the cover) — a one-time copy, because a Request needs
its own content. The root message stays as the first message of the chat, and the top strip becomes
the Request's normal NOW / pinned-facts area. `post_root_message_id` is kept (harmless).

---

## 6. Constellation: showing Posts and membership webs

### 6.1 Node model

Do **not** add a sibling sealed class: extend the existing `FieldRequestNode` into
`FieldBeaconNode(beacon, kind)` (rename is mechanical). Anchors, tap resolution, selection, overlay
labels, semantics and preview routing all already work per request node; only the node glyph, status
marker (none for Posts), and placement rule branch on `kind`. `ConstellationRequest` gets `kind`,
`memberIds` (placed members only), `lastActivityAt`.

### 6.2 Server payload

`constellationField` gains:
- `posts`: Posts where viewer is author or active addressee, `status = 0`,
  `last_activity_at > now() - kPostActiveWindow` (or pinned by the viewer).
- `memberWebs {beaconId, personId, state: forwarded|inside}` for those Posts — **not** the forward
  chain (A3). For a selected Request the same shape is fetched lazily (new small query
  `beaconMemberWebs(id)`: admitted helpers for every content reader, forward recipients only with
  involvement read).

`inside` = room member (`beacon_member`); for Posts additionally "has opened it" (`beacon_room_seen`
row exists) — a recipient who never opened is `forwarded`. The server drops persons that are not in
ego's mutually visible peer set (D6/§9.1) and returns `hiddenReachCount` per object instead. No
`parent_edge_id` data ever reaches the field.

### 6.3 Placement

New semantic-ideal rule in `computeConstellationPlacedLayout`: a Post with no anchor is placed at the
**barycenter of its placed members** (author included), then goes through the existing collision
candidate search. The author's composer drop point is stored as a `beacon` anchor at publish (§7.5), so
the author always sees it exactly where they put it; recipients see it among the people it reached.

### 6.4 Rendering

- New `ConstellationEdgeKind.webForwarded` / `webInside` (thin, low-alpha, non-directional; two
  colour tokens) + `draftRecipient` (§7). Drawn only for the selected object.
  Style cases in `constellation_edge_style.dart`; legend entries. The pair-uniqueness assert in
  `addEdge` (`constellation_cubit.dart:2263`) becomes per-kind (a web may coincide with a trust
  path between the same two people).
- Webs are a star from the object to each placed member, never person→person.
- Fade: opacity = f(`lastActivityAt`, `loadedAt`) computed in the presentation frame; no recency
  ordering anywhere (A5).
- "+N reached" chip reuses the overflow chip widget.
- Snapshot semantics stay (D15): relay growth appears on refresh; realtime growth is a follow-up.

---

## 7. Constellation composer (create on the graph)

### 7.1 Entry

- Toolbar button "Create here" (Post / Request) + desktop secondary-tap on empty canvas + touch
  long-press on empty canvas (never long-press alone — cross-platform rule). The draft spawns at the
  pointer (or viewport centre for the button).

### 7.2 State ownership

```
ConstellationComposerCubit (thin)       — draft position, radius, manual adds/removes, mode
   ├── BeaconCreateCubit (kind)         — content + server draft (ensureDraft on first edit)
   └── ForwardCubit(draftId, embedded)  — candidates, eligibility, selection, notes, send
```

- **Selection truth lives in `ForwardCubit`.** The composer computes
  `selected = (inRadius ∪ manualAdded) \ manualRemoved`, intersects with `canForwardToOn`, and syncs it
  into `ForwardCubit` (`initialSelectedIds` / toggle API). The pure model
  `RadiusRecipientSelection` lives in `features/constellation/domain/` and is unit-tested on its own:
  manual adds survive shrinking the radius; manual removes survive growing it; ineligible people are
  never selected.
- `ConstellationPlacementPhase.composing` (new): the draft is a topology node `fd:draft` positioned by a
  presentation override (the same machinery as `draggingNew`), **no anchor write** until publish (A6).
  Person drag-to-pin is suspended in this phase so tap/drag on people means recipients, not pins.

### 7.3 Composition widening (A4)

On entering composer mode the cubit recomposes with `includeForwardCandidates: true`: all visible
peers that are forward candidates (`fetchForwardCandidates` ∩ `field.peers`) are kept and laid out on
their rings, up to the render cap; pinned people keep positions. Exit restores the normal composition.
Ineligible visible people (paused, blocked, already involved) render disabled with the reason on tap
(reusing `ForwardRecipientRowHost` copy).

### 7.4 Gestures (v1)

- Drag the draft node: move (presentation override; radius re-evaluates on drop, not per frame).
- Tap a person: toggle manual add/remove → edge appears/disappears (`reconcileTopology` without
  relayout).
- Radius handle on the circle rim: drag to resize (scene-space circle via `canvasBackgroundBuilder`);
  people whose scene position is inside are proposed and edges draw immediately.
- **Deferred to v2:** drag a line from the draft to a person; drag a person onto the draft
  (`mapNodeAtSceneCentre` exists as the hit test).
- Bottom composer sheet: body (Post) or title + short description (Request), recipient count
  «Будет отправлено: N» with the list, forward policy (Post), personal note (existing
  `ForwardBottomComposer`), "List view" (opens `ForwardRecipientPicker` on the *same* `ForwardCubit` —
  the accessible path and the Text-view parity answer), "More details" (Request → full
  `BeaconCreateRoute` with the same draft id and preselected recipients), Send.

### 7.4a UX details (from `post-ux-mockups.md` §K)

- Starting radius = distance to the 3rd-nearest eligible person (+ margin); `RadiusRecipientSelection`
  owns this rule.
- Radius membership is recomputed on draft drop, live while dragging the radius handle.
- Wide layout: the composer sheet is a side panel; hover links chip ↔ web; right-click on a person
  toggles.
- A11y: «Списком» (list picker on the same `ForwardCubit`) + a radius slider in the sheet.
- Cancel: an empty draft exits silently; a Post draft with content asks and is **deleted** (Post
  drafts are not kept); a Request draft follows today's rule (stays in My Work drafts).
- After Send: the Post is briefly shown selected with its *forwarded* webs, then settles.

### 7.5 Publish

Existing `BeaconCreateCubit.sendRequest` (publish → forward → confirmation dialog), then
`ConstellationAnchorCase.upsert(beacon, dropPoint)` so the object stays where the author placed it. The
cubit reloads the field (snapshot), and the new node appears; selecting it shows its webs.

### 7.6 Request vs Post in the composer

Identical except: Request content sheet has title + need, no forward policy, "More details" is
prominent; the published Request is discoverable per the author's choice and gets its normal
satellite placement for others (the author's pin keeps it at the drop point for the author only).

---

## 8. Units (dependency-ordered)

| Unit | Scope | Depends | Acceptance |
|---|---|---|---|
| **P0** | Owner decisions Q1–Q11 + doc amendments A1–A7 (status quo, CONTEXT, edge-semantics, pinning, beacon_room, visibility matrix, terminology) | — | Docs merged |
| **S1** | `m0201`: columns, CHECKs, backfill, `last_activity_at` triggers, forward⇒admission trigger, `addressee` role, `beacon_member`, `person_bond(_peers)` `kind = 0` | P0 | pg tests: admission on forward/invite accept, revoke on cancel, no bond, activity bump |
| **S2** | `BeaconForwardPolicy` in forward + invitation (Post closed/open); `beaconForwardingOpen` one-way (Posts); `viewer_can_forward`; Hasura metadata | S1 | pg tests: closed/open Post, one-way trigger, invite path, Requests unchanged |
| **S3** | `BeaconKindPolicy.requireRequest` + `kind = 0` filters + audit pg test (§4.5) | S1 | audit test green |
| **S4** | `beaconCreate(kind, forwardPolicy)`, `beaconConvertToRequest`, notification copy branch | S2, S3 | pg + unit tests |
| **R1** | Client `RoomHost` seam (no behaviour change) | — | existing room/beacon_view tests unchanged and green |
| **R2** | `ForwardTargetProfile` (no behaviour change for Requests) | — | existing forward tests green |
| **R3** | `BeaconCreateCubit(kind)`; Post create = empty-room screen with the room composer + «Кому»; `ForwardingSwitch` (Posts) + published-Post one-way action; unsent-Post recovery | S4 | widget tests |
| **C1** | `Beacon` domain fields + `isRequest` guards; codegen | S4 | unit tests |
| **C2** | Post view = room only (kind dispatch, `PostViewCubit implements RoomHost`, pinned strip → root, overflow incl. «Граф пересылок» → existing `ForwardsGraphScreen`) | R1, C1 | widget tests; pg test: Post addressee passes `canReadInvolvement` |
| **C3** | «Для вас» Post row (grouped, non-pinned, contract declarations) + «Разговоры» tab (history split, pinned section); mute UI + muted in-app rule; pin via `beacon_pinned` (+ `pinned_at`); leave/return via «Не интересно»; Not interested = leave; room author tap → profile + Add to contacts (§5.7) | C1 | widget tests |
| **C4** | Convert to Request flow | C2, S4 | widget test + pg test |
| **G1** | Server field: `posts`, `memberWebs`, `hiddenReachCount`; `beaconMemberWebs(id)` query for Requests | S1 | pg test incl. D6 drop and involvement gate |
| **G2** | Client `FieldBeaconNode(kind)`, barycenter placement, web edge kinds (selection-only), fade, "+N reached" chip, per-kind edge uniqueness | G1, C1 | domain layout tests + widget tests |
| **G3** | Request webs on selection (lazy `beaconMemberWebs`) | G2 | widget test |
| **K1** | `RadiusRecipientSelection` pure model | — | unit tests |
| **K2** | Composer phase: draft node, widened composition, draft edges bound to `ForwardCubit`, tap toggle, radius painter + handle | G2, K1, R2, R3 | widget tests (structural, no goldens) |
| **K3** | Composer sheet, list-view handoff, More details handoff, publish + anchor | K2 | widget + integration_test (web e2e) |
| **V** | Client version bump + `index.html` cache-buster + `kDefaultMinClientVersion` | all | — |
| **F** (follow-ups) | drag-line / drag-onto gestures; realtime relay growth; per-message Post attention if wanted | — | — |

R1, R2, K1 have no server dependency and can start immediately in parallel with S1–S4.

---

## 9. Risks

- **Status reuse leaks Posts into Request surfaces.** Mitigated by S3's audit test; any new Request query
  written later must filter `kind = 0` — add a line to `DEV_GUIDELINES.md` and consider a SQL lint grep in
  CI for `status IN (0` without `kind` in `packages/server/lib/data/**`.
- **`RoomHost` refactor touches large files** (`RoomCubit` 1447, `RoomMessageTile` 2718,
  `BeaconRoomBody` 1199 lines). Land it as a pure refactor with no behaviour change before any Post UI.
- **Composer widening shifts the layout** when entering the mode. Accept (pins stable, 350 ms
  transition); revisit only if it tests badly.
- **Radius selecting too many people.** Soft cap (Q8) + explicit count and list before Send; nothing is
  sent without the Send tap.
- **Addressee role vs existing People/committer queries** — verify in S3 that no count, face pile or
  review composition includes `role = 6`.
- **Conversion race** (a forward in flight while converting) — conversion takes the same beacon row lock
  the forward transaction takes; trigger-created addressee rows stay valid for a Request (Q3).
