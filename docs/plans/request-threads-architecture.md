> **Superseded** by [`nested-requests-implementation-plan.md`](nested-requests-implementation-plan.md) — ask/promise/blocker coordination-item threads retired in favor of General-only Discussion and nested child requests; see [`nested-requests-implementation-journal.md`](nested-requests-implementation-journal.md).

# Request Threads — Architecture

**Status:** architecture draft, **rev 6**, awaiting approval. Shape only — no implementation steps,
no file-by-file task breakdown. Decisions **D1–D14** were taken by the product owner in a design
interview (2026-08-14) and are binding, as is **D27** (taken later in the same session). **D15–D26**
are consequences those answers force; they are
equally binding but were derived, not chosen, and a reviewer may overturn them on evidence.

**Revision history.** rev 6 — a third review (Grok 4.6, both documents, 15 findings, 6 blocking).
Its most important finding was **methodological**: the rev-5 corrections were applied as a banner at
the top of the plan plus one patched spot each, but a fresh-context executor starting at "UNIT 04"
reads only that unit — so the plan still told it to build the GraphQL union, skip the plan-log remap,
and keep the `observeReadThrough` guard. **The implementation plan is therefore being regenerated
from this document rather than patched again** (three consecutive reviews found the same
patch-does-not-propagate failure). Substantive corrections here: `beacon_you_presentation.dart` is
**not** change-free — it borrows `CoordinationItemKind.resolution` as the *help-offer review chip
icon*, a different product concept that D27 must not delete (§3.6); `currentCoordinationPlan` has
**zero readers**, closing Q12 by deletion (§4.6); the preview `kind` codes are now **assigned**
rather than left for implementers to invent (§4.3); there is a **third** copy sense — fact-card
visibility — and one glossary table, since `terminology.mdc` has a single workspace column that
cannot be both "thread" and "discussion" (§14.1); **four** kind-4 SQL sites, not two (§13); D13's
query-param URL and D24's real route are reconciled as a nested child page (§8.2, §9.1); and
"alongside `BeaconViewCubit`" is *not* a shared ancestor, since that cubit is created inside
`wrappedRoute` (§8.2). Q9 is now closed as **implement the `RETURNING` fix**, not as an assumption to
skip it.

rev 5 — a second adversarial review (codex/GPT-5.6 Sol, both documents
together, 11 findings, 5 blocking) falsified four more claims and caught two decisions that had not
propagated. The load-bearing ones: **the message-preview GraphQL union is unimplementable** on the
pinned `graphql_server2` 6.5.0, which resolves unions structurally and rejects `__typename` — it is
now a single object with a `kind` discriminator (§4.3); **there are nine semantic-marker families,
not five**, plus coordination rows carrying `semanticMarker == null` (§4.3); **watermark storage is
already monotonic** via `GREATEST` for General *and* threads, so rev 2–3's "threads can move
backwards" was false — the real bug is the mutation returning the submitted rather than persisted
timestamp (§5.3, Q9 restated); **`plan` log rows still need a focus target** since plan is a live
kind excluded from the list, so only the resolution-parent remap is withdrawn (§11.4); and
`observeReadThrough` is **gated to General**, so thread-keying the store alone leaves the flicker
in place (§5.4). Also: `admissionReason` is a `String`, not an `Int`.

rev 4 — owner decision **D27: the resolution feature is removed entirely**
(§3.5). `AcceptResolutionCase` was a propose→approve handshake around a status flip that
`resolveAsk`/`resolvePromise`/`resolveBlocker` already perform directly. This *shrinks* the Threads
work: **D15 and D26 dissolve**, open question **Q11 closes by deletion**, the `activeForMeOnly`
one-hop rule and its `resolutionParent`/`byId` plumbing go, the pending-resolution banner and its
detail-time fetch go, and the composer is never conditionally disabled. It costs one visible change
outside this screen — My Work's YOU line loses its **"reviews"** segment (new **Q13**) — and one
migration (delete `kind = 4` rows) so `CoordinationItemKind.fromInt(4)` cannot crash on dev data.

rev 3 — a fourth review (Kimi K3, second posture) landed after rev 2 and found
three things that survived it, one of which rev 2 itself introduced: (a) **D24 makes a window-class
change a navigation action**, so §8.2's "resize is pure re-layout" held only *within* a class — the
expanded↔compact transition contract is now specified, and `openThreadId` must live above both pages
(§8.2); (b) `_StaleDeadlineTicker` is private to `items_tab.dart`, a file §13 deletes, so it must be
extracted first or stale labels stop ticking (§11.1); (c) the app-bar unread badge comes from the
**shared inbox room-context hints batch** that Inbox and My Work also consume, not a "room-state
read" — only the beacon-view consumers are deletable (§5.6).

rev 2 — corrected against three adversarial reviews (GPT-5.6 Sol via codex,
Grok 4.6 and Kimi K3 via cursor-agent — 51 findings) plus a self-verification pass, which between
them falsified **fourteen** claims rev 1 made about the existing code. All three reviewers
independently produced the first finding below; two independently produced the third. The four that
mattered:

1. `beacon_items_seen` is **not** dead — a raw-SQL `LEFT JOIN` in `responsibilityCountsByBeaconIds`
   feeds My Work's `askNew`/`promiseNew`/`blockerNew`/`reviewNew`, and `BeaconViewCubit`
   calls the mutation on every YOU-line refresh. rev 1's "drop the dead table" would have made every
   responsibility item read as new forever. **D11 is amended** (§5.5).
2. `"general"` **cannot** travel as a `threadItemId`. Every server room method branches on
   `tid != null && tid.isNotEmpty` *before* SQL, so `"general"` would be treated as an item thread,
   fail `_canAccessThread`, and strip General of fact cards, plan, room state and its watermark.
   **D18 is amended** (§3.4).
3. `ensureCanCoordinateOnBeacon` is **strictly narrower** than `_canAccessThread`, so rev 1's
   "authorization is unchanged" would have revoked item-thread access from non-admitted
   creators/targets/accepters. **D21 is overturned** and replaced by the union rule (§4.4).
4. A keyed `BlocProvider` **cannot** enforce close-before-open: `BlocProvider.dispose` does not await
   `cubit.close()`, and `RoomCubit.close()` flushes mark-seen asynchronously. rev 1 named
   `itemDiscussionProviders` as the model to follow while also requiring an ordering it cannot
   provide (§8.4).

Also corrected: General's mark-seen goes through a *different* mutation than threads' (§5.2); the
local watermark store is beacon-keyed and already leaks item-thread reads into General's count
(§5.4); the badge must resolve through that store or it flickers (§5.6); the per-item unread
predicate has three clauses, one of which must **not** be applied to General (§4.5); pending
resolutions are not in the item row (§12); system-message previews need a token union, not a boolean
(§4.3); a message-driven CTE would drop message-less items and drafts (§4.5); `ItemCard` is
request-scoped only and should be evolved in place rather than forked (§11.1); and rev 1's route
paths, param names (`item`/`message`, not `coordinationItemId`/`messageId`), query-count claim, and
deletion inventory were all wrong (§9, §13).

rev 1 — initial blueprint from the design interview.

**Scope.** The information architecture of the Request detail screen: replace the Room-vs-Elements
split with one **Threads** model, `Request → Threads → General | Ask | Commitment | Blocker`. Not a
rewrite of Ask/Commitment/Blocker lifecycle logic, not a generic messenger abstraction. Threads are
strictly request-scoped and have no existence outside a Request (internally: Beacon).

**Zero users.** Backward compatibility, URL aliasing, and backfill for renamed concepts are out of
scope. Old query params are deleted and their producers rewritten — not aliased, and not redirected
(§9.2, closing rev 1's D7-vs-D13 contradiction).

---

## 0. One-page summary

"Room and Elements should be one list of Threads" is **already true in the database and half-true in
the client**:

- `beacon_room_message.thread_item_id` is nullable — `NULL` = main room, non-null = item thread.
  Every message already belongs to exactly one thread.
- `beacon_room_seen` is already keyed `(user_id, beacon_id, thread_item_id)`. Read state is already
  per-thread.
- `RoomCubit(beaconId:, threadItemId:)` already renders either surface; `ItemDiscussionPane` already
  composes "semantic header + banner + conversation"; `BeaconRoomBody` is already the shared body.

What does not exist is a **single list**, a **single way in**, and a **single name for "which thread
is open"**. Today there are three and they disagree:

1. **Elements tab** (`kBeaconTabItems`, RU «Элементы») — a card list inside the operational
   `CustomScrollView`.
2. **Room surface** — not a tab. An app-bar chat button does `pushPath('?tab=room')`; on `expanded`
   it is instead the right pane of an ops|room split that is not in the URL until it must be resynced.
3. **Item threads** — a third mode: `_activeThreadItem` swaps the room pane in place when
   `canNestItemDiscussionInRoomPane(...)` allows, else pushes a separate `ItemDiscussionScreen`.

The cost is concentrated in `beacon_view_screen.dart` (1743 lines), whose comments record the pain:
reentrancy guards on room exit, `pop()` vs `back()` vs `maybePop()` vs `replacePath()`, post-frame
`_syncActiveThreadHost` reconciliation, and a `PopScope.canPop` encoding all three modes at once.

The target replaces all three with one selection — **which thread is open** — expressed once in the
URL, resolved once into a pane, rendered by widgets that already exist.

**What this is not.** rev 1 undersold the work. Three reviewers independently showed that the
"cleanup" story hides four genuinely hard seams: cubit lifecycle ordering (§8.4), the routed-detail
back stack (§8.3), unread reconciliation across three watermark mechanisms (§5, §6), and the
sliver/box boundary (§10.5). Those are the risk in this change, not the list UI.

---

## 1. Binding decisions

| # | Decision |
|---|---|
| **D1** | **Threads replaces Items as tab 0.** Tab bar stays three-wide: `Threads \| People \| Log`. |
| **D2** | **General is row 0 of the Threads list** — for viewers who have room access (§4.4). |
| **D3** | **Unified navigation** for every *addressable thread*: `compact`/`regular` push a detail with its own URL; `expanded` shows a two-pane split. Drafts (D16) are the one explicit exception, not a per-kind branch. |
| **D4** | **List scope:** active published Ask/Commitment/Blocker, a collapsed **Closed (n)** fold, and the viewer's own unpublished **drafts**. Plan and plan steps stay out. |
| **D5** | **Row = today's `ItemCard`, evolved.** Every fact the card shows now is preserved; last-message author/excerpt and timestamp are added. General is pinned first. |
| **D6** | **Expanded split:** left = header/HUD + tab bar + tab body; right = the selected thread, **General preselected**, staying co-visible when the left switches to People or Log. |
| **D7** | **The app-bar chat button and the `?tab=room` / `?surface=room` surface are deleted**, and their producers rewritten (§9.3). General is reachable only through the Threads list. |
| **D8** | **The server returns the uniform thread list** including a synthetic General row, via one new query. |
| **D9** | **Fat row contract:** identity + counts + last-message + a nullable embedded coordination-item block reusing the existing `CoordinationItemRow` type verbatim. |
| **D10** | **Liveness by refetch** off the existing `BeaconRoomInvalidation` stream — with a latest-wins concurrency policy, not merely a debounce (§6). |
| **D11** | **Read state unified for *threads*:** one `markThreadSeen(beaconId, threadId)` API absorbing `MarkBeaconRoomSeen` **and** `BeaconParticipantRoomSeen`. **Amended:** `beacon_items_seen` is a different concept (a responsibility-digest watermark for My Work) and is **retained** — see §5.5. |
| **D12** | **Threads tab badge = General unread + thread unread**, with the closed-thread question settled in §5.4. |
| **D13** | **URL:** `?tab=threads&thread=general\|<itemId>`. `message=` survives as a within-thread scroll target. |
| **D14** | **`features/beacon_room` is renamed `features/beacon_threads`** and absorbs the list. |
| **D15** | ~~`resolution` items stop being list rows.~~ **Superseded by D27** — they cease to exist, so nothing needs re-homing, remapping, or excluding. |
| **D16** | **Draft rows do not open a thread** — tapping opens the existing composer sheet. Drafts are rows, not addressable thread ids. |
| **D17** | **`ItemDiscussionScreen` and its route are deleted**, along with every direct `ItemDiscussionRoute` producer (§13). |
| **D18** | **`general` is a reserved id at the route and list-API boundary only.** **Amended:** it is translated to `null` at the *GraphQL/use-case entry* of every room method, and `RoomCubit` for General is constructed with `threadItemId: null`. `"general"` never travels as a `threadItemId` (§3.4). |
| **D19** | **The server never localizes.** General carries no title; system last-messages travel as a closed token union (§4.3). |
| **D20** | **Grouping and ordering are client-owned presentation.** |
| **D21** | ~~Authorization is unchanged.~~ **Overturned.** Authorization is *preserved*, which requires two inclusion rules, not one guard (§4.4). |
| **D22** | **The rename (D14) lands as a pure mechanical move**, separate from behavior change. |
| **D23** | **The thread host owns cubit lifetime with an awaited close.** A keyed `BlocProvider` is not the mechanism (§8.4). |
| **D24** | **Thread detail on compact/regular is a real route**, not a query-param variant of the current page (§8.3). |
| **D25** | **The threads list is driven from `General UNION ALL eligible coordination_item`**, left-joined to message aggregates — never from a message-driven CTE (§4.5). |
| **D26** | ~~Pending-resolution state stays a detail-time fetch.~~ **Dissolved by D27** — there is no pending resolution to fetch. The list query really is one round-trip. |
| **D28** | **User-facing "Chat" is retired.** Three-level vocabulary (owner decision): **запрос/Request** → **обсуждение/discussion** (the collective space, used for admission and membership) → **тема/thread** (one thread; the built-in one is **Общее/General**). Amends `terminology.mdc`, `AGENTS.md`, `CONTEXT.md`, and ~133 ARB values (§14.1). |
| **D27** | **The resolution feature is removed entirely** (owner decision, rev 4). `CoordinationItemKind.resolution` and the propose→accept/reject handshake are deleted from client and server. Direct `resolve*` is the only way an item resolves (§3.5). |

---

## 2. What already exists (do not rebuild)

**Storage.**

| Table | Fact |
|---|---|
| `beacon_room_message` | `thread_item_id text NULL REFERENCES coordination_item(id) ON DELETE CASCADE`. NULL = main room. |
| `beacon_room_seen` | **No SQL primary key.** m0072 creates four plain columns plus two *partial* unique indexes — `uq_beacon_room_seen_main (user_id, beacon_id) WHERE thread_item_id IS NULL` and `uq_beacon_room_seen_thread (…, thread_item_id) WHERE thread_item_id IS NOT NULL` — because `NULL ≠ NULL` in btree and a nullable column cannot sit in a PK. The Drift class declares a `primaryKey` the real schema does not have. |
| `beacon_items_seen` | **Live.** Read by a raw-SQL `LEFT JOIN` in `responsibilityCountsByBeaconIds` (`coordination_item_repository.dart:1278–1312`) producing `askNew`/`promiseNew`/`blockerNew`/`reviewNew`; written from `BeaconViewCubit`'s YOU-line refresh. **Out of scope — retained** (§5.5). |
| Indexes on `beacon_room_message` | `(beacon_id, created_at DESC)` (m0036) and partial `(thread_item_id, created_at) WHERE thread_item_id IS NOT NULL` (m0072). No `(beacon_id, thread_item_id, created_at)` composite; General's slice is not covered by the partial index. |

**Server.** `BeaconRoomCase` send/list/mark-seen all take `threadItemId`; `CoordinationItemWithCounts`
already carries per-item `messageCount`/`unreadCount`/`lastSeenAt`; `markBeaconRoomSeen` already
writes with the correct dual `ON CONFLICT … WHERE` partial-index predicates
(`beacon_room_repository.dart:1102–1129`).

**Client.** `RoomCubit(threadItemId:)`, `BeaconRoomBody` (takes **no** `threadItemId` — it reads
`RoomCubit` from context), `ItemDiscussionPane`, `ItemActionsCubit`, `ItemCard` +
`coordination_item_card_chrome.dart` + `coordination_item_presenter.dart`, `BeaconRoomInvalidation`
+ the `entity_changes` websocket path, `AccordionExpansionGroup`, `TenturaUnderlineTabs`,
`TenturaChatColumn` / `TenturaContentColumn`.

**Already true, contrary to rev 1's framing:** the expanded split is *current behavior* — 
`_buildExpandedSplitBody` is already a `Row` of operational body + room pane that stays up across
People/Log. D6 preserves it rather than inventing it.

---

## 3. Target model and vocabulary

### 3.1 The thread

```
ThreadId   = "general" | <coordination_item_id>
ThreadKind = general | ask | promise | blocker
```

Code and wire keep `promise`; the user-facing label is **Commitment** (§16-Q1). There is deliberately
**no** `Thread` domain aggregate: a thread is an *addressing scheme over existing storage*. General's
messages are `thread_item_id IS NULL`; a semantic thread's are the same table filtered by item id; a
semantic thread's state is the coordination item row. No thread table, no membership, no creation API
— which is what keeps this from becoming a messenger.

### 3.2 The four roles

| Role | General | Semantic |
|---|---|---|
| Conversation | yes | yes |
| Semantic state (status, parties, deadline) | — | yes |
| Lifecycle actions | — | yes |
| Deletable | never | via item cancel/supersede, unchanged |

Every branch on this difference must test **presence of the item block**, never a kind check.

### 3.3 What is not a thread

- **Plan / plan steps** — request-level state; plan messages stay in General. `_rejectPlanItemThread`
  already throws for plan thread ids, and `currentCoordinationPlan` must keep a home (§4.6).
- **Resolutions** — deleted outright (D27, §3.5). Not excluded, not re-homed: gone.
- **Drafts** (D16) — a thread that does not exist yet. Rows, not destinations.

### 3.4 The `general` sentinel boundary (D18, amended)

rev 1 said `general` maps to `NULL` "in the repository layer". That is wrong and would have shipped a
broken General. Every room use case branches **before** SQL:

```dart
final tid = threadItemId?.trim();
final inThread = tid != null && tid.isNotEmpty;   // beacon_room_case.dart:185, 342, 577
```

So `"general"` would take the item-thread branch, hit `_canAccessThread` → `getById("general")` →
`null` → deny. On the client, `RoomCubit` gates item-sync, `observeReadThrough`, fact cards, plan,
room state, and the session watermark on `threadItemId == null`.

**The rule:**

| Layer | Representation |
|---|---|
| Route / URL | `thread=general` |
| Threads-list API (`beaconThreads`, `markThreadSeen`) | `threadId: "general"` |
| **Translation point** | the GraphQL resolver / use-case entry for those two operations only |
| Every existing room API (`listMessages`, `sendMessage`, seen, fact cards, …) | `threadItemId: null` |
| `RoomCubit` for General | `RoomCubit(beaconId: id, threadItemId: null)` |
| SQL | `thread_item_id IS NULL` |

`BeaconRoomBody` never receives a thread id at all — it reads the cubit from context.

The sentinel is collision-safe: coordination item ids are `I` followed by 12 hex characters
(`utils/id.dart`), so no real item can ever be named `general`.

---

### 3.5 Removing the resolution feature (D27)

**Why it goes.** A resolution is a second mechanism for a state transition the codebase already
performs directly. `AcceptResolutionCase` (`accept_resolution_case.dart:30–90`) does exactly three
things: set the **parent** item to `resolved` if it was open or accepted, set the resolution itself to
`resolved`, and notify the resolution's creator. `resolveAskCase` / `resolvePromiseCase` /
`resolveBlockerCase` already produce the same terminal state in one step.

The only thing the resolution layer adds is a **handshake**: a party who cannot resolve an item
directly proposes an outcome, and a counterpart approves it. That is a negotiation protocol wrapped
around a status flip — the over-engineering. Direct `resolve*` is enough.

**What this simplifies in *this* change** — the removal is not a tax on the Threads work, it is a
discount:

- **Q11 is closed by deletion, not by a guess.** The open question of whether resolution threads hold
  message history stops mattering; both the threads and the items are deleted.
- D15's exclusion rule, the focus-remap rule, and the "resolution conversations need a home" problem
  all evaporate.
- `involvesUserAsSourceOrTarget`'s resolution branch, its `resolutionParent` parameter, and the
  `lookupItems` / `byId` map that exists only to feed it are deleted outright rather than left as
  dead code (§11.4).
- **D26 dissolves.** `fetchPendingResolutionForItem` is deleted, so `ThreadDetail` needs no
  detail-time fetch and the fat-row contract (D9) genuinely is one round-trip.
- `enableComposer: pendingResolution == null` becomes unconditional — the composer is never disabled
  by a pending proposal.

**What it costs, and this is outside the Request screen.** `CoordinationResponsibility` counts
resolutions as the **"reviews"** segment of My Work's YOU line — `reviewOpen`, `reviewNew`, their
contribution to `totalOpen` / `totalNew`, and the fixed display order "asks, promises, blockers,
reviews" (`coordination_responsibility.dart:32–72`), fed by two `ci.kind = 4` FILTER blocks in
`responsibilityCountsByBeaconIds`. Removing resolutions removes that segment. **This is a visible
product change in My Work, not a refactor**, and it is the one part of D27 that deserves an explicit
owner sign-off rather than being folded in silently.

**Data.** `coordination_item.kind` is a persisted int, so dropping the enum case makes
`CoordinationItemKind.fromInt(4)` throw on any surviving row. With zero users this is only a
dev/seed-database concern, but it is a crash rather than a degradation, so the removal carries the
one migration this whole change needs: delete `coordination_item` rows with `kind = 4`. Their
messages cascade via `beacon_room_message.thread_item_id … ON DELETE CASCADE`.

**Do not delete by string match.** Three unrelated things match a naive search and must survive:

- `l10n.notificationCatUnblocksMe` renders the text **"Resolutions"** but is the notification
  category for *unblocks*.
- `CoordinationItemStatus.superseded` (status 4) and `CoordinationItemEventKind.superseded` (6) are
  generic statuses, not resolution machinery.
- **`BeaconStatus.reviewOpen` is a beacon lifecycle status, not the responsibility counter.** It is
  used at `beacon_cubit.dart:76`, `beacon_lifecycle_ui.dart:11, 25`, and `my_work_case.dart:136–142`.
  A search-and-delete on `reviewOpen` breaks the beacon lifecycle. Only
  `CoordinationResponsibility.reviewOpen` goes.

### 3.6 The YOU-line "reviews" segment (Q13, confirmed)

D27's one visible consequence outside the Request screen. **Confirmed by the owner: the segment is
removed with no replacement counter.**

`CoordinationResponsibility` (`coordination_responsibility.dart`) loses `reviewOpen` / `reviewNew`,
their terms in `hasAny` and `totalNew`, the `if (reviewOpen > 0)` block in `orderedEntries` (which is
also this file's only reference to `CoordinationItemKind.resolution`, so it must go with the enum
value), and `reviewNew: 0` in `withNewCountsCleared`. The wire fields go too: server
`custom_types.dart:979` and the two `ci.kind = 4` FILTER blocks that compute them, plus client
`coordination_responsibility_batch.graphql:10–11` and `coordination_responsibility_model.dart:19–20`.

**No new empty state is introduced.** Every segment in `orderedEntries` is already conditional on its
own `open > 0`, and `hasAny` already gates whether the YOU line renders at all. A viewer whose only
responsibility was reviews correctly gets no YOU line rather than an empty one — the existing gate
covers it, so no additional empty-state handling is needed.

**`beacon_you_presentation.dart` is *not* change-free — an earlier revision said it was, and that was
wrong.** Line 192 does merely consume `orderedEntries`, but the same file uses
`CoordinationItemKind.resolution` in four other places, and two of them are **a different product
concept**:

```dart
// :269 and :280 — help-offer REVIEW chips, not coordination resolutions
BeaconYouOfferReviewSegmentKind.authorReview =>
  BeaconYouSegmentPresentation(icon: coordinationKindIcon(CoordinationItemKind.resolution), …)
// :321  CoordinationItemKind.resolution => TenturaTone.info,
// :337  CoordinationItemKind.resolution => l10n.beaconYouReviewCount(count),
```

The enum value is being borrowed purely as a *glyph and tone* for the author's "unreviewed help
offers" segment. Deleting the enum breaks compile at all four sites — but deleting the **segments**
would strip the help-offer review chips, which D27 does not authorize.

**Rule:** keep `BeaconYouOfferReviewSegmentKind.authorReview` and `.helperAwaitingAuthor` and their
counts; repoint their `icon:` and tone to a non-resolution glyph; drop only the
`CoordinationItemKind.resolution` switch arms and `beaconYouReviewCount` if it becomes unused.

The entity test `coordination_responsibility_test.dart` asserts "ask → promise → blocker → review"
and must be reduced to three kinds.

## 4. Server contract

### 4.1 The query

```graphql
beaconThreads(beaconId: String!): [BeaconThreadRow!]!
```

**Baseline correction.** rev 1 claimed this replaces "four reads". It does not. `ItemsTabCubit.fetch`
makes **two** calls — `listByBeacon` (which already returns drafts, server-filtered to
`published = true OR creator_id = viewer`) and `fetchCurrentRootPlan`. The honest gain is: one call
instead of two, plus folding in General's row, which today arrives via a separate room-unread
snapshot. `currentCoordinationPlan` needs an explicit new home (§4.6).

```
type BeaconThreadRow {
  threadId:      String!    # "general" | coordination item id
  threadKind:    String!    # "general" | "ask" | "promise" | "blocker"

  unreadCount:   Int!
  messageCount:  Int!
  lastMessageAt:        String?
  lastMessageAuthorId:  String?
  lastMessagePreview:   ThreadMessagePreview?   # §4.3

  item: CoordinationItemRow                     # null ⇔ General
}
```

`item` reuses `gqlTypeCoordinationItemRow` **verbatim** so `CoordinationItemModel`'s mapper is reused
and no field can drift. If an implementation defines a second item type, it has gone wrong.

rev 2 flagged that `CoordinationItemRow` carries no pending-resolution field
(`custom_types.dart:936–966`) and therefore required a detail-time fetch. **D27 removes the need**:
there is no pending resolution, `fetchPendingResolutionForItem` is deleted, and this query is the
whole contract for both list and detail.

### 4.2 Row inclusion

| Row | Included when |
|---|---|
| General | exactly once, **for room members only** (§4.4) |
| Published ask/promise/blocker | room members: all, active and closed. Non-members: only items they are creator/target/accepter of |
| Drafts | `published = false AND creator_id = <viewer>` |
| Plan / plan step | never |
| Resolution | n/a — the kind no longer exists (D27) |

### 4.3 Last-message preview (D19)

rev 1 proposed `lastMessageIsSystem` + `semanticMarker` + `authorId` and asserted the client could
render "exactly as" in-room system rows do. It cannot:

- Participant-join rows need `joinedUserId` and `admissionReason` from the payload
  (`room_message_tile.dart:154–174`).
- Coordination lifecycle rows deliberately have **`semanticMarker == null`** and instead need
  `linkedItemId`, `linkedEventKind`, item kind and title (`room_message_tile.dart:197–229`).
- rev 1 cited `beacon_room_fact_messages.dart` as a system-row renderer; it is snackbar copy.

So the preview is a **single object with an explicit `kind` discriminator and nullable payload
fields** — never a GraphQL union:

```
type ThreadMessagePreview {
  kind: Int!                      # discriminator, see table below
  excerpt: String?                # body only, server-truncated (§16-Q4)
  hasAttachment: Boolean!
  joinedUserId: String?           # kind = join
  admissionReason: String?        # kind = join — a String, not an Int
  linkedItemId: String?           # kind = coordination
  linkedEventKind: Int?
  itemKind: Int?
  itemTitle: String?
  pollTitle: String?              # kind = poll
  factTitle: String?              # kind = factPinned
}
```

**A union is not an option here.** `graphql_server2` 6.5.0 (pinned in `pubspec.lock`) resolves union
members **structurally**: it validates the result map against every possible type and requires
*exactly one* to match (`graphql_server2.dart:898–928`), while `GraphQLObjectType.validate` rejects
any undeclared key (`object_type.dart:111–117`). That breaks a union two ways — an emitted
`__typename` matches no member, and overlapping shapes such as `Text { excerpt: String! }` versus
`Attachment { excerpt: String? }` match *two*. Either failure throws before Ferry sees the response.
A single object with a `kind` int sidesteps both.

**The discriminator must cover every persisted family.** `BeaconRoomSemanticMarker`
(`beacon_room_consts.dart:11–38`) has **nine** values, not the handful an earlier draft assumed:

| `semantic_marker` | Family | Preview `kind` |
|---|---|---|
| — (null, non-empty body) | ordinary message | `text` |
| — (null, attachment only) | attachment | `attachment` |
| 1 | `updatePlan` | `planUpdated` |
| 2 / 3 | `pinFactPublic` / `pinFactPrivate` | `factPinned` (visibility carried separately) |
| 4 | `participantStatusChanged` | `participantStatus` |
| 5 | `blocker` | `coordination` |
| 6 | `needInfo` | `needInfo` |
| 7 | `done` | `done` |
| 8 | `poll` | `poll` |
| 9 | `participantJoined` | `join` |
| null **+** `linkedItemId`/`linkedEventKind` | coordination lifecycle | `coordination` |

Note the last row: coordination lifecycle rows deliberately carry `semanticMarker == null` and are
identified by `linkedItemId` + `linkedEventKind` instead (`room_message_tile.dart:197–229`). A
mapper switching only on `semanticMarker` will mis-file them as plain text.

**The `kind` codes are fixed here, once, and mirrored verbatim on the client.** Leaving them unassigned
invites two implementers to invent different numbers and a client switch that silently never matches.
They deliberately do **not** reuse `BeaconRoomSemanticMarker` values, because three families
(`text`, `attachment`, `coordinationLifecycle`) have no marker at all:

```
ThreadMessagePreviewKind:
  0  text                  (marker null, non-empty body)
  1  attachment            (marker null, empty body, has attachment)
  2  planUpdated           (marker 1)
  3  factPinned            (markers 2 and 3; visibility in a separate field)
  4  participantStatus     (marker 4)
  5  coordination          (marker 5, OR marker null + linkedItemId/linkedEventKind)
  6  needInfo              (marker 6)
  7  done                  (marker 7)
  8  poll                  (marker 8)
  9  join                  (marker 9)
```

A family with no mapping is a build error, not a blank line. The client localizes each `kind`.
`systemPayload` must never be serialized into `excerpt` — it carries routing and actor internals;
only the named display-safe fields above cross the boundary.

### 4.4 Authorization — the union rule (D21 overturned)

Five predicates exist and they are not equivalent:

| Predicate | Definition |
|---|---|
| `ensureCanCoordinateOnBeacon` | author ∨ steward ∨ `roomAccess == admitted`; throws |
| `_canUseRoom` (`beacon_room_case.dart:79`) | identical three checks; returns bool |
| `_canAccessThread` (`:107`) | `_canUseRoom` **∨** `creatorId == u ∨ targetPersonId == u ∨ acceptedById == u` |
| client `canNavigateBeaconRoom` (`beacon_view_state.dart:345`) | `isBeaconMine ∨ isSteward ∨ (isHelpOffered ∧ hasRoomAdmission)` — **omits** plain admitted participant |
| client `canCoordinateInBeaconRoom` (`:331`) | adds a **beacon-status gate** the server has not |

`_canAccessThread` is **strictly broader**: a non-admitted user can read and post in an item thread
they are creator/target/accepter of. The state is reachable (admission revoked after creation;
`redirect_ask_case` retargeting). Gating the list on `ensureCanCoordinateOnBeacon` would revoke that,
and under D7/D17 it would be total loss of access, not degradation.

```
roomMember := _canUseRoom(beaconId, viewer)

if roomMember:  rows = [General] + all published items + viewer's drafts
else:           rows = published items where _isItemParticipant(item, viewer)   # no General
                if rows is empty: throw (same exception as today)
```

Three consequences:

1. **General is not unconditionally present.** §4.2's "exactly once" holds *for room members*. This
   is the one place the "General is just another thread" abstraction leaks, and it leaks correctly:
   General *is* the room, so seeing it is exactly room membership.
2. **§8.2's default relaxes** to "the first row of the list" — General for room members, the viewer's
   own item thread otherwise.
3. **§9.4's fallback must not bounce to General** when General is inaccessible; it falls back to the
   first accessible row, and to the admission placeholder if there is none. "Never a dead end" must
   not become "always a dead end for item-only viewers".

Posting rights are unchanged and still enforced at send time by `_canMutateMessage` (`:135`). The
list is not a grant to post.

### 4.5 Query shape (D25)

**Do not drive from a message-grouped CTE.** rev 1's sketch would have dropped every item with no
messages and every draft — contradicting D4. The row universe is item-driven:

```
General row  UNION ALL  eligible coordination_item rows
   LEFT JOIN message aggregates (count, max(created_at))
   LEFT JOIN last-message row (DISTINCT ON / lateral)
   LEFT JOIN beacon_room_seen for this viewer
```

**Unread must not be reinvented.** Two existing predicates must be reused, not paraphrased. (rev 1
cited lines 879–896, which merely copy `lastSeenAt` into Dart — an implementer following that would
have written the watermark clause and nothing else.)

Per-item unread is the SQL subquery at `coordination_item_repository.dart:854–859`, and it has
**three** clauses, all load-bearing:

1. `m.created_at > s.last_seen_at` (or no seen row) — the watermark;
2. `m.author_id <> $2` — **the viewer's own messages are not unread**;
3. `ci.kind <> $3` — plan items excluded.

General unread is a *different* function: `countRoomMessagesAfter` with `thread_item_id IS NULL`
(`beacon_room_repository.dart:1519–1554`).

The subtlety that will bite: clause 3 has **no General analogue**. General *is* where plan messages
live (§3.3), so General's count must **include** exactly what the per-item predicate excludes.
Copying the per-item fragment wholesale onto the General row would silently under-count it. Share
clauses 1 and 2; do not share clause 3.

If General's count here diverges from `countRoomMessagesAfter`, the Threads list and Inbox/My Work
will disagree about the same number.

**Ordering (D20).** Server returns General first, then
`COALESCE(last_message_at, item.updated_at) DESC, threadId ASC`. The client owns folds and grouping.

**Indexes.** See §2. Measure before adding a third.

### 4.6 Loose ends this query does not cover

- **`currentCoordinationPlan` — drop it, do not carry it forward.** `ItemsTabCubit.fetch` calls
  `fetchCurrentRootPlan` and stores it on `ItemsTabState`, but a repo-wide search for
  `.currentCoordinationPlan` returns **zero readers**: nothing renders it. `RoomCubit` already loads
  its own plan independently (`room_cubit.dart:487-542`) for the General surface. So `ThreadsCubit`
  should **not** make that second call — carrying it would preserve a dead round-trip on every
  refetch. This closes Q12 by deletion rather than by choosing a home.
(The pending-resolution loose end that stood here is gone: D27 deletes the feature, so this query is
the whole contract for both list and detail.)

---

## 5. Read-state model

### 5.1 Already unified

`beacon_room_seen` is already the single per-thread watermark store, and the existing write already
uses the correct dual partial-index conflict targets. Most of what D11 asks for shipped in m0072.

### 5.2 There are two General mark-seen paths, not one

rev 1 said the change is a rename of `MarkBeaconRoomSeen`. In fact **General does not call it**:

```dart
// beacon_room_repository.dart:425
if (threadItemId == null) {   … GBeaconParticipantRoomSeenReq …  }
else                      {   … GMarkBeaconRoomSeenReq       …  }
```

`BeaconParticipantRoomSeen` is a distinct GraphQL field that server-side aliases to
`markBeaconRoomSeen` with no thread id. `markThreadSeen` absorbs **both**, and
`BeaconParticipantRoomSeen` joins the deletion list (§13).

### 5.3 The General/thread asymmetry that must survive

`BeaconRoomCase.markBeaconRoomSeen:571` differs by branch in three ways:

| | General (`threadItemId == null`) | Semantic thread |
|---|---|---|
| **Authorization** | `_canUseRoom` → `'Room access required'` | `_rejectPlanItemThread` then `_canAccessThread` → `'Room or item thread access required'` |
| **Clamp** | `at` is forced **equal** to `latestMainRoomMessageCreatedAt` whenever one exists — both branches assign `at = latest`, so the caller's `readThroughAt` is discarded | none |
| **Case-layer floor** | floored at the existing watermark via `getMainRoomLastSeen` | none |
| **Storage monotonicity** | `GREATEST(existing, new)` | **`GREATEST(existing, new)` — identical**; storage can never regress for either |

A naive merge either drops General's clamp and case-layer floor (unread flickers back) or stamps
threads with an unrelated room message's timestamp. Keep the branch; share only the signature.

**Correction to rev 2–3 of this document:** they claimed a semantic thread's watermark "can move
backwards". That is **false at the storage layer** — both upsert branches use
`GREATEST(beacon_room_seen.last_seen_at, EXCLUDED.last_seen_at)`
(`beacon_room_repository.dart:1110–1127`), so neither General nor a thread can regress in the
database. The asymmetry above is real but lives entirely in the *case* layer.

**The real defect is that the mutation response can lie.** `markBeaconRoomSeen` returns the
**submitted** `at`, not the value the upsert actually persisted (`beacon_room_case.dart:621–630`).
When a stale or out-of-order `readThroughAt` arrives, `GREATEST` correctly keeps the newer stored
value while the response reports the older submitted one — and the client feeds exactly that value
into `RoomReadWatermarkStore.confirmSynced`, desynchronising local suppression from server truth.
Fix with `RETURNING last_seen_at` propagated through the mutation. See §16-Q9.

### 5.4 The local watermark store is beacon-keyed and already leaks

`RoomReadWatermarkStore` is explicitly per-beacon **main-room** state
(`_readThroughByBeacon`, `_syncedByBeacon`). But `BeaconRoomCase` calls
`_watermark.confirmSynced(beaconId, persistedAt)` after **every** successful mark-seen — including
item threads (`beacon_room_case.dart:341–353`), with `RoomCubit` supplying its thread id. So seeing
an item thread already advances the watermark used to reconcile **General** unread in Inbox and
My Work.

rev 1 listed this store as "unchanged", which cannot implement D11 or D12. Either:

- key it `(beaconId, threadId)`, or
- keep it General-only and call `confirmSynced` **only** when `threadItemId == null`.

Any optimistic per-row unread suppression (§6) needs the thread-keyed version.

**Keying the store is necessary but not sufficient.** The only place a *pending* local read-through
is recorded today is gated to General:

```dart
// room_cubit.dart:405-416
if (state.threadItemId == null) {
  _case.observeReadThrough(state.beaconId, latest);
}
```

A semantic thread therefore has **no** optimistic watermark at all — its store entry appears only
after the network mutation resolves, via `confirmSynced`. Passing a `threadId` into the store without
removing this guard leaves the just-left-thread flicker (§6) exactly as it is: a refetch landing
between close and mark-seen still resurrects that row's count. The guard must go, so read-through is
observed for General *and* semantic threads before the mutation is awaited.

### 5.5 `beacon_items_seen` is retained (D11 amended)

rev 1 called it dead on the strength of a Dart-symbol grep. The table is read in **raw SQL**:

```sql
LEFT JOIN beacon_items_seen bis ON bis.user_id = $1 AND bis.beacon_id = ci.beacon_id
…  COALESCE(ci.published_at, ci.created_at) > COALESCE(bis.last_seen_at, '-infinity')  … AS ask_new
```

(`coordination_item_repository.dart:1278–1312`), producing `askNew`/`promiseNew`/`blockerNew`/
`reviewNew` for My Work's YOU line; `BeaconViewCubit._markYouResponsibilitySeen` writes it on every
YOU-line refresh.

It is **not** a thread read watermark — it is a per-beacon *responsibility digest* watermark
answering "which of my obligations are new since I last looked at this request". Unifying it into
per-thread read state would destroy that distinction. It stays, `markBeaconItemsSeen` stays, and
dropping it is explicitly **out of scope**.

### 5.6 Badge derivation (D12)

```
threadsTabBadge = resolveUnread(General) + Σ row.unreadCount   over active semantic rows
```

**The General term is not a raw server count.** Today's app-bar badge passes through
`RoomReadWatermarkStore.resolveUnread(beaconId:, serverCount:, serverSeenAt:)`, which returns `0`
whenever the local read-through is ahead of the confirmed server watermark
(`room_read_watermark_store.dart:80–93`). That store exists precisely because mark-seen is a
round-trip. A badge summed straight from server counts reintroduces the flicker it was built to
kill: between "user reads General to the bottom" and "mutation lands + refetch returns", every
invalidation-driven refetch resurrects the count.

So the badge must resolve General's server count through the store before summing, and — once the
store is thread-keyed (§5.4) — each semantic row must do the same. The exit flush in §8.4 must feed
`confirmSynced` so a *just-closed* thread does not regress while its refetch is in flight.

**Which rows.** `ItemCard`'s badge is gated `unreadCount > 0 && item.isActive && kind != plan`, and
today's tab badge counts `openItems` only. Closed-thread unread exists in storage but is surfaced
nowhere. D12 must pick one and the row must agree with the tab, or the tab can read `3` with no row
badged:

> **Decision:** the badge counts **General + active threads**, matching today's card gating. Closed
> threads keep their stored unread but display it only inside the Closed fold once expanded.

**Delete the consumer, not the source.** The app-bar badge is fed by
`BeaconRoomCase.fetchRoomUnreadSnapshot` → `_hints.fetchByBeaconIds`, i.e. the **inbox room-context
hints batch** (`inbox_room_context_batch.graphql`, field `roomUnreadCount`). That same batch also
feeds Inbox tiles (`inbox_cubit.dart:181`) and My Work (`my_work_case.dart:278–281`). It is *not*
`getBeaconRoomState` / the `BeaconRoomState` cue, which is a different read.

Only the beacon-view **consumers** — `BeaconViewState.roomUnreadCount` and
`_effectiveRoomUnreadCount` — are deleted. The hints batch and its `roomUnreadCount` field stay;
removing them would break Inbox and My Work unread badges.

### 5.7 The upsert hazard

`beacon_room_seen` has no PK, so the upsert has **two conflict targets**:

```sql
-- General
ON CONFLICT (user_id, beacon_id) WHERE thread_item_id IS NULL DO UPDATE …
-- semantic
ON CONFLICT (user_id, beacon_id, thread_item_id) WHERE thread_item_id IS NOT NULL DO UPDATE …
```

Postgres requires the inference predicate to match a partial index; a "unified" statement without the
`WHERE`, or naming a non-existent PK, fails at runtime with a green build. Adding a real PK with a
sentinel `''` is not an escape — the FK to `coordination_item(id)` would reject it. The existing write
is already correct; carry it over verbatim.

---

## 6. Liveness (D10)

Keep `ItemsTabCubit`'s existing pattern — subscribe to `BeaconRoomCase.beaconRoomInvalidations`,
filter to this beacon — with three corrections.

**Entity set.** Add `roomSeen` (today's filter omits it, which is why the Elements badge cannot react
to a seen write from another device). Keep `roomMessage`, `coordinationItem`, `participant`,
`factCard`.

**Concurrency, not just debounce.** rev 1 proposed a 300 ms trailing debounce. That is not a
concurrency policy: the existing listener fires `unawaited(fetch(silent: true))`, mutations and
composer callbacks call `fetch()` independently, and each fetch emits unconditionally. An older
response can land last and restore an obsolete status, ordering, or draft row. `ThreadsCubit` needs
**latest-wins**: a monotonic generation stamped per fetch, with stale results discarded — plus
coalescing so a burst collapses. Debounce on top is an optimization, not the mechanism.

**Do not debounce `roomSeen` like `roomMessage`.** A seen write is the signal that clears a badge;
delaying it by the same window is what makes the badge visibly flicker.

**Unread reconciliation — rev 1's rule was wrong.** rev 1 said the open thread should always display
zero unread. But `RoomCubit` clears unread only when the user reaches the bottom
(`markReadToBottom`, `room_cubit.dart:405`), and the body keeps a live unread divider. Forcing zero
would hide genuine unread from a user reading history, or sitting on People/Log with the split open,
or receiving messages above the divider — replacing a stale-server race with false zeroes. And it
does not even cover the real race, which is the thread you **just left**: after a switch the previous
thread is no longer "open", so the rule would not apply to it at all.

The correct shape:

- Reconcile the selected row from the live `RoomCubit.unreadCount` and its read-through state, not
  from a blanket override.
- Suppress only counts covered by an **optimistic, thread-keyed local watermark** (§5.4) — which is
  exactly what covers the just-left thread until its mark-seen round-trips.
- Combined with D23's awaited close, the window in which a stale count can show closes.

---

## 7. Client module layout (D14)

```
features/beacon_threads/                        ← renamed from features/beacon_room
  domain/
    entity/beacon_room_invalidation.dart        (unchanged)
    entity/request_thread.dart                  NEW
    room_read_watermark_store.dart              CHANGED — thread-keyed (§5.4)
    use_case/beacon_threads_case.dart           ← beacon_room_case.dart, + listThreads
  data/
    repository/beacon_threads_repository.dart   ← beacon_room_repository.dart
    gql/beacon_threads_list.graphql             NEW
  ui/
    bloc/threads_cubit.dart                     ← beacon_view/ui/bloc/items_tab_cubit.dart
    bloc/threads_state.dart                     ← items_tab_state.dart
    bloc/room_cubit.dart                        (unchanged — still the conversation cubit)
    thread_host.dart                            NEW — §8
    widget/threads_list.dart                    ← beacon_view/ui/widget/items_tab.dart
    widget/item_card.dart                       ← coordination_item/…/item_card.dart, evolved (§11.1)
    widget/thread_detail.dart                   ← coordination_item/.../item_discussion_pane.dart
    widget/beacon_room_body.dart                (unchanged — the shared conversation body)
```

`features/coordination_item` keeps lifecycle (`ItemActionsCubit`, `CoordinationItemCase`, composer
and edit sheets, overflow menu, all mutations); it loses `item_discussion_screen.dart` and
`item_discussion_pane.dart`. `features/beacon_view` keeps header/HUD, pinned facts, People, Log,
status sheets, forward; it loses the items tab, room surface, chat app-bar button, and the
room/thread state machine. `ui/widget/coordination_item_presenter.dart` and
`coordination_item_card_chrome.dart` stay shared — My Work uses them.

**The rename is mechanical and separable (D22).** Counting method matters here, since two reviewers
produced different figures: `grep -rl 'features/beacon_room' --include='*.dart'` returns **52** files
under `packages/client/lib` and **46** under `packages/client/test` (98 total); the directory
`test/features/beacon_room` holds **31 `.dart` files** (37 including golden fixtures). Land the move —
path change plus import rewrite, zero logic edits, tests green — as its own change.

### 7.1 Layer discipline

`RequestThread` is a Freezed domain entity composing the existing `CoordinationItem`, with
`item == null` as the General discriminator. The repository returns it, never the generated Ferry
row. `ThreadsCubit` still needs `BeaconThreadsCase` for the invalidation stream, and lifecycle
actions still route through `CoordinationItemCase`, so the multi-repo `*Case` injection the
`cubit_requires_use_case_for_multi_repos` lint requires is satisfied as today.

---

## 8. The thread host

### 8.1 State

```
ThreadHostState { ThreadId? openThreadId }
```

Everything the current screen tracks separately is derived: `_embeddedRoomOpen`, `_activeThreadItem`,
`beaconViewRoomRequestedByRoute`, `beaconViewShowsLegacyRoomSurface`,
`canNestItemDiscussionInRoomPane` (deleted — there is no nesting, only selection),
`_splitRoomRouteSyncScheduled`, `_splitRoomRouteFocusPostFrameScheduled`, `_splitRoomRouteFocusKey`.

### 8.2 The invariant that removes the reconciliation code

> **On `expanded`, `openThreadId` is never null; it defaults to the first row of the list** — General
> for room members, the viewer's own item thread otherwise (§4.4).

The current post-frame `_syncActiveThreadHost` and `_scheduleExpandedRoomRouteSync` exist because the
split's right pane could show something the URL did not describe, and a resize could invalidate a
nesting decision after layout. With this invariant, **within a window class** there is nothing to
reconcile: the same `openThreadId` renders as a right pane or as a route.

**Crossing a window class is not free, and D24 makes it a navigation action.** Because compact detail
is a real pushed page (§8.3), a resize is delivered to *both* pages on the stack, and the transition
is a push or pop triggered by layout — exactly the flavour of problem the deleted machinery handled.
The current code's own comment explains why it is hard: state cannot live on the `State` object,
because "the *new* State created for the pushed room page starts with its own, unset copy of any such
flag" (`beacon_view_screen.dart:349–356`). So the contract must be explicit:

| Transition | Contract |
|---|---|
| expanded → compact, thread open | The **host** (not a `LayoutBuilder`) observes the class change and pushes the detail for the already-selected `openThreadId`. A layout callback must never navigate. |
| compact → expanded, sitting on a pushed detail | The pushed page **pops itself**, and the base page renders the split with that thread selected. Leaving it stacked would show the same thread in two panes; converting it in place would duplicate the page. |
| Either direction, no thread open | Pure re-layout. |

`openThreadId` must therefore live above both pages. **"Alongside `BeaconViewCubit`" is not above
them** — `BeaconViewCubit` is created inside `BeaconViewScreen.wrappedRoute`
(`beacon_view_screen.dart:194-207`), so a sibling `AutoRoute` page cannot `context.read` it. A real
shared ancestor is required, and there are two workable shapes:

1. **Nested child route** — `ThreadDetailRoute` registered as a *child* of the beacon-view route, so
   both share one `wrappedRoute` scope and one provider. Preferred; it also keeps the URL nested.
2. **Beacon-scoped registry** — a `GetIt`/`InheritedWidget` entry keyed by `beaconId`, resolved by
   both pages independently, disposed when the last leaves.

Whichever is chosen, this is the single hardest part of the change; any plan that budgets "the state
machine collapses to one nullable field" has under-sized it.

**D13 and D24 must be reconciled, not both implemented.** D13 fixes the canonical URL as
`/beacon/view/:id?tab=threads&thread=…`; D24 requires the compact detail to be a *real route* rather
than the same route with a different query param. Those are compatible only if the detail is a
**distinct page class** whose path is a child of the beacon view, e.g.:

```
/beacon/view/:id?tab=threads                 → list (base page)
/beacon/view/:id/thread/:threadId            → ThreadDetailRoute (distinct page, nested child)
```

The `?thread=` query form then survives only as the **expanded split's** selection, where there is no
second page. A third URL shape invented in the implementation (`…/thread?tab=threads&thread=…`) is
neither, and a cold load at a detail URL with no base page beneath it has nowhere for the
compact→expanded "pop self, base shows split" contract to land — the nested-child form fixes that by
construction, since the parent is always instantiated. **§9.1 is updated accordingly.**

### 8.3 Routed detail (D24) — the hazards do not vanish

rev 1 claimed a pushed detail makes back "an ordinary pop". That is exactly what the current Room
does — `pushPath('?tab=room')`, another Beacon View URL distinguished by a query param — and its
exit provably cannot use `back()` or `maybePop()`:

- `back()` on web is `window.history.back()`, an async popstate round-trip observed to rewrite the
  top page in place, leaving a duplicate `BeaconViewRoute`.
- `maybePop()` consults the very `PopScope.canPop` that routed the gesture here, so it refuses.
- Cold deep links need a **branch-relative** `replacePath` because an absolute leading-slash path
  does not match the tab branch's own registration.

Specifying the detail as "the same route with a different query param" therefore inherits every one
of those hazards. **D24 requires a real `ThreadDetailRoute`** — its own page, its own root and
branch registrations — so that an ordinary pop genuinely works and `PopScope` need not encode
surface modes. If a reviewer prefers the query-param shape, then the existing stack-provenance
(`_hasOperationalBeaconPageBeneath`), forced `pop()`, branch-relative replace, and reentrancy guard
must all be carried over under thread terminology rather than deleted. Pick one; rev 1 tried to have
both.

### 8.4 Cubit lifetime (D23)

rev 1 named `itemDiscussionProviders` as the model while also requiring "the previous thread's
mark-seen completes before the next thread's unread is read back". These are incompatible:

- `RoomCubit` subscribes and calls `load()` **from its constructor** (`room_cubit.dart:59–69`).
- `RoomCubit.close()` flushes mark-seen **asynchronously** (`:1082–1090`).
- `BlocProvider.dispose` calls `close()` and **does not await** the returned `Future`.

So a keyed provider swap starts the incoming reads before the outgoing watermark persists. The screen
already has the correct mechanism and it is not a provider:

```dart
Future<void> _releaseEmbeddedRoomCubit() async {
  final c = _roomCubit; if (c == null) return;
  _roomCubit = null;
  if (!c.isClosed) await c.close();      // close() awaits markSeenNowIfNeeded()
}
```

**The host owns cubit lifetime and serializes switching:** mark the selection pending, `await
oldCubit.close()`, then construct and expose the new cubit. One `RoomCubit` per *open* thread, keyed
by `openThreadId`, never one per row.

### 8.5 The embedded host

Four of the seven embedded parameters are dead or constant. Two call sites exist:

| Call site | Passes |
|---|---|
| `my_work_beacon_view_pane.dart:48` (sole caller `my_work_screen.dart:512`) | `embedded`, `embeddedAllowRoomSplit: true`, `embeddedRoomCoVisible: true` (hardcoded), `entry`, `viewTab`, `peopleTabAttention`, `onEmbeddedLeave` |
| `inbox_beacon_view_pane.dart:37` | `embedded: true` only |

`suppressEmbeddedRoomBack`, `embeddedRoomCloseNonce`, and `onEmbeddedRoomOpenChanged` are declared and
forwarded but **never passed** — they sit at `false`/`0`/`null` in production. My Work's list is
already replaced by `_MyWorkExpandedPreview` on selection, so the collapse protocol those fields
imply is not wired. **Delete all three**, plus `_notifyEmbeddedRoomOpen` and the nonce handling. The
tight `minPaneWidth: 280` variant applies only when `embedded && allowSplit && !coVisible` — no live
caller — so it is unused today.

**The unresolved seam is navigation, not collapse.** `embedded` explicitly *skips route URL
lifecycle*, and My Work compact does not embed the pane at all (`if (!useExpandedPane)` returns the
list). But D3/D24 require compact/regular detail to be a pushed route with its own URL. So:

> **Embedded contract:** above the split threshold the pane splits and selection is pane-local, with
> the canonical `thread=` synced to the route. Below it, the embedded pane does **not** stack a
> pane-local detail — it asks the host to push the canonical thread URL. `MyWorkBeaconViewPane` grows
> one callback for that (`onRequestThreadRoute`), replacing the three being deleted.

Note also that the current split predicate keys off `context.windowClass` **first**, then pane width,
so a wide pane in a non-expanded window will not split. §10.4 resolves this.

---

## 9. Routing (D13)

### 9.1 Scheme

```
/beacon/view/:id?tab=threads                       → list (compact) / list+split (expanded)
/beacon/view/:id?tab=threads&thread=general        → expanded: which pane is selected
/beacon/view/:id/thread/general                    → compact/regular: the pushed detail page
/beacon/view/:id/thread/<itemId>?message=<msgId>
/beacon/view/:id?tab=people | log
```

`?thread=` expresses **selection within one page** (the expanded split). `/thread/<id>` is a
**distinct nested page** (compact/regular detail, D24). They are two representations of the same
`openThreadId`, and the host converts between them at the window-class boundary (§8.2) — it never
uses both at once.

`thread` is retained across People/Log so the expanded right pane persists (D6), ignored on compact.

### 9.2 Deleted — no redirects (D7 ∧ D13 reconciled)

rev 1's D7 said `?tab=room` "becomes a redirect" while D13 said it is deleted and the scope line
forbids aliasing. **Resolution: delete, no redirect, and rewrite every producer (§9.3) in the same
change.** With zero users the only thing a redirect protects is our own un-migrated producers, and
those are a finite, enumerated list.

| Deleted | Note |
|---|---|
| `?tab=room`, `?surface=room` (`kQueryBeaconSurface`, `kBeaconSurfaceRoomQueryValue`) | |
| `kQueryCoordinationItemId` | the actual param name is **`item`**, not `coordinationItemId` (`consts.dart:100`) |
| `BeaconViewEntrySource.roomNotification` as a room opener | entry token keeps any analytics role |
| `ItemDiscussionRoute` + registrations | plus every direct producer, §13 |
| `BeaconRoomRoute` / `BeaconRoomScreen` / `kPathBeaconRoom` + its root registration | a legacy stub whose redirect guard targets `viewTab: 'room'`, which no longer exists |
| Legacy tab aliases `details`/`forwards`/`overview`/`helpOffers`/`activity`/`timeline` | |

`kQueryMessageId` (value `message`) survives.

### 9.3 Deep-link producers

Destination mapping is client-side; the server's `dest` vocabulary is unchanged. The real names:

- `domain/attention/destination_map.dart:17–24` — kinds are **`beacon_room`** and
  **`beacon_room_message`** (not `dest == 'room'`), both emitting `kQueryBeaconViewTab: 'room'`.
  `AttentionDestinationKind` has **no** coordination-item destination.
- `app/router/notification_deep_link.dart:14–25` — `dest == 'room'` plus `item=`.

Both must be rewritten to `tab=threads` with the appropriate `thread=`.

**Message links must resolve their own thread.** Today a message target maps to
`?tab=room&message=<id>` — i.e. it *assumes the main room* — so a message living in an item thread is
linked into the wrong surface. No new API is needed: `roomMessageTarget(beaconId, messageId)` already
returns `threadItemId`. Rule: emit `?tab=threads&message=<id>` **without** `thread`; the host
resolves `thread = threadItemId ?? 'general'` once and rewrites the URL to canonical form. An
explicit `thread` in the URL always wins and skips the lookup. This is the one behavior the change
*adds*, and it is a bug fix falling out of the model.

### 9.4 Hydration

A cold load at `?thread=<itemId>` has no item in hand. Today that is `_ItemDiscussionHydrateLoader`'s
`FutureBuilder` over `listByBeacon`. Under D8 the threads list *is* the hydration source: the host
waits for `ThreadsCubit`'s first emission and selects the matching row — one loading state, one error
state, shared with the list.

An unknown or inaccessible `thread` falls back to **the first accessible row**, not unconditionally to
General (§4.4 ¶3), and to the admission placeholder when there is none.

---

## 10. Adaptive layout

Breakpoints: compact `< 600`, regular `600–839`, expanded `≥ 840`.

### 10.1 Compact (< 600) — list, then push

```
┌──────────────────────────────┐      ┌──────────────────────────────┐
│ ← Request title           ⋮  │      │ ← Ask: pick up keys       ⋮  │
├──────────────────────────────┤      ├──────────────────────────────┤
│  header card / HUD           │      │  ┌────────────────────────┐  │
│  pinned facts strip          │      │  │ Ask · open · Ann→Bob   │  │
├──────────────────────────────┤ tap  │  │ due in 2d · [Resolve]  │  │
│ ━Threads━   People    Log    │ ───▶ │  └────────────────────────┘  │
├──────────────────────────────┤      ├──────────────────────────────┤
│ 💬 General              (3)  │      │  Ann: can you grab them?     │
│ 🙏 Ask: pick up keys    ○    │      │  Bob: on it 👍               │
│ 🤝 Commitment: drive    ✓    │      │                              │
│ ⛔ Blocker: no van       !    │      ├──────────────────────────────┤
│ ▸ Closed (4)  ▸ Drafts (1)   │      │ [ message…              ▶ ]  │
└──────────────────────────────┘      └──────────────────────────────┘
```

A real pushed route (D24) with its own app bar: back, thread title, thread overflow. General's detail
carries the request title and no semantic header.

### 10.2 Regular (600–839) — same as compact

Same push model, wider column. No split: `beaconViewRoomSplitPaneWidth` needs ≥ 360 for the thread
pane plus a workable list, which does not fit under 840.

### 10.3 Expanded (≥ 840) — two panes

```
┌─────────────────────────────┬──────────────────────────────────┐
│  header card / HUD          │  Ask: pick up keys            ⋮  │
│ ━Threads━   People    Log   ├──────────────────────────────────┤
│ ▶ 💬 General           (3)  │  ┌────────────────────────────┐  │
│   🙏 Ask: pick up keys  ○   │  │ Ask · open · Ann → Bob     │  │
│   🤝 Commitment: drive  ✓   │  │ due in 2d      [Resolve]   │  │
│   ⛔ Blocker: no van     !   │  └────────────────────────────┘  │
│   ▸ Closed (4)              │  Ann: can you grab them?         │
│   ▸ Drafts (1)              │  Bob: on it 👍                   │
│                             ├──────────────────────────────────┤
│                             │ [ message…                   ▶ ] │
└─────────────────────────────┴──────────────────────────────────┘
       Expanded                        SizedBox(width: paneWidth)
```

- Pane width: keep `beaconViewRoomSplitPaneWidth(tt, availableWidth:, minPaneWidth:)`.
- Separator: `TenturaVerticalHairline`.
- **Co-visibility (D6):** the right pane is a *sibling of the tab bar*, not a tab body — switching to
  People or Log leaves it up. This is current behavior, preserved.
- Split predicate's third term is **"the list has at least one row"**, replacing
  `canNavigateBeaconRoom` (§4.4/§4.6): the server has already decided what the viewer may see.
- Selected row marked with a leading indicator + container tone from `tt`.

### 10.4 Embedded (My Work)

Split when the **pane's** width clears the threshold, not the window's — today the predicate checks
`context.windowClass` first, which is wrong for a pane inside a multi-column screen. Below the
threshold the pane requests a host route push (§8.5), it does not stack a pane-local detail.

### 10.5 Scroll ownership — pick one architecture (§ decision required)

The current tab body is a `Column` inside `SliverToBoxAdapter`, with an explicit comment that a
nested `ListView` caused `parentDataDirty` semantics asserts on web. rev 1 said the list "should
become real slivers" while also keeping the current seam. **Those are mutually exclusive:**
`BeaconOperationalScrollView` wraps `tabBody` in `SliverToBoxAdapter`
(`beacon_operational_scroll_view.dart:346–350`), and a `SliverList` is a `RenderSliver`, not a box
child — placing one there is a render-protocol failure.

Two honest options:

- **(a) Keep the boxed `Column`.** Zero risk, but every active row plus every expanded closed/draft
  row builds eagerly. Acceptable at current per-request item counts.
- **(b) Change the seam.** `BeaconOperationalScrollView` accepts sliver-producing tab content and
  composes it directly into `CustomScrollView.slivers`; the threads list becomes `SliverList` plus
  sliver folds. This touches People and Log too.

**Recommendation: (a) for the first implementation**, with (b) noted as the follow-up. Under no
circumstances a nested `ListView` — that is the one option known to be broken on web.

---

## 11. Thread row (D5)

### 11.1 `ItemCard` is already the request-scoped row — evolve it in place

rev 1 proposed a new `thread_row.dart` on the grounds that `ItemCard` "is used by My Work as well".
It is not: `ItemCard(` is constructed at exactly three sites, all inside `items_tab.dart` (:408,
:590, :655). My Work uses the *shared chrome and presenter* helpers
(`coordination_item_card_chrome.dart`, `coordination_item_presenter.dart`) — which do have wider
consumers (`room_message_tile.dart`, `activity_list.dart`, `beacon_you_presentation.dart`) and stay
shared — but never `ItemCard` itself.

So `ItemCard` moves into `beacon_threads` with the list and grows the General case and the two new
fields, rather than being forked. That removes a whole widget from the plan and guarantees the row
cannot drift from the card it replaces.

**One extraction is required first.** The private helpers `_ItemHeaderTier`,
`_bodyPreviewThreshold`, `_formatStaleRemaining`, and `_formatStaleOverdue` are library-private to
`item_card.dart` and travel with it. But **`_StaleDeadlineTicker` is private to `items_tab.dart`**
(`:688`) — a file §13 deletes. It must be moved out (to `ui/widget/` as public API, or into
`item_card.dart`) *before* that deletion, or the stale/overdue labels silently stop ticking.

### 11.2 Information budget

| Slot | General | Semantic |
|---|---|---|
| Leading | chat glyph | `coordinationKindIcon(kind)` tinted by `coordinationItemColor(tt, kind, status)` |
| Title | `l10n` "General" / «Общее» | item `title`, else `contentPreview` |
| Parties | — | `coordinationItemCardAvatarTrail` creator → target |
| Status | — | kind + status chip, existing `_ItemHeaderTier` emphasis |
| Time pressure | — | stale/overdue label + `_StaleDeadlineTicker` |
| **Last message** | author + localized preview token (§4.3) | same |
| **Timestamp** | `lastMessageAt`, relative | same |
| Unread | count badge | count badge — present today but gated `isActive && kind != plan`; see §5.6 |
| Inline actions | — | resolve/accept/reject/cancel/remind/edit, unchanged, incl. `_ItemCardAnimatedRow` |
| Overflow | — | `coordinationItemCardMenuEntries`, unchanged |

The genuinely **new** information is two fields: last-message preview and its timestamp. Everything
else `ItemCard` already renders. This is a re-layout, not an information redesign.

Density comes from the existing expand behavior — `_expanded`, `_bodyPreviewThreshold`, and the
Show more/less toggle. Collapsed = chat-list reading; expanded = card reading.

### 11.3 Grouping

```
💬 General                              ← always first, never in a fold
── Active (n)  [☖ for me]               ← AccordionExpansionTile, filter preserved
▸ Closed (n)
▸ Drafts (n)                            ← viewer's own only
```

`AccordionExpansionGroup` + `itemsTabAccordionSectionId` already implement single-open folds and
focus-driven auto-expansion; that survives with `focusItemId` and `FocusFlashHighlight`.

### 11.4 The `activeForMeOnly` filter

The filter survives and gets **simpler**, because D27 deletes the only case that made it complicated.

`involvesUserAsSourceOrTarget` currently has two branches: a `resolution` branch doing a one-hop
lookup to the parent item, and a default `directInvolvementAsSourceOrTarget`. With the resolution
kind gone, only the default remains — and with it the `resolutionParent` parameter, the
`lookupItems` argument, and the `byId` map in `filterActiveItemsForUser` that exists solely to feed
the hop. All are deleted, not left as dead code.

Parent rows were never affected by the hop (they are kept by their own direct-involvement check), so
"for me" behavior for Ask/Commitment/Blocker is unchanged.

Log-row focus (`focusItemId` + `FocusFlashHighlight`) needs **one** remap, not none. rev 3 concluded
that with resolutions gone "every coordination event id is an Ask/Commitment/Blocker id" — that is
wrong: **`plan` is still a live kind**, the activity presenter renders plan lifecycle events
(`beacon_activity_event_presenter.dart:109–133`), and the repository writes `coordinationItemId` for
every created kind (`coordination_item_repository.dart:75–97`). But plan rows are deliberately
excluded from the Threads list (§3.3), so a plan or plan-step Log row matches no thread and would
silently lose its existing tap-to-focus.

**Rule:** an event whose item is `plan` or a plan step focuses **General** and uses the event's source
message as the scroll anchor — consistent with plan messages living in General. Every other
coordination id matches a thread row directly. Only the *resolution-parent* remap is withdrawn.

### 11.5 Creation affordances

The three CTAs stay at the top of the tab, gated on `canCoordinateInBeaconRoom` — the one predicate
that correctly mirrors coordination access including the beacon-status gate, and which governs a
mutation rather than a read.

### 11.6 Design-system constraints

`context.tt` tokens and `TenturaText.*` only (`no_inline_font_size`, `no_operational_raw_color`,
`no_raw_edge_insets`, `no_raw_border_radius`). `items_tab.dart` currently ships hardcoded
`EdgeInsets.only(bottom: 10)` / `SizedBox(height: 8)` and a hardcoded English `'Closed (…)'`; the
rewrite fixes both. Row actions must not be long-press-only — secondary-tap plus a hover affordance,
filtered by `PointerDeviceKind`, per the cross-platform gesture rule.

---

## 12. Thread detail

```
ThreadDetail(thread)
├── if thread.item != null:  semantic header
└── BeaconRoomBody(...)      ← reads RoomCubit from context; takes no thread id
```

**D27 removes the banner entirely.** rev 2 required a detail-time `fetchPendingResolutionForItem`
because `CoordinationItemRow` carries no pending-resolution field. With the resolution feature gone,
`ItemActionsCubit` loses `pendingResolution`, `acceptResolution()`, and `rejectResolution()`, the
banner is deleted, and the detail needs no second query. The fat-row contract (D9) now covers both
list and detail.

Preserved behaviors a naive rewrite would drop:

- **`ClosedRequestBanner` — compact/regular only.** It already lives on
  `beacon_operational_header_card.dart:78`, which remains the left pane on expanded. The second copy
  exists on `BeaconRoomSurface` solely for the compact pushed surface. Copying it into every
  `ThreadDetail` would double it on expanded.
- `enableComposer` becomes unconditional — nothing disables the composer any more (D27).
- `prepareThreadScroll(messageId:, coordinationItemId:)` — now fed from the route (§9.3).
- `onOpenCoordinationItem` from inside a thread — a selection change, not a nested push.
- `onCoordinationSaved` — `BeaconRoomSurface` wires it to `_refreshItemsTab` so creating an item from
  General refreshes the list. It must become `ThreadsCubit.fetch()`; relying on debounced
  invalidation instead makes item creation feel broken.
- `coordination_item_room_sync.dart` / `coordination_room_navigation.dart` cross-links;
  `openCoordinationItemFromRoom` collapses into "set `openThreadId`".

---

## 13. Deletions and repoints

**Client — deleted**

- `beacon_view/ui/widget/beacon_room_surface.dart`, `beacon_view_room_app_bar_button.dart`,
  `items_tab.dart`
- `coordination_item/ui/screen/item_discussion_screen.dart`
- `beacon_room/ui/screen/beacon_room_screen.dart`, `kPathBeaconRoom`, and the `BeaconRoomRoute` root
  registration whose guard redirects to the deleted `viewTab: 'room'`
- `canNestItemDiscussionInRoomPane` + `can_nest_item_discussion_test.dart`
- `beaconViewRoomRequestedByRoute`, `beaconViewShowsLegacyRoomSurface`, `_urlIndicatesRoom`,
  `_stripRoomFromUrl`, `_scheduleExpandedRoomRouteSync`,
  `_scheduleExpandedRoomPaneRouteFocusIfNeeded`, `_syncActiveThreadHost`,
  `_activateExpandedRoomSplit`
- `kQueryBeaconSurface`, `kBeaconSurfaceRoomQueryValue`, `kQueryCoordinationItemId` (`'item'`)
- `BeaconViewScreen.suppressEmbeddedRoomBack`, `.embeddedRoomCloseNonce`,
  `.onEmbeddedRoomOpenChanged`, `_notifyEmbeddedRoomOpen`, and their `MyWorkBeaconViewPane`
  forwarders
- `BeaconParticipantRoomSeen` document (absorbed by `markThreadSeen`, §5.2)
- `TestIds.beaconRoomOpen`; `beaconTabItems` → `beaconTabThreads`; `labelBeaconTabRoom`

**Client — must be repointed (missing from rev 1, and they will break the build)**

- `beacon_room/ui/widget/room_message_tile.dart:47–67` — constructs `ItemDiscussionRoute` directly
- `beacon_room/ui/coordination_room_navigation.dart:23–43` — same
- every `onEnterRoomSurface(...)` call site — `beacon_view_app_bar_overflow.dart:196–211`,
  `beacon_view_status_bottom_sheet.dart:370–384`, `beacon_view_screen.dart:1155` — become
  "open `thread=general`". The status sheet's "resolve in Chat" is otherwise a dead callback.
- `destination_map.dart`, `notification_deep_link.dart` (§9.3)

A merge gate should `rg` for `ItemDiscussionRoute`, `BeaconRoomRoute`, `kPathBeaconRoom`,
`tab=room`, and `surface=room` and require zero hits.

**Server — deleted (D27, resolution removal)**

- `domain/use_case/coordination_item/create_resolution_case.dart`, `accept_resolution_case.dart`,
  `reject_resolution_case.dart`
- `createResolution` / `acceptResolution` / `rejectResolution` GraphQL mutations
- `coordinationItemKindResolution` (`consts/coordination_item_consts.dart:8`) and its uses at
  `coordination_item_repository.dart:1379, 1499`
- **four** kind-4 sites in `responsibilityCountsByBeaconIds`, not two: the `review_open` and
  `review_new` FILTER blocks, the `ci.kind = 4 AND EXISTS (…target_item_id…)` branch inside
  `_sqlMyResponsibilityOnCi` (the server twin of the client `resolutionParent` hop), and the
  `ci.kind IN (2, 3, 4, 5)` list in `others_open` (`coordination_item_repository.dart:1248-1307`).
  The last two are dead rather than crashing after m0149, but leaving them makes "no code path can
  produce or consume a resolution" false in SQL
- **migration m0149:** `DELETE FROM coordination_item WHERE kind = 4;` (messages cascade via
  `beacon_room_message.thread_item_id … ON DELETE CASCADE`)

**Client — deleted (D27)**

- `data/gql/coordination_item_{create,accept,reject}_resolution.graphql` + `build_client.dart` entries
- `CoordinationItemKind.resolution` and its `fromInt(4)` case
- `ItemActionsCubit.pendingResolution` / `acceptResolution()` / `rejectResolution()`;
  `CoordinationItemCase.fetchPendingResolutionForItem`
- `_PendingResolutionBanner`, `showItemDiscussionProposeResolutionSheet`,
  `ItemDiscussionOverflowAction(onProposeResolution:)`
- the `acceptAction` / `rejectAction` resolution arms in the items list
- `involvesUserAsSourceOrTarget`'s resolution branch, `resolutionParent`, and
  `filterActiveItemsForUser`'s `lookupItems` / `byId` map
- `CoordinationResponsibility.reviewOpen` / `reviewNew` and the "reviews" YOU-line segment
  (`coordination_responsibility.dart:32–72`) — **visible My Work change, §16-Q13**
- `beacon_activity_event_presenter.dart` resolution arms (`:187–202`, `:281–283`) and l10n
  `coordinationResolutionCardLabel`, `coordinationResolutionAcceptLabel`,
  `coordinationResolutionRejectLabel`, `beaconRoomActionCreateResolution`,
  `coordinationMarkResolutionHint`, `coordinationSemanticResolution{Opened,Resolved,Cancelled}`

**Must NOT be deleted despite matching a string search:** `l10n.notificationCatUnblocksMe` (renders
"Resolutions", but is the *unblock* notification category) and `CoordinationItemStatus.superseded` /
event kind 6 (a generic status, not resolution machinery).

**Server — otherwise deleted:** nothing. `beacon_items_seen` and `markBeaconItemsSeen` are **retained** (§5.5);
`beaconParticipantRoomSeen` folds into `markThreadSeen`.

**Client — test/e2e references that will break**

- `integration_test/support/e2e_test_helpers.dart:497` (`TestIds.beaconRoomOpen`) and `:522`
  (`TestIds.beaconTabItems`) — both deleted/renamed. The e2e suite is not covered by `flutter test`,
  so these fail later than everything else unless fixed in the same change.

**Kept:** `coordinationItemsByBeacon`. rev 1 said "My Work uses it" — it does not; My Work goes
through `coordinationResponsibilityBatch` (`my_work_case.dart:210`) and
`MyWorkCoordinationItemActivity`. Its real remaining consumers are `ItemActionsCubit`, the case
helpers (`fetchOpenBlocker`, `fetchCurrentRootPlan` — `fetchPendingResolutionForItem` is deleted by
D27), and
`BeaconRoomCase`. It stops being this screen's list source but is not deletable.

---

## 14. Localization, terminology, docs

| Key | EN | RU |
|---|---|---|
| `labelBeaconTabItems` → `labelBeaconTabThreads` | Threads | Темы |
| new `threadGeneralTitle` | General | Общее |
| hardcoded `'Closed (n)'` in `items_tab.dart` | → `l10n` | → `l10n` |
| `labelBeaconTabRoom` ("Chat" / «Чат») | deleted — see below | |

### 14.1 Retiring "Chat", introducing "Thread" (D28)

**Owner decision:** user-facing **Chat** is retired.

**One glossary, to avoid the contradiction earlier drafts carried.** `terminology.mdc`'s contract
table has a single *workspace* column, so it cannot say both "Thread" and "discussion". The workspace
— the thing you are admitted to — is **обсуждение / discussion**. **тема / thread** is one
conversation inside it, and is not a glossary-table concept at all:

| terminology.mdc column | Value |
|---|---|
| Primary object (user-facing) | **Request** / «запрос» |
| Workspace (user-facing) | **discussion** / «обсуждение» |
| *(not in the table)* | one conversation = **thread** / «тема»; the built-in one = **General** / «Общее» |

`AGENTS.md`'s terminology invariant line and `CONTEXT.md` § Terminology follow the same table.
Exactly one unit may edit the glossary — see §16-Q14.

**Correction to an earlier claim in this document:** "Chat" is **not** CI-enforced.
`scripts/check-user-facing-terminology.sh` is a *blocklist* — it fails only when user-facing copy
contains the internal nouns `beacon` / `room` (RU `маяк` / `комнат`), plus a check that `AGENTS.md`
and `CONTEXT.md` still document the alias. It never asserts that "Chat" appears, and
`request_terminology_contract_test.dart` does not mention Chat either. So retiring Chat breaks no
gate; it is a documentation-and-copy change, not a build-breaking one. The blocklist on `room`
remains satisfied — "Thread" is not `room`.

**But the copy surface is large and not mechanical.** Counts have been disputed three times because
they depend on the matcher, so the *command* is the specification, not a number: ARB **values**
(skipping `@`-metadata keys) matching `/[Cc]hat/` in `app_en.arb` and `/чат/i` in `app_ru.arb` —
currently ~59 EN and ~77 RU. They split into **three** senses needing three different replacements:

| Sense | Examples | Becomes |
|---|---|---|
| **The conversation surface** | "Open Chat", "Ask in Chat", "Chat · {count}", "Last in chat", `labelBeaconTabRoom` | **General** where it means that one thread; **Threads** where it means the tab |
| **Access / membership envelope** | "Admits to chat", "No chat admission", "Chat members", "Remove from chat", "Can read this chat" | **обсуждение / discussion** — request-level participation |
| **Fact visibility** (missed by earlier drafts) | `beaconRoomPinFactPublic` "Public — visible beyond the chat", `beaconRoomPinFactRoomOnly` "Chat only", `beaconRoomSemanticRoomFact` "Chat fact", `beaconRoomFactCardActionMakePrivate` "Chat only" | also **discussion** — facts are request-scoped, so "thread only" would be wrong |

The second and third groups are the trap: "Chat" was doing triple duty — the General conversation,
the admission envelope for the whole request, *and* the privacy boundary for fact cards. Under the Threads model those are different concepts —
admission grants access to the request's threads collectively, not to one thread — so a
find-and-replace to "Thread" would produce copy that is wrong, not merely awkward.

#### The three-level vocabulary (owner decision)

The access sense gets its own noun — **обсуждение / discussion** — giving a coherent three-level
scheme:

| Level | RU | EN | Used for |
|---|---|---|---|
| The request | **запрос** | **Request** | unchanged |
| The whole conversation space (collective) | **обсуждение** | **discussion** | admission, membership, access: «допуск к обсуждению», «участники обсуждения», «удалить из обсуждения» |
| One thread | **тема** | **thread** | the tab «Темы», «Открыть тему»; the built-in one is **Общее / General** |

So the access-sense strings become «Допуск к обсуждению» / "Admitted to the discussion",
«Участники обсуждения» / "Discussion participants", «Удалить из обсуждения» / "Remove from the
discussion", and so on.

**This requires freeing the word first.** «Обсуждение» / "Discussion" today means *one item's
thread*, in three keys:

| Key | EN now | RU now | Becomes |
|---|---|---|---|
| `coordinationItemDiscussionTitle` | "Discussion" | «Обсуждение» | retired — under Threads the title is the item's own title, or «Общее» for General |
| `coordinationItemDiscussionComposerHint` | "Add to discussion…" | «Добавить в обсуждение…» | re-worded to the thread sense («Написать в тему…») |
| `beaconRoomActionOpenThread` | "Open thread" | «Открыть обсуждение» | «Открыть тему» — EN and RU already disagree here today |

If those three are not repointed in the same sweep, the two senses collide again and «обсуждение»
means both "one thread" and "all threads" in the same UI.

**Incidental:** several RU strings in the access group already carry gender/case bugs
(«Чат недоступна», «Участники чаты»). The rewrite is the natural moment to fix them, but that is
cleanup, not part of the decision.

**`docs/features/beacon_room.md` is normative and becomes false.** It currently specifies a three-tab
Request with **Items** and a separate full-screen **Room**, and describes ask/blocker/promise/
**resolution** item threads. It must be rewritten as part of this change, not after it — including
removing resolutions from its vocabulary (D27).

Per `.cursor/rules/versioning.mdc`: user-visible change → semver bump in
`packages/client/pubspec.yaml` **and** the `web/index.html` `flutter_bootstrap.js?v=` cache-buster,
which only regenerates when the app is actually built locally.

---

## 15. Test surface

The 31 files under `test/features/beacon_room` are mostly message rendering, composer, replies,
reactions, mentions, and `RoomCubit`; they move with the rename unchanged.
`can_nest_item_discussion_test.dart` is deleted with its subject.

| Area | What must be pinned |
|---|---|
| Union authorization | non-admitted item participant sees their thread and **no** General; room member sees General exactly once; empty result throws as today |
| `general` boundary | `"general"` never reaches `threadItemId`; General's `RoomCubit` gets `null`; fact cards / plan / room state / watermark still work for General |
| Mark-seen | General keeps its clamp and monotonic floor; thread path keeps neither; both conflict targets upsert correctly |
| `beacon_items_seen` | responsibility `*_new` counts still work — a regression test that would have caught rev 1's proposed drop |
| Cubit lifecycle | rapid thread switching: previous `close()` (and its mark-seen) completes before the next load; badge does not flicker |
| Liveness | out-of-order responses discarded (latest-wins); `roomSeen` not debounced like `roomMessage` |
| Query shape | items with zero messages and drafts appear as rows; General unread equals `countRoomMessagesAfter` |
| Preview tokens | every persisted system-row family maps to a variant; `systemPayload` never in an excerpt |
| Routing | pop from thread detail reveals the list once, no duplicate `BeaconViewRoute`; cold deep link at `?thread=`; unknown thread falls back to first accessible row |
| Resolution removal | no `kind = 4` rows survive the migration; `CoordinationItemKind.fromInt(4)` is unreachable; My Work YOU line renders without a reviews segment; `notificationCatUnblocksMe` still says "Resolutions" |
| Adaptive | right pane persists across People/Log; embedded pane splits on pane width; embedded compact requests a host route |
| Row widget | goldens collapsed + expanded, light + dark |

Gate: `scripts/check-custom-lints.sh` for both packages (**not** `flutter analyze` — it does not load
the plugin), `flutter test`, `bash scripts/check-user-facing-terminology.sh`.

---

## 16. Open questions

**Q1 — terminology (§14).** Partly settled by the owner:

- **Settled:** the tab is **Threads / Темы**, and General's title is **General / «Общее»** (owner
  correction — the original brief said «Общий разговор»; «Общее» is the shipping copy).
- **Settled (D28):** user-facing **"Chat"** is retired; **Thread / Тема** replaces it in
  `terminology.mdc`, `AGENTS.md` and `CONTEXT.md`. Scope and the two-sense trap are in §14.1.
- **Still open:** does `coordinationPromiseCardLabel` become **Commitment / «Обязательство»** as the
  brief names it, or stay "Promise" / «Обещание»? The code identifier stays `promise` either way.

**Q2 — Draft row treatment (D16).** Visually marked as "not yet a thread"? Drafts fold above or below
Closed?

**Q3 — Empty state.** A new request has one row. Active fold shown empty with CTAs, or a first-run
line explaining that Asks/Commitments/Blockers become threads?

**Q4 — Excerpt truncation length.** 140 chars is a guess; interacts with row height at compact width.

**Q5 — Relative timestamp buckets.** Reuse the stale/overdue ticker or a separate coarser one?

**Q6 — Selected-row affordance on regular.** No split there; does the row show a "visited" state on
return from the pushed detail?

**Q9 — Mark-seen response fidelity (§5.3).** *Restated — the original question rested on a false
premise.* Storage is already monotonic for both General and threads (`GREATEST`). The real, narrower
item is a latent bug: the mutation returns the **submitted** timestamp rather than the **persisted**
one, so a stale write reports a watermark the database does not hold and the client stores it via
`confirmSynced`. **Decision: implement the fix** — the upsert returns `RETURNING last_seen_at`, the repository
propagates it, and `markThreadSeen.seenAt` reports the effective persisted value. Leaving it as "an
assumption not to fix" would be self-defeating: §5.4 keys the local watermark store by thread and
§6 suppresses row unread from it, and both consume exactly this response. General's case-layer floor
usually masks the discrepancy; a semantic thread has no floor, so the lie lands directly in
`confirmSynced`. Pin it with a test asserting response equality with the stored watermark.

**Q10 — §10.5 sliver architecture.** Confirm option (a) for v1.

**Q11 — ~~Resolution conversations~~ (closed by D27).** The question was where resolution message
history should surface once resolutions stopped being rows. The feature is deleted instead, so there
is no history to re-home and no answer needed. Closed by deletion rather than by a guess.

**Q13 — ~~My Work "reviews" segment~~ (closed, confirmed by owner).** The YOU line renders asks,
commitments and blockers only. No replacement counter. See §3.6.

**Q12 — ~~`currentCoordinationPlan` home~~ (closed by evidence).** The field has **zero readers**;
`RoomCubit` loads the plan it needs independently. `ThreadsCubit` drops the fetch entirely (§4.6).

~~Q7 (embedded callbacks)~~ and ~~Q8 (message index)~~ answered in §8.5 and §2.
