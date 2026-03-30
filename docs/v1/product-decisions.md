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

## Document map

| Document | Role |
|----------|------|
| `product-decisions.md` (this file) | Locks and amended goals |
| `missing-features-plan.md` | What to build; references this file |
| `contradictions-plan.md` | Code vs brief conflicts still to fix |
