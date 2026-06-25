# Watching mechanism (V1)

Product reference for **Watching** — triaged passive follow on forwarded beacons. Canonical home/inbox model: [`Tentura_current_status_quo.md`](Tentura_current_status_quo.md).

## Surfaces

| Surface | Meaning |
|--------|---------|
| **Inbox → Needs me** | Pending triage — needs a decision now. |
| **Inbox → Watching** | Triaged passive follow: not rejected, not offering help, not owning execution. |
| **Not for me** (archive) | Explicit rejection — opened from inbox overflow, not a third inbox tab. |
| **My Work** | Ownership: authored or active help offer. |

Home default tab is **My Work** (not Inbox).

## UX rules

- **Watching is secondary**, not a third primary action beside Forward and Not for me on the inbox card.
- Entry points: **overflow** (“Move to Watching”), **beacon detail**, and **automatic** after the user forwards **without** an active help offer.
- Use **neutral** visual treatment (muted / outline); not success green, not error red, not warning amber.

## Copy

- Use: **Move to Watching**, **Watching**, expanded tooltips: *Watching — not offered help*, *Watching — following, not handling*.
- Avoid: Bookmark, Save, Pending, Maybe later, Interested (hides social meaning).

## Stance model

Per-user stance for a beacon is stored per inbox row:

- **needs_me** — triage queue
- **watching** — passive follow
- **rejected** — not for me (archive)
- **closed_before_response** / **deleted_before_response** — terminal tombstones when the beacon ended before an explicit stance (see [`before-response-terminal-tombstone.md`](before-response-terminal-tombstone.md))

## Transitions

- **Into Watching:** user chooses Move to Watching; or user completes **forward** with **no active help offer** (sender row becomes watching).
- **Out of Watching (stronger actions):** offer help → My Work; not for me → archive; forward onward → recipient-visible **Forwarded** (precedence below).

**Return to Needs me** — Watching overflow may move the item back to triage.

## Recipient-visible state (forward list)

Upstream users see each recipient's **current** stance; strongest wins:

1. **Author**
2. **Help offered** (active offer)
3. **Withdrawn** — withdrew help offer
4. **Forwarded by me** — I already forwarded here (blocks re-selection; shows my note)
5. **Declined** — rejected the beacon
6. **Forwarded** (by others) — received or onward-forwarded; **selectable** for my forward
7. **Watching** — **selectable**
8. **Unseen** — **selectable**

## Non-goals (Phase 1)

- Third primary Watch button on every inbox card
- Watch notification settings, public profile watch counts, fine-grained follow levels
- **Evaluation:** Watching alone does **not** create evaluation eligibility — see [`beacon-evaluation-principles.md`](beacon-evaluation-principles.md).
