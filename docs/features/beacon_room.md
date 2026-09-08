# Request (internally: Beacon) & Discussion — product spec (as shipped)

User-facing behavior of a **Request** (internally: **Beacon**) and its **discussion** workspace (internally: `beacon_room`). One conversation inside the discussion is a **thread** / **тема**; the built-in thread is **General** / **Общее** — the **only** public conversation on each request. For product direction and philosophy, see [`../Tentura_current_status_quo.md`](../Tentura_current_status_quo.md).

## What a Request is

A **Request (internally: Beacon)** is a **request for help** that can be forwarded person-to-person, committed to, coordinated, and closed. It is not a discussion thread or a feed post.

Each request has:

- a **need** (what is being asked for),
- **context** (where/when/constraints),
- optional **media**,
- a **lifecycle** (open → closed → optional review window → review complete),
- a **forward chain** visible to people on that path,
- and optional **child requests** linked through an immutable nesting parent (`parent_beacon_id`).

There are **no comments** on beacons. Updates happen through structured coordination in **General**, not open-ended replies on a public surface.

## Home surfaces

Bottom navigation (default tab: **My Work**):

| Tab | Role |
|-----|------|
| **My Work** | Requests I authored and/or offered help on |
| **Inbox** | Requests forwarded to me that need triage or passive follow |
| **Friends** | People in my network (forward targets, trust) |
| **Profile** | Account, capabilities, settings |

**Inbox** has two tabs:

- **Needs me** — actionable triage (forward, offer help, not for me, move to watching).
- **Watching** — I chose to follow without offering help.

**Not for me** is an **archive** (overflow menu), not a third inbox tab. Rejected items leave the active triage queue.

## Request detail

Opening a request shows a **coordination header** (shared situation + personal obligation) and three surface tabs below the app bar:

| Tab | What the user sees |
|-----|-------------------|
| **NOW** | Coordination header card (**NOW**, **YOU**, **Details**, **ACT**), pinned facts, and **child request** cards (published children plus the viewer's unpublished drafts) |
| **Chat** | **General** conversation when admitted (message list + composer); tab label is the short form of the discussion workspace — see [`.cursor/rules/terminology.mdc`](../../.cursor/rules/terminology.mdc) |
| **People** | Author, helpers, forwarders, discussion participants |

The **Activity log** (coordination timeline) is no longer a tab — it opens from the request overflow menu as a full-height adaptive sheet (`labelBeaconTabLog`).

The header rows (**NOW**, **YOU**, **Details** when schedule/location/definition exist, **ACT**) summarize phase and next action. Copy is shared for everyone in the same visibility tier; **YOU** and **ACT** are personal. Mini-avatars for involved people appear on the **General** card (not in the header).

### Lifecycle (user-visible)

While **open**, the author may signal whether more help is needed or enough help is in motion. Helpers can **offer help** openly (with a note); the author may respond per offer about **fit and coverage** — coordination metadata, not approval of a person.

When the author **closes** successfully, eligible participants enter a **review window** to acknowledge contributions privately (see [`../beacon-evaluation-principles.md`](../beacon-evaluation-principles.md)).

Closing or cancelling a parent does **not** auto-close children; admitted participants on related requests receive **hierarchy notices** in their own General threads (generic copy only — no private ancestor content leaked to child-only viewers).

## Discussion model

### General-only conversation

The **Chat** surface exposes one addressable conversation per request:

| Surface | Meaning |
|---------|---------|
| **General** | The main conversation (`thread_item_id` null in storage): messages, replies, mentions, polls, facts, plans |
| **Child requests** | Separate published beacons under this parent — cards on the parent, full detail via normal request routes |

Retired **ask**, **commitment (promise)**, and **blocker** coordination-item threads are no longer list rows or navigation targets. Server thread scope machinery remains for internal fixtures; the product path is General-only.

**Plan** and plan-step coordination items are not Discussion list rows; plan work surfaces in General and the Log.

### Child requests (nesting)

A **child request** is a normal beacon with its own owner, membership, help offers, forwarding, review window, and trust attribution. Parentage is immutable and assigned only at creation.

| Capability | Parent admittee (no child admission) | Child admittee |
|------------|--------------------------------------|----------------|
| See child card on parent | ✅ (summary via linked-detail read) | ✅ |
| Open child General | ❌ | ✅ (independent admission required) |
| Inbox / My Work involvement for child | ❌ | Per normal involvement rules |
| Forward / offer help on child | ❌ | Per normal child policies |

Parent admission does **not** grant child discussion access. A forward to the child creates ordinary inbox involvement; accepting/obtaining child admission unlocks General independently.

**Create child request** — from the parent's **NOW** surface or by promoting a General message. Promotion keeps the source bubble; a footer links to the published child when readable; a system **child created** notice records publication. One published child per source message.

**Parent reference on child** — when the viewer can read the parent under the one-edge rule, a navigable parent reference is shown; otherwise unavailable/tombstone wording with no actionable parent id or title leak.

### Authorization (discussion rows)

Who sees Discussion content:

- **General row** — author, stewards, and helpers explicitly admitted to the discussion (`room_access`). Offering help or receiving a forward does **not** admit by itself.
- **Child request cards** — effective admission to the **parent** request (same as listing/creating children). Cards use linked-detail visibility, not widened content read.
- **Child drafts** — author only until published.

Empty or blocked admission shows the admission placeholder. Item-participant union rules for semantic threads are retired.

### Navigation surfaces

| Window class | Behavior |
|--------------|----------|
| **Compact** / **regular** | Three tabs (NOW / Chat / People). **Chat** shows **General** inline — no pushed thread route. Child cards on NOW open normal beacon detail routes. |
| **Expanded** (split, when General is accessible and the thread list has ever had rows) | Left: app bar + tab bar (**NOW** and **People** only — Chat is hidden because the conversation is permanently in the right pane); right: **General** (`BeaconRoomSurface`). Split latches once thread rows exist and does not collapse on a silent threads refresh. |
| **Embedded** (My Work pane) | Split follows **pane width**, not window class |

**URL contract** (`kQueryBeaconViewTab` wire values are unchanged — `threads` still selects the conversation):

| URL | Result |
|-----|--------|
| `/beacon/view/:id` | NOW |
| `?tab=now` | NOW |
| `?tab=threads` | Chat (split: room pane focused, NOW selected in the left tab bar) |
| `?tab=threads&thread=general` | Chat |
| `?tab=threads&message=<id>` | Chat, scrolled to the message |
| `?tab=people` | People |
| `?tab=people&people_tab_attention=1` | People + attention pulse |
| `?tab=log` | NOW + Activity sheet opened post-frame (legacy compat) |
| unknown / absent `tab` | NOW |
| `/beacon/view/:id/thread/general` | redirect → `?tab=threads&thread=general` |
| `/beacon/view/:id/thread/<legacy>` | redirect → Chat showing `beaconLegacyThreadUnavailable` |
| `?message=<id>` without `thread=` | canonicalized in-place to Chat + scroll |

**Redirect precedence** (one normalizer for cold deep links and warm `/thread/:id` redirects): (1) path `thread/:threadId` wins over query `thread=`; (2) a resolved thread id implies `tab=threads`, overriding incoming `tab=`; (3) a non-`general` thread id resolves to Chat + legacy-unavailable, even when `message=` is present; (4) `entry=` / `is_deep_link=` provenance parameters are preserved; (5) anything unrecognized falls through to NOW.

Child beacons use standard beacon routes, not thread ids.

### Per-thread unread

Unread counts for **General** appear on the **Chat** tab badge (`threadsTabUnreadCount`). Closed-thread unread may be stored but is excluded from the badge. Child request state does not inherit parent read watermarks; viewing a parent does not mark a child's General seen. Own messages do not count as unread. Read-to-bottom suppresses row unread optimistically until sync completes.

### General detail

General hosts the shared message composer and history: replies (same thread scope), @mentions, polls, attachments, facts, and plan interactions. **Hierarchy notices** (ancestor/child lifecycle, child created) render as centered system rows with typed payloads. Terminal parent/child statuses make General **read-only** for ordinary user writes; system notices still materialize from the delivery worker.

## Discussion admission and membership

**Admission** to the **discussion** is always **explicit** — offering help or receiving a direct forward does not automatically grant access. When the author **directly forwarded** the request to someone and they offer help, the offer is marked and sorted upward in People, but the author must still **Accept** explicitly before admission.

**Backup offers:** when the request signals **enough help**, additional offers are allowed as **backup** — secondary coordination without "offers awaiting author" pressure. Backup offers are never auto-activated.

**Remove from the discussion ≠ End participation:** removing someone revokes **discussion access only**; participation record and committer stake remain until **End participation** (or helper withdraws). **End participation** drops current stake while keeping historical acknowledgement. The UI must not conflate remove-from-discussion with ending participation.

## Fact visibility

Facts pinned on messages use **discussion-scoped** visibility boundaries — request-wide public vs **discussion only** — not per-thread isolation. Fact cards and visibility copy use **discussion** vocabulary.

## Forwarding

Forwarding passes the request along the trust graph. Each hop is visible to people on the path. Forwarding does not grant discussion access by itself. Parent-only hierarchy visibility does **not** allow forwarding a child.

The Forward candidate mini-profile may show one deterministic path through a
capped MeritRank graph snapshot. This is provenance from that bounded snapshot,
not a complete-network guarantee and not an explanation of why a person was
recommended. Candidate eligibility continues to come from the canonical mutual
visibility projection. People hidden from the viewer are removed before path
construction; a graph identity that can no longer be hydrated is shown only as
an unavailable person, without exposing its ID.

One active Forward surface owns the synchronous recipient-selection session.
Deselecting is always allowed; selecting re-resolves the current candidate and
availability before changing local state. Blocking is viewer-owned, and this
flow adds no cross-device or cross-session compare-and-swap. Server-side
Forward validation remains the final enforcement boundary.

## Realtime convergence

Discussion child lists and parent references subscribe to the `beacon_hierarchy` invalidation kind (alongside existing `room_message`, `participant`, etc.). Hints carry ids/events only; clients refetch authorized snapshots. Access loss evicts cached child cards without leaking content.

## Copy vocabulary (user-facing)

| Level | EN | RU |
|-------|----|----|
| Request | Request | запрос |
| Whole workspace | discussion | обсуждение |
| One conversation | thread | тема |
| Built-in thread | General | Общее |
| Nested request | child request | дочерний запрос |

Internal code, storage, GraphQL, and routes retain **beacon** / **room** identifiers — see [`../../CONTEXT.md`](../../CONTEXT.md) and [`.cursor/rules/terminology.mdc`](../../.cursor/rules/terminology.mdc).
