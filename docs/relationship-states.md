# Relationship states (user-facing)

Tentura uses a **directed trust relation** between people:

- **You trust them**: you have set trust toward this person (one-way).
- **They trust you**: they have set trust toward you (one-way).
- **Mutual trust**: you trust each other (two one-way links).
- **No trust relation**: neither direction is set.

## What the action does

On a profile, **“Trust this user”** means:

- **Confirmation**: not required (it applies immediately).
- **Direction**: one-way (you → them).
- **Notification**: not sent by this action.

## How to read the reciprocity label

Profile screens and person cards show a small trust label:

- **Mutual**: you trust each other.
- **One-way out**: you trust them.
- **One-way in**: they trust you.
- **None**: no trust relation.

## What changes after trusting someone

Trust can affect:

- **Network surfaces**: the person appears in your “friends/network” views (one-way relationship on your side).
- **Mutual trust**: a person only counts as “mutual trust” when both directions exist.
- **Forwarding suggestions**: Tentura uses your trust graph when suggesting who might help on a forwarded request. Mutual trust is a stronger routing signal than one-way trust.

Trust does **not** by itself let you open another person’s requests. You need an involvement path (forwarded to you, help offered, room admitted, etc.).

## Icons & graph legend

Avatars, graph nodes, and People lists reuse the same contact-badge chrome. Three signals are easy to confuse — keep them separate:

| Signal | What it means |
|--------|----------------|
| **Text label** (profile / People) | Vote-based reciprocity: mutual, one-way out, one-way in, none |
| **Two linked dots** | Vote mutual trust (`isMutualFriend`) |
| **Open / closed eye** | Bidirectional MeritRank (`score > 0` and `rScore > 0`, `isMutuallyVisible`); same gate as forward reachability — **not** the same as the text label or graph reachability |
| **Primary rating arcs** | Your rating toward them (`score`); separate from the eye |

The closed eye merges **one-way out**, **one-way in**, and **none**; use the text label when you need that distinction.

### Graph edge colors (mode-dependent)

**Trust graph** (undirected lines): gold touches you; blue other positive links; red negative. Lines show neighborhood hops, not vote direction.

**Forwards graph** (arrows sender → recipient): gold includes you; blue other forwards. Tertiary ring = active help offerer.

**Invite genealogy** (arrows inviter → invitee): gold your branch; green their branch; blue shared trunk. Count badge = unloaded invitees.

Open the in-graph **Legend** control on any graph screen for the full list.

## Blocking (separate from trust)

A person may be **hidden by a block**: from the blocker's perspective, a blocked person disappears from feeds, the trust graph, search, invite genealogy, and mutual-friends views. This is independent of and layered on top of the trust-relation states above. See [`features/user-block.md`](features/user-block.md) for full detail.
