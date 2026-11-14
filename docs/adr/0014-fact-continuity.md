# ADR 0014: Fact continuity across Requests and Posts

## Status

Accepted (2026-11-12, owner decisions D1–D20 and review decisions R1–R6). Shipped
as epic tentura-zzla. Full design: [`docs/plans/fact-continuity-architecture.md`](../plans/fact-continuity-architecture.md).

## Context

A fact stays local to its episode (a Request or a Post, both `beacon`). Members
needed to carry a fact into another episode without leaking the source room and
without a canonical shared fact. The design had to reconcile these conflicts
(plan §3):

- A copy's history cannot continue the source's (it would leak source revisions and participants): D1.
- Request-visible vs discussion-only has no meaning on a Post: D5.
- ADR 0004 decision 8 (parent is a link, never a title) shapes the origin line: D6.
- ADR 0004 decision 2 (fork copies no room content; images only for the source author) is amended for facts: ticked facts are copied, a non-admitted forker is offered request-visible facts only, and fact images are always re-stored for the copier (D11).
- Saved facts vs "a fact belongs to exactly one episode": pointers only (D18).
- Pre-existing holes (fact history authorised by `beaconId` but queried by `fact_card_id`; unvalidated attachment JSON) were fixed first, in block P, before any copy code.
- Post writes are serialised with archiving by DB triggers; fact tables got a dedicated guard (block B).

Product principle: facts belong to episodes; provenance connects episodes; nothing is canonical.

## Decision

A copy is a new, independent fact that remembers its origin fact and revision.
Nothing is synchronised. Facts also work on Posts, and a personal list of saved
facts (pointers) feeds the chat fact picker.

### Owner decisions D1–D20

| # | Topic | Decision |
|---|---|---|
| D1 | History of a copy | The copy starts at **revision 1** holding only the copied text and images. Source revisions are **not** duplicated. Earlier history is reachable only through the origin link. |
| D2 | Who may copy | Anyone who can read the fact now, by the single access rule of §4.4. |
| D3 | Source room | Learns nothing: no chat line, no event, no notification, no counter in the source. |
| D4 | Visibility of a copy | Always lands **discussion-only**. Widening is the existing «Make public» action in the destination. |
| D5 | Facts on a Post | One visibility. Stored as discussion-only (`visibility = 1`). No «Make public / private» on a Post. |
| D6 | Origin line | Generic text «Brought from another Request» / «…Post». No source title, no source names. Shown to every reader of the copy. |
| D7 | Tapping the origin line | Opens the source fact if the viewer may read it; otherwise «The original isn't available to you». The same answer for hidden, unpinned and deleted sources. |
| D8 | Arrival at the source | Everyone sees the source's **current** text. If it changed since the copy, a note says so. Only members of the source discussion get «See the copied version» (opens history at that revision). |
| D9 | Chain | One hop at a time. A copy stores only its direct origin. No recursive query exists. |
| D10 | Duplicates | At most **one live copy per source fact per destination**. A second attempt answers «Already there» and returns the existing copy. After the copy is unpinned the fact can be copied again. |
| D11 | Images | Each image is re-stored as a new blob owned by the copier. All or nothing per fact. This **overrides** ADR 0004 decision 2 for facts (that decision duplicates images only when the forker is the source author). |
| D12 | Push destinations | Published episodes the actor may write facts in, **plus the actor's own drafts** (Requests and Posts). No «New Request / New Post» rows in the picker. |
| D13 | Drafts | A fact copied into a draft exists at once (snapshot fixed). No chat line until publish; publish writes one grouped line. |
| D14 | Fork | The fork sheet gets a «Facts to bring» checklist, nothing ticked. |
| D15 | Budding | The bud form gets the same checklist, nothing ticked. Works from an archived Post. |
| D16 | Chat line | New system line «X brought a fact from another Request», grouped for several facts. |
| D17 | Post UI | Facts are pinned and picked in the Post's Chat and **listed in the Post info sheet**. See R6: there is no facts strip in any room today. |
| D18 | Saved facts | A saved fact is a **pointer** (user id + fact id). The list shows the fact's current text, checked against the viewer's current rights. Unreadable, unpinned or deleted rows show «No longer available». |
| D19 | Picking a saved fact | Copies it into the current episode (D4, D10 apply) and attaches it to the message being written as a quote. |
| D20 | Managing saved facts | «Save to my facts» / «Remove from my facts» in the fact actions sheet; the «Saved» tab is the only list. Cap 200. No separate screen. |

### Review-driven decisions R1–R6

| # | Question raised by the review | Decision |
|---|---|---|
| R1 | A ticked fact is unavailable when fork or bud runs. | Skip it; never fail the fork or bud. This includes a fact whose image copy hits the daily upload cap. `BeaconFactCardCopy` (one fact) still throws. |
| R2 | A fact's image row is already gone, or the attachment is not an image. | Drop that attachment from the copy; copy the rest. |
| R3 | A Post message pinned as a fact is rejected as a bud source today (`BeaconPromotionEligibilityPolicy`), including the root message. | Relax the rule for Post parents: on a Post the source is prefill only and binds nothing. |
| R4 | Saved row whose source was hard-deleted vs unpinned. | No foreign key on the saved fact id, so both show «No longer available» (no distinguishable signal). |
| R5 | Fact writes on a draft (pin, edit, restore, visibility) already write chat lines into an unpublished room. | Reject them on a draft. A draft accepts only copy-in and remove. |
| R6 | D17 was chosen on a mockup with a facts strip at the top of the Chat. No such strip exists. | No new strip. Post facts are reached from the info sheet list, the pinned-message mark, and the fact picker. |

## Consequences

- Facts on Posts have one visibility (discussion-only); copies always land discussion-only.
- Every reader of a copy sees a generic origin line; only readers of the source can follow it.
- The source room learns nothing about copies.
- A blocked but admitted Request participant loses fact history and fact writes (single SQL access function, stricter than `RoomAccessPolicy.canUseRoom`).
- Fact images are re-stored per copy and count against the copier's daily upload cap.
