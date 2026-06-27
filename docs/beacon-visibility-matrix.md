# Beacon visibility, content access, and forwarding — reference matrix

**Sources:** ADR 0008, `beacon_can_read_content` (m0098), `beacon_visibility.dart`, profile GraphQL queries, `forward_case.dart`.

---

## Terminology

| Term | Definition |
|------|-----------|
| **Vote-mutual friend of author** | Both voted for each other: `vote_user.amount > 0` in both directions — the only friendship type that grants beacon read access |
| **One-way friend** | You voted for them (`myVote > 0`, `isFriend` in UI) — does **not** grant read access |
| **MR bidirectional** | MeritRank scores both ways (`src_score > 0` AND `dst_score > 0`) — controls **who appears in the forward picker**, not read access |
| **MR one-way ("sees me")** | They have positive MR toward you (`rScore > 0`, `isSeeingMe`) — per-recipient **reachability** gate in the picker |
| **Indirect / bridge friend** | You share a mutual friend with someone but are not vote-mutual with them — **no** content access |
| **Forward recipient** | Active (non-cancelled) `beacon_forward_edge` with `recipient_id = you` |
| **Forward sender only** | Active edge with `sender_id = you`, no other access path — **not** a read path |

> **MeritRank is never a read gate.** It gates who appears in the forward-to picker only.  
> See `CONTEXT.md` § Beacon visibility, ADR 0008.

---

## Content-read predicate

`beacon_can_read_content(beacon_id, viewer_id)` — the single enforcement point used by Hasura `beacon` select permissions and the V2 access guard.

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
| Viewer is **vote-mutual friend of the author** | ✅ (all author's non-draft, non-deleted beacons) |
| One-way friend of author | ❌ |
| MR-connected (but not vote-mutual with author) | ❌ |
| Bridge / indirect friend | ❌ |

---

## Profile surfaces

Three beacon lists appear on another user's profile (P):

| Surface | What it shows | List query |
|---------|--------------|-----------|
| **Show Beacons** | All beacons **authored by P** that you can read | `beacon(where: { user_id: P, status ∈ … })` — Hasura gates each row by `can_read_content` |
| **Shared › Forwarded** | Beacons **you forwarded to P** | `beacon_forward_edge(sender = me, recipient = P)` — edge always visible; nested beacon data gated by `can_read_content` |
| **Shared › Co-help offered** | Beacons where **both you and P** have active help offers | `beacon` filtered by both `help_offers(user_id = me)` AND `help_offers(user_id = P)` — again gated |

---

## Involvement → profile list / read / forward

The three profile surfaces + "open detail" + "can forward" for each relationship type.

"Beacon author" below may differ from profile owner P. Read rules are relative to the **beacon's author**, not P.

| Viewer's relationship | Show Beacons (P-authored) | Shared › Forwarded | Shared › Co-help | Open detail (read content) | Can forward beacon |
|----------------------|:-------------------------:|:------------------:|:----------------:|:---------------------------:|:-----------------:|
| **Author of the beacon** | Yes (own) | If you forwarded to P | If both offered | ✅ | ✅ open-family only |
| **Vote-mutual friend of author** | ✅ all of author's beacons, when author = P | If you forwarded to P | If both offered | ✅ | ✅ open-family only |
| **One-way friend of author** (you→author, not mutual) | Only if you are otherwise involved | If you forwarded to P | If both offered | ❌ | ❌ |
| **MR bidirectional, not vote-mutual with author** | Only if otherwise involved | If you forwarded to P | If both offered | ❌ | ❌ |
| **Indirect / bridge friend** (mutual with P, not author) | Only P's own beacons if P = author and you're involved | If you forwarded to P | If both offered | ❌ (to third-party beacons) | ❌ |
| **Forward recipient** (active inbound edge) | If P = author | If you forwarded to P | If both offered | ✅ | ✅ open-family only |
| **Forward sender only** (outbound edge, no other path) | ❌ | Edge visible; beacon data ❌ if read lost | — | ❌ | ❌ |
| **Active help offerer** (`status = 0`) | If P = author | If you forwarded to P | ✅ by definition | ✅ | ✅ open-family only |
| **Withdrawn help offerer** | — | — | ❌ | ❌ | ❌ |
| **Steward** | If P = author | If you forwarded to P | If both offered | ✅ | ✅ open-family only |
| **Room-admitted participant** (`room_access = 3`) | If P = author | If you forwarded to P | If both offered | ✅ | ✅ open-family only |
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

- `isReachable` = `profile.isSeeingMe` (`rScore > 0`, i.e. they score you positively)
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
| One-way "friend" of profile owner P | **Show Beacons** button always visible | List **empty** unless vote-mutual with P or otherwise involved |
| MR-strong connection, no vote mutual with author | In forward picker | **Cannot open** author's beacons unless forwarded/help-offered |
| Vote-mutual with P; beacon authored by stranger C | Co-help section if both offered on C | Co-help reads ✅; Show Beacons shows **P's own** beacons only |
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
| Content-read predicate (SQL) | `packages/server/lib/data/database/migration/m0098.dart` |
| Hasura computed fields wiring | `packages/server/lib/data/database/migration/m0099.dart` |
| Product summary | `CONTEXT.md` § "Beacon visibility & sharing" |
| ADR | `docs/adr/0008-beacon-visibility-and-invite-sharing.md` |
| Profile "Show Beacons" query | `packages/client/lib/features/beacon/data/gql/beacons_fetch_by_user_id.graphql` |
| Profile shared-beacons query | `packages/client/lib/features/profile_view/data/gql/profile_shared_beacons_fetch.graphql` |
| Forward sender auth | `packages/server/lib/domain/use_case/forward_case.dart` |
| Forward recipient picker | `packages/client/lib/features/forward/data/gql/forward_candidates_fetch.graphql` |
| Per-recipient selectability | `packages/client/lib/features/forward/domain/entity/forward_candidate.dart` |
| Vote vs UI friend | `packages/client/lib/domain/entity/profile.dart` (`isFriend` vs `isMutualFriend`) |
