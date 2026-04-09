# Watching mechanism (V1 Phase 1)

Condensed product + implementation reference. Full narrative rationale lives in the original design brief; this file is the **canonical** summary for agents.

## Surfaces

| Surface | Meaning |
|--------|---------|
| **Inbox (Needs me)** | Pending triage — needs a decision now. |
| **My Work** | Ownership: authored or committed. |
| **Watching** (inbox tab) | Triaged passive follow: not rejected, not committed, not owning execution. |
| **Not interested** (rejected tab) | Explicit “not for me”. |

## UX rules

- **Watching is secondary**, not a third primary action beside Forward and Not for me on the inbox card.
- Entry points: **overflow** (“Move to Watching”), **beacon detail**, and **automatic** after the user forwards **without** an active commitment.
- Use **neutral** visual treatment (muted / outline); not success green, not error red, not warning amber.

## Copy

- Use: **Move to Watching**, **Watching**, expanded tooltips: *Watching — not committed*, *Watching — following, not handling*.
- Avoid: Bookmark, Save, Pending, Maybe later, Interested (hides social meaning).

## Data model (current)

Per-user stance for a beacon: Postgres **`inbox_item`** keyed `(user_id, beacon_id)` with **`status`**: `0` = needs_me, `1` = watching, `2` = rejected.

Optional future: audit columns or timeline events (`entered_watching_at`, `source_of_transition`) — not required for Phase 1 acceptance.

## Transitions

- **Into Watching:** user chooses Move to Watching; or user completes **forward** and has **no active commitment** on that beacon (server sets sender row to watching).
- **Out of Watching (stronger actions):** commit → My Work; not for me → rejected; forward onward → recipient-visible state becomes **Forwarded** (precedence below); personal Watching list may still show the beacon until product adds stricter rules.

## Recipient-visible state (forward list)

Upstream users see each recipient’s **current** stance with deterministic precedence (strongest wins):

1. Committed (active commitment)
2. **Forwarded** — user has sent at least one forward edge for this beacon (`onwardForwarderIds` / sender on `beacon_forward_edge`)
3. Not for me (rejected)
4. **Watching** (`inbox_item.status = 1`)
5. Received forward (legacy “already forwarded” / in `forwardedToIds`) vs unseen — client continues to distinguish as today

## Return to Needs me

The Watching-tab overflow may offer **Return to Needs me** (moves `status` back to `0`) for users who want the item back in the triage queue. This is weaker than “stronger stance” overrides above.

## Non-goals (Phase 1)

- Third primary Watch button on every inbox card
- Watch notification settings, public profile watch counts, fine-grained follow levels
- **Evaluation:** Watching alone does **not** create evaluation eligibility — see [`../beacon-evaluation-feature-design.md`](../beacon-evaluation-feature-design.md).

## Code touchpoints

- Client inbox: `inbox_item` via Hasura; `InboxCubit` / `InboxItemTile`.
- Server forward: V2 `beaconForward` — also updates sender `inbox_item` when appropriate.
- Forward screen involvement: V2 `beaconInvolvement` — includes `watchingIds`, `onwardForwarderIds` (see server GraphQL types).
