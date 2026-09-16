# Beacon visibility, content access, and forwarding — reference matrix

**Sources:** ADR 0008 (Amendment A), `beacon_can_read_content` (m0098, amended m0123), `beacon_visibility.dart`, profile GraphQL queries, `forward_case.dart`.

---

## Terminology

| Term | Definition |
|------|-----------|
| **Vote-mutual friend** | Both voted for each other: `vote_user.amount > 0` in both directions — used for profile labels and mutual-trust bridge queries; does **not** grant beacon read access |
| **One-way friend** | You voted for them (`myVote > 0`, `isFriend` in UI) — does **not** grant read access |
| **MR bidirectional** | MeritRank scores both ways (`src_score > 0` AND `dst_score > 0`) — controls **who appears in the forward picker**, not read access |
| **MR one-way ("sees me")** | They have positive MR toward you (`rScore > 0`, `isSeeingMe`) — used for one-way-in text labels only |
| **MR bidirectional visibility** | MeritRank both ways (`score > 0` AND `rScore > 0`, `isMutuallyVisible`) — open eye badge and per-recipient **reachability** gate in the picker |
| **Indirect / bridge friend** | You share a mutual friend with someone but are not vote-mutual with them — **no** content access |
| **Forward recipient** | Active (non-cancelled) `beacon_forward_edge` with `recipient_id = you` |
| **Forward sender only** | Active edge with `sender_id = you`, no other access path — **not** a read path |

> **MeritRank is never a read gate.** It gates who appears in the forward-to picker only.  
> See `CONTEXT.md` § Beacon visibility, ADR 0008.

---

## Content-read predicate

`beacon_can_read_content(beacon_id, viewer_id)` — the canonical enforcement point for **normal beacon content**, Hasura `beacon` select permissions (unchanged by nesting), and mutation gates such as forward, help offer, invitation, and fork.

| Condition | Content readable? |
|-----------|:-----------------:|
| Beacon is a **draft** and viewer is author | ✅ |
| Beacon is a **draft**, viewer is not author | ❌ |
| Beacon is **deleted** | ❌ (tombstone UX only) |
| Viewer is the **author** | ✅ |
| Viewer has an **active forward edge as recipient** | ✅ |
| Viewer has an active forward edge **as sender only** | ❌ |
| Viewer is a **steward** or **room-admitted participant** (`room_access = 3`) | ✅ |
| Viewer has an **active help offer** (`status = 0`) | ✅ |
| Vote-mutual or one-way friend of author (trust only) | ❌ |
| MR-connected (but not otherwise involved) | ❌ |
| Bridge / indirect friend | ❌ |
| **Parent member** (effective admission to parent) viewing **child** content (`contextChild` only) | ✅ |
| **Child member** viewing **parent** or other **ancestor** (`contextAncestor` only) | ✅ |

## Access level and reasons

Four access levels (0 author, 1 member, 2 observer, 3 stranger).
Reasons explain why a level-2 viewer sees a request; they drive UI copy
and some rights (see rights table). Canonical SQL: `beacon_access_level`,
`beacon_access_reasons` (bitmask); domain: `BeaconAccessPolicy` in
`packages/server/lib/domain/beacon_access_policy.dart`.

### Access-reason bitmask

| Bit | Value | Reason |
|---|---|---|
| 0 | 1 | author |
| 1 | 2 | steward (`beacon_steward` row, or participant `role = 1`) |
| 2 | 4 | admitted (participant `room_access = 3`) |
| 3 | 8 | forwarded (active inbound forward edge) |
| 4 | 16 | applied (active help offer, `status = 0`) |
| 5 | 32 | discovered (D11, trust-only) |
| 6 | 64 | contextChild (member of the immediate parent), from phase 2 |
| 7 | 128 | contextAncestor (member of some descendant), from phase 2 |

Access level: 0 author, 1 member, 2 observer, 3 stranger.
Level = 0 if bit 0; else 1 if bits 1-2; else 2 if bits 3-7; else 3.

### Rights by level and reason

| Right | L0 | L1 | L2 forwarded | L2 applied | L2 discovered | L2 context* | L3 |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| Read details, images, public facts | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ *(new)* | ❌ |
| Read room-only facts, discussion, Plan | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Apply (offer help), open-family only | — | — | ✅ | (already) | ✅ | ✅ *(new, D2)* | ❌ |
| Forward / invite, `allowsForward` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ *(new, D2)* | ❌ |
| Fork as lineage source | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ *(new, D2)* | ❌ |
| Involvement (forward chain, offerers, rejections) | ✅ | ✅ | ✅ | ✅ | ❌‡ | ❌‡ | ❌ |
| List children | ✅ | ✅ | ✅ filtered† | ✅ filtered† | ✅ filtered† | ✅ filtered† | ❌ |
| Create child | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Parent reference shown as a link | if level(parent) ≤ 2 | ← same | ← | ← | ← | ← | ❌ |

\* `contextAncestor` or `contextChild`.
† Children filtered per child by the same access function.
‡ Unless otherwise involved (e.g. forward sender).

Context observers (either context bit) get content read and D2 observer
operations; involvement stays closed unless separate involvement facts
apply.

---

## Profile surfaces

Three request-related lists appear on another user's profile (P):

| Surface | What it shows | List query |
|---------|--------------|-----------|
| **Requests I'm involved in** | Requests **authored by P** that were ever **forwarded to you** | `beacon_forward_edge` filter — nested beacon gated by `can_read_content` |
| **Shared › Forwarded** | Requests **you forwarded to P** | `beacon_forward_edge(sender = me, recipient = P)` — edge always visible; nested beacon data gated by `can_read_content` |
| **Shared › Co-help offered** | Requests where **both you and P** have active help offers | `beacon` filtered by both `help_offers(user_id = me)` AND `help_offers(user_id = P)` — again gated |

---

## Involvement → profile list / read / forward

The three profile surfaces + "open detail" + "can forward" for each relationship type.

"Beacon author" below may differ from profile owner P. Read rules are relative to the **beacon's author**, not P.

| Viewer's relationship | Requests I'm involved in (P-authored) | Shared › Forwarded | Shared › Co-help | Open detail (read content) | Can forward beacon |
|----------------------|:-------------------------------------:|:------------------:|:----------------:|:---------------------------:|:-----------------:|
| **Author of the beacon** | If forwarded to you | If you forwarded to P | If both offered | ✅ | ✅ open-family only |
| **Vote-mutual friend of author** | Only if forwarded to you | If you forwarded to P | If both offered | ❌ (trust alone) | ❌ |
| **One-way friend of author** (you→author, not mutual) | Only if forwarded to you | If you forwarded to P | If both offered | ❌ | ❌ |
| **MR bidirectional, not vote-mutual with author** | Only if otherwise involved | If you forwarded to P | If both offered | ❌ | ❌ |
| **Indirect / bridge friend** (mutual with P, not author) | Only P's own beacons if P = author and you're involved | If you forwarded to P | If both offered | ❌ (to third-party beacons) | ❌ |
| **Forward recipient** (active inbound edge) | If P = author | If you forwarded to P | If both offered | ✅ | ✅ open-family only |
| **Forward sender only** (outbound edge, no other path) | ❌ | Edge visible; beacon data ❌ if read lost | — | ❌ | ❌ |
| **Active help offerer** (`status = 0`) | If P = author | If you forwarded to P | ✅ by definition | ✅ | ✅ open-family only |
| **Withdrawn help offerer** | — | — | ❌ | ❌ | ❌ |
| **Steward** | If P = author | If you forwarded to P | If both offered | ✅ | ✅ open-family only |
| **Room-admitted participant** (`room_access = 3`) | If P = author | If you forwarded to P | If both offered | ✅ | ✅ open-family only |
| **Parent member, child not admitted** (`contextChild`) | If P = parent author | If you forwarded to child | — | ✅ on child as observer; no child discussion/Plan/involvement unless separately admitted or involved | ✅ on child, open-family only (D2) |
| **Child member, ancestor not admitted** (`contextAncestor`) | — | — | — | ✅ on child; ✅ on parent and other ancestors as observer; no ancestor discussion/Plan/involvement unless separately admitted or involved | ✅ on child and ancestors, open-family only (D2) |
| **Room participant, not admitted** | — | — | — | ❌ | ❌ |
| **Invite not yet accepted** | ❌ | ❌ | ❌ | Preview only (`canPreviewInvite`) | — |
| **After invite accepted** (creates forward edge) | — | — | — | ✅ (now a recipient) | ✅ open-family only |
| **Beacon is deleted** | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Beacon is draft** (non-author) | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Beacon is closed / cancelled** (you had a read path) | If you can still read | Same | Same | ✅ still readable | ❌ (`allowsForward` = open-family only) |

---

## Forwarding: two separate gates

### Gate 1 — can you forward this beacon at all?

Enforced server-side in `ForwardCase.forward`:

1. `canReadContent(viewer, beaconId)` — same predicate as the table above
2. `beacon.allowsForward` — lifecycle must be open-family: `open`, `needsMoreHelp`, or `enoughHelp`  
   (closed, wrapping-up/`reviewOpen`, cancelled, deleted, draft → no forward)

### Gate 2 — who can you forward it to?

The **recipient picker** shows users from `rating(where: { src_score > 0, dst_score > 0 })` — MeritRank bidirectional.

Per-candidate **selectability** (`ForwardCandidate.canForwardTo`):

- `isReachable` = `profile.isMutuallyVisible` (`score > 0` AND `rScore > 0`, i.e. MeritRank both ways)
- Excluded: already a forward recipient by you, author, help offerer, declined, withdrawn

| Relationship to recipient R | In picker? | Selectable? |
|-----------------------------|:----------:|:-----------:|
| MR bidirectional (`src > 0` AND `dst > 0`) | ✅ | ✅ unless already involved |
| MR one-way (you→them only) | ❌ | ❌ |
| Vote-mutual friend, MR below threshold | Maybe not in picker | ❌ if `rating` query returns no row |
| Already a forward recipient of yours | Maybe visible | ❌ |
| Author / help-offerer / declined | Maybe visible | ❌ |

---

## Known mismatches (QA traps)

| Situation | Profile UI suggests… | Reality |
|-----------|---------------------|---------|
| You forwarded to P, later lost read access | Forwarded card still shows | Tapping → **Beacon unavailable** (sender ≠ reader) |
| Vote-mutual with P, no forward/help path | Might expect to browse P's requests | **Requests I'm involved in** only lists forwards to you; trust alone does not open P's requests |
| MR-strong connection, no involvement with author | In forward picker | **Cannot open** author's beacons unless forwarded/help-offered |
| Friends tab `coInvolvedBeaconsCount` | "N shared beacons" badge | Uses involvement SQL without `can_read_content` — may over-count vs actually openable beacons |

---

## Open-family lifecycle (forwarding allowed)

| Status | `allowsForward` | Notes |
|--------|:---------------:|-------|
| `open` (0) | ✅ | |
| `needsMoreHelp` (7) | ✅ | |
| `enoughHelp` (8) | ✅ | |
| `reviewOpen` (5) | ❌ | Wrapping-up / evaluation window |
| `closed` (6) | ❌ | |
| `cancelled` (1) | ❌ | |
| `draft` (3) | ❌ (non-author) | Author can still publish |
| `deleted` (2) | ❌ | |

---

## Source files

| What | File |
|------|------|
| Content-read predicate (Dart) | `packages/server/lib/domain/beacon_visibility.dart` |
| Access policy (Dart) | `packages/server/lib/domain/beacon_access_policy.dart` |
| Content-read + reasons + level (SQL) | `packages/server/lib/data/database/migration/m0098.dart`, `m0123.dart`, `m0170.dart`, `m0171.dart` |
| Ancestor closure (SQL) | `packages/server/lib/data/database/migration/m0171.dart` |
| Drop linked-detail predicate (SQL) | `packages/server/lib/data/database/migration/m0172.dart` (history: added in `m0155.dart`) |
| Co-participant bond (SQL) | `packages/server/lib/data/database/migration/m0173.dart` (`person_bond`, `person_bond_peers`) |
| Hasura computed fields wiring | `packages/server/lib/data/database/migration/m0099.dart` |
| Product summary | `CONTEXT.md` § "Beacon visibility & sharing" |
| ADR | `docs/adr/0008-beacon-visibility-and-invite-sharing.md` |
| Profile involved-requests query | `packages/client/lib/features/beacon/data/gql/beacons_involved_with_author.graphql` |
| Profile shared-beacons query | `packages/client/lib/features/profile_view/data/gql/profile_shared_beacons_fetch.graphql` |
| Forward sender auth | `packages/server/lib/domain/use_case/forward_case.dart` |
| Forward recipient picker | `packages/client/lib/features/forward/data/gql/forward_candidates_fetch.graphql` |
| Per-recipient selectability | `packages/client/lib/features/forward/domain/entity/forward_candidate.dart` |
| Vote vs UI friend | `packages/client/lib/domain/entity/profile.dart` (`isFriend` vs `isMutualFriend`) |
