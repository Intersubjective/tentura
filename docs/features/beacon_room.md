# Request (internally: Beacon) & Threads — product spec (as shipped)

User-facing behavior of a **Request** (internally: **Beacon**) and its **discussion** workspace (internally: `beacon_room`). One conversation inside the discussion is a **thread** / **тема**; the built-in thread is **General** / **Общее**. For product direction and philosophy, see [`../Tentura_current_status_quo.md`](../Tentura_current_status_quo.md).

## What a Request is

A **Request (internally: Beacon)** is a **request for help** that can be forwarded person-to-person, committed to, coordinated, and closed. It is not a discussion thread or a feed post.

Each request has:

- a **need** (what is being asked for),
- **context** (where/when/constraints),
- optional **media**,
- a **lifecycle** (open → closed → optional review window → review complete),
- and a **forward chain** visible to people on that path.

There are **no comments** on beacons. Updates happen through structured coordination, not open-ended replies.

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

Opening a request shows a **coordination header** (shared situation + personal obligation) and three tabs:

| Tab | What the user sees |
|-----|-------------------|
| **Threads** | **General** (row 0 when admitted) plus semantic threads for active published **Ask**, **Commitment**, and **Blocker** items; collapsed **Closed** fold; own **drafts** |
| **People** | Author, helpers, forwarders, discussion participants |
| **Log** | Public timeline of request-level changes |

The header rows (**NOW**, **YOU**, **Details** when schedule/location/definition exist, **ACT**) summarize phase and next action. Copy is shared for everyone in the same visibility tier; **YOU** and **ACT** are personal. Mini-avatars for involved people appear on the **General** thread card (not in the header).

### Lifecycle (user-visible)

While **open**, the author may signal whether more help is needed or enough help is in motion. Helpers can **offer help** openly (with a note); the author may respond per offer about **fit and coverage** — coordination metadata, not approval of a person.

**Blockers** surface when work is stuck; clearing them is a shared coordination act.

When the author **closes** successfully, eligible participants enter a **review window** to acknowledge contributions privately (see [`../beacon-evaluation-principles.md`](../beacon-evaluation-principles.md)).

There is **no resolution feature** — asks, commitments, and blockers resolve through direct resolve actions on the item, not a separate resolution item type.

## Threads model

### List scope and ordering

The **Threads** tab shows:

1. **General** — pinned first for viewers with discussion admission (see below).
2. **Active** published semantic items — Ask, Commitment, Blocker — as thread rows with last-message preview and per-thread unread.
3. A collapsed **Closed (n)** fold for terminal semantic items (unread on closed rows appears only when the fold is expanded for display).
4. The viewer's own unpublished **drafts** — rows marked as not yet a thread; tap opens the composer, never a route.

**Plan** and plan-step coordination items are **not** list rows; plan work surfaces in General and the Log.

### Thread kinds

| Thread | Meaning |
|--------|---------|
| **General** | The main conversation on the request (`thread_item_id` null in storage) |
| **Ask** | Discussion on one ask item |
| **Commitment** | Discussion on one commitment (promise) item |
| **Blocker** | Discussion on one blocker item |

### Authorization (union rule)

Who sees which rows is the **union** of:

- **Discussion admission** — author, stewards, and helpers explicitly admitted to the discussion (`room_access`).
- **Item participation** — creator, target, or accepter of a semantic item may see **that item's thread** even when not admitted to General.

A non-admitted item participant sees their semantic row(s) and **no General row**. An admitted participant sees General exactly once plus every thread they are entitled to. Empty access shows the admission placeholder.

### Navigation surfaces

| Window class | Behavior |
|--------------|----------|
| **Compact** / **regular** | Threads tab 0; selecting a row pushes `/thread/<id>`; back returns to the list once |
| **Expanded** | Left: header + tab bar + tab body; right: selected thread, **General preselected** when accessible; right pane persists across **People** and **Log** |
| **Embedded** (My Work pane) | Split vs push follows **pane width**, not window class |

URL: `?tab=threads&thread=general|<itemId>`. `message=` scrolls within the open thread. Draft rows are not addressable thread ids.

### Per-thread unread

Unread counts are **per thread**, keyed by `(beacon, thread)`. General unread and semantic-thread unread sum to the Threads tab badge. Own messages do not count as unread. Read-to-bottom suppresses row unread optimistically until sync completes.

### Thread detail

Each addressable thread hosts the shared message composer and history. Semantic threads show the item header (kind, status, title) above messages. **@mentions** in the composer notify admitted participants; participants without a public handle can be mentioned by name while composing or sending, but not while editing an existing message. **Replies** reference one parent message in the **same thread scope**; deleting the parent clears the quote on next read.

## Discussion admission and membership

**Admission** to the **discussion** is always **explicit** — offering help or receiving a direct forward does not automatically grant access. When the author **directly forwarded** the request to someone and they offer help, the offer is marked and sorted upward in People, but the author must still **Accept** explicitly before admission.

**Backup offers:** when the request signals **enough help**, additional offers are allowed as **backup** — secondary coordination without "offers awaiting author" pressure. Backup offers are never auto-activated.

**Remove from the discussion ≠ End participation:** removing someone revokes **discussion access only**; participation record and committer stake remain until **End participation** (or helper withdraws). **End participation** drops current stake while keeping historical acknowledgement. The UI must not conflate remove-from-discussion with ending participation.

## Fact visibility

Facts pinned on messages use **discussion-scoped** visibility boundaries — request-wide public vs **discussion only** — not per-thread isolation. Fact cards and visibility copy use **discussion** vocabulary; "thread only" would be wrong because facts are request-scoped.

## Forwarding

Forwarding passes the request along the trust graph. Each hop is visible to people on the path. Forwarding does not grant discussion access by itself.

## Copy vocabulary (user-facing)

| Level | EN | RU |
|-------|----|----|
| Request | Request | запрос |
| Whole workspace | discussion | обсуждение |
| One conversation | thread | тема |
| Built-in thread | General | Общее |

Internal code, storage, GraphQL, and routes retain **beacon** / **room** identifiers — see [`../../CONTEXT.md`](../../CONTEXT.md) and [`.cursor/rules/terminology.mdc`](../../.cursor/rules/terminology.mdc).
