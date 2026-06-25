# Beacon & Room — product spec (as shipped)

User-facing behavior of a **beacon** (the request) and its optional **Room** (coordination workspace). For product direction and philosophy, see [`../Tentura_current_status_quo.md`](../Tentura_current_status_quo.md).

## What a beacon is

A beacon is a **request for help** that can be forwarded person-to-person, committed to, coordinated, and closed. It is not a discussion thread or a feed post.

Each beacon has:

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
| **My Work** | Beacons I authored and/or offered help on |
| **Inbox** | Beacons forwarded to me that need triage or passive follow |
| **Friends** | People in my network (forward targets, trust) |
| **Profile** | Account, capabilities, settings |

**Inbox** has two tabs:

- **Needs me** — actionable triage (forward, offer help, not for me, move to watching).
- **Watching** — I chose to follow without offering help.

**Not for me** is an **archive** (overflow menu), not a third inbox tab. Rejected items leave the active triage queue.

## Beacon detail

Opening a beacon shows a **coordination header** (shared situation + personal obligation) and three tabs:

| Tab | What the user sees |
|-----|-------------------|
| **Items** | Need, pinned facts, coordination items (plan, asks, blockers, promises, resolutions), and entry to the Room |
| **People** | Author, helpers, forwarders, room membership |
| **Log** | Public timeline of beacon-level changes |

The header rows (**STATUS**, **NOW**, **YOU**, **ACT**) summarize phase and next action without turning the screen into a chat. Copy is shared for everyone in the same visibility tier; **YOU** and **ACT** are personal.

### Lifecycle (user-visible)

While **open**, the author may signal whether more help is needed or enough help is in motion. Helpers can **offer help** openly (with a note); the author may respond per offer about **fit and coverage** — this is coordination metadata, not approval of a person.

**Blockers** surface when work is stuck; clearing them is a shared coordination act.

When the author **closes** successfully, eligible participants enter a **review window** to acknowledge contributions privately (see [`../beacon-evaluation-principles.md`](../beacon-evaluation-principles.md)).

## Room

The **Room** is a separate full-screen workspace for people **admitted** to coordinate execution (author, admitted helpers, stewards as product rules allow).

In the Room the user can:

- read and send **messages** tied to coordination (not a public forum),
- work through **coordination items** — **plan** (steps), **ask**, **blocker**, **promise**, **resolution**,
- open **item threads** for discussion on a specific ask/blocker/promise/resolution (plans use the plan surface instead),
- pin or correct **facts** visible at the right visibility (beacon-wide vs room-only).

Room content stays **scoped**: people who are not in the Room do not see room-private messages or room-only facts on public beacon surfaces.

**Admission** is explicit — offering help or forwarding does not automatically grant full Room access.

## Forwarding

Forwarding is **manual** and **targeted**. Each forward carries a personal note. Recipients see scoped involvement states on the forward screen (who offered help, declined, is watching, was already forwarded to, etc.).

Forwarding alone does **not** create broad social visibility beyond the beacon path.

## What this feature is not

- Not a group chat replacement for the whole app (no global 1:1 chat product surface).
- Not a ranked feed or comment thread under the beacon.
- Not a public reputation or leaderboard surface.
- Not a registry/group tab — lists are **Inbox** (push) and **My Work** (ownership).

## Related guidance

- [`../Tentura_current_status_quo.md`](../Tentura_current_status_quo.md) — relay model, inbox vs my work, MR scope
- [`../watching-mechanism.md`](../watching-mechanism.md) — Watching vs triage
- [`../beacon-status-line-rationale.md`](../beacon-status-line-rationale.md) — STATUS / NOW / YOU / ACT copy rules
- [`../beacon-evaluation-principles.md`](../beacon-evaluation-principles.md) — post-close review
- [`../before-response-terminal-tombstone.md`](../before-response-terminal-tombstone.md) — when the beacon ends before I acted
