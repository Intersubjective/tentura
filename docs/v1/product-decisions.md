# V1 product decisions (canonical)

Amendments and locks for implementation agents. These **override** older phrasing in the informal “V1 redesign brief” where they conflict.

---

## Beacon lifecycle (replaces `enabled`)

- **Remove** the boolean **`enabled`** field as the source of truth for beacon state.
- **Introduce** an **enum** (DB + GraphQL + client) with richer semantics, e.g.:
  - `OPEN`, `CLOSED`, `DRAFT`, `PENDING_REVIEW` (extend as needed).
- All queries, UI (My Work Active/Closed, inbox badges, author controls), and migrations must use this enum.

---

## Inbox MR sort

- **MR sort** = **server-computed per-beacon score** (beacon’s score from **MeritRank** for the current user and context).
- Expose a sortable field or pre-ordered view so the client can request **MR | Recent | Deadline** without recomputing MR on device.

---

## Forward screen: filters and involvement

- **Filters** (All / Best next / Unseen / Already involved, etc.) are primarily **client-side** on the candidate list, combined with data from:
  - existing friends/reachable payloads, and
  - **optional new API** that returns **people involved in this beacon** with roles such as:
    - forwarded (along chain),
    - unseen (relative to current user),
    - already involved (committed / uncommitted / declined),
    - author.
- “Best next” remains to be defined as a ranking heuristic (likely MR + involvement + recency); can stay client-side until server assists.

---

## 1-to-1 chat

- **Keep** 1-to-1 chat as a **supported feature** (including `ChatRoute`, `ChatPeerListTile`, `ChatNewsCubit` as needed).
- **Do not** remove chat for V1. Network IA may still add Contacts / Reachable / Graph sections **alongside** chat entry points.

---

## Personal beacon list on profile

- **Keep** the **“Show Beacons”** / personal beacon list on **one’s own profile** (and equivalent **personal** scope) for now.
- This is **not** treated as a contradiction with anti-feed goals: it is **explicitly scoped** to a **single user’s** beacons, not a global discovery feed.

---

## Report / complaint

- **Keep** the **report** action on beacons (non-owners). It routes to **platform moderators** and is **required for legal / safety** compliance.
- This is **not** optional V1 scope trimming; do not remove.

---

## Global chrome: AppBar actions

- **Standardize** on **AppBar actions** (not FABs) for cross-tab consistency:
  - context switcher,
  - new beacon,
  - scan / enter code (and related connect flows).
- **Refactor** the shell (`HomeScreen` / tab scaffolds) so every main tab uses a **consistent AppBar** pattern instead of mixing FAB + inline dropdowns only on some tabs.

---

## Commit and overcommit coordination (Phase 1)

- **Commit stays open by default** — no mandatory pre-approval for ordinary commits.
- **Hard lifecycle gate for commit:** only **OPEN** beacons accept new commitments (`beaconCommit`). Coordination status is **not** a commit lock (including “enough help committed”); use softer UI copy in that case (see overcommit doc §11).
- **Uncommit:** allowed only when lifecycle is **not** closed, draft, deleted, or closed-review-complete — i.e. allowed on **open**, **pending review**, and **closed review open** (see overcommit doc §9).
- **Author coordination responses** describe **coverage / fit of the beacon’s need**, not approval or rejection of a person. UI and data model must keep that framing (see [`../overcommit-coordination-feature-design.md`](../overcommit-coordination-feature-design.md)).

---

## Watching (Phase 1)

- **Watching** is explicit passive follow: triaged, not rejected, not committed, not owning execution. It lives in **`inbox_item.status = 1`** alongside Needs me (`0`) and rejected (`2`).
- **Do not** add a third primary CTA (Watch) next to Forward / Not for me on inbox cards. Use overflow, beacon detail, and auto-watch after forward when the user has **no active commitment**.
- **Forward without commit** moves the sender’s row to **Watching** so Inbox stays a real triage queue.
- **Recipient lists** (forward screen) must show **Watching** with clear precedence vs Committed / Forwarded onward / Not for me — see [`watching-mechanism.md`](./watching-mechanism.md).

---

## Document map

| Document | Role |
|----------|------|
| `product-decisions.md` (this file) | Locks and amended goals |
| `missing-features-plan.md` | What to build; references this file |
| `contradictions-plan.md` | Code vs brief conflicts still to fix |
| `../overcommit-coordination-feature-design.md` | Overcommit coordination (active beacon), commit / uncommit / status |
| `watching-mechanism.md` | Watching stance: surfaces, transitions, forward-list precedence, copy |
