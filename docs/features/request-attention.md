# Request attention — obligations, updates and the clearing ritual

**User-facing:** what appears on **My desk** and **For you**, why a Request is on one of them and not the other,
what the dot and the number mean, and how a person brings a surface back to zero.

**Status.** This is the durable product contract for Request attention. It governs new work and reviews.
Parts of it are already implemented, parts are not; the implementation state and the route from here are tracked
in [`docs/plans/request-centric-attention-plan.md`](../plans/request-centric-attention-plan.md) (revision 3).
Where this document and any plan disagree, this document states the intent and the plan states the schedule.
Where this document and the code disagree, the code is a defect or the feature is unshipped — check the plan
before assuming either.

Terminology: user-facing **Request** is internal `Beacon`; **My desk** is `my_work`; **For you** / Activity is
`inbox`. See [`CONTEXT.md`](../../CONTEXT.md) § My desk.

---

## 1. One Request, one primary surface

A Request is on exactly one primary surface for a given viewer, derived from that viewer's relationship to it:

```
responsible(viewer, request) =
      authored, any status except draft (archived included)
   OR holds an active help offer
   OR holds at least one authorized live obligation

primary surface = responsible ? My desk : For you
```

The surface is **derived when read, never stored**. Offering help moves a Request from For you to My desk;
withdrawing moves it back. On overlap, My desk wins.

**Invariant:** live events about a Request appear under that Request, on its primary surface, and nowhere else.
There is exactly one deliberate exception, §7.

_Avoid:_ storing a surface on a receipt; deciding placement from the event's type or its deep-link target instead
of from responsibility; showing the same live Request on both tabs.

## 2. Two classes of event

| | **Obligation** | **Optional update** |
|---|---|---|
| Meaning | somebody is waiting on this person | something happened they may want to know |
| Indicator | **number** | **dot** |
| Control | a **CTA** that captures a decision | a **×** that clears it |
| Leaves when | the underlying domain transition happens | the person clears it, or opens the Request |
| Lives on | My desk only | either surface |

Obligations can only exist on My desk: holding one is itself a reason the Request is on My desk. For you
therefore never shows a number.

A pinned unanswered forward is an **invitation**, not an obligation — it waits for a decision but nobody is owed
work. It is not counted, and it is not swept (§7).

_Avoid:_ promoting "important" or mandatory-delivery notifications into obligations; classifying by event type
alone — the same event is an obligation for one recipient and an optional update for another (a help offer
obliges the author, informs everybody else).

## 3. Three independent states

```
read:       unseen   → seen                       reading, in History or in a discussion
cleared:    uncleared → cleared                   an explicit × , or opening the Request
settled:    live     → resolved | superseded | expired    a domain transition
```

These never substitute for one another:

- reading something never clears it and never settles it;
- clearing never settles — a swept surface does not mean work was done;
- settling removes an obligation even if its receipt was never read;
- marking something unread in History never resurrects attention on a primary surface.

_Avoid:_ using "seen" as the storage for "cleared"; inferring settlement from a row disappearing from a surface.

## 4. Clearing

**Gestures.**

| Control | Clears |
|---|---|
| × on an event | that one optional event |
| × on a Request card | that card's optional events and its outcome notice; obligations and the Request remain |
| Opening the Request | the optional events captured at the moment it opened |
| **Dismiss all** (For you) | every row on the surface that carries its own × |

**Boundaries.**

- Clearing is always the result of a deliberate gesture. Scrolling, rebuilding, switching tabs, background
  refreshes and previews clear nothing.
- Opening a Request clears a **snapshot** taken when it opened, after it successfully displays — so an event that
  arrives while the person is reading survives, and a failed or forbidden navigation clears nothing.
- Opening a child Request clears the child only.
- Opening a review deep link clears that Request's optional updates and leaves the review obligation live.
- Reaching the bottom of a discussion marks its messages **read**; under §3 that is not clearing.
- **Dismiss all never applies a decision on the person's behalf.** It skips unanswered forwards, pending prompts
  and anything else awaiting a choice, and it never touches obligations.
- Clearing a card never archives the Request, never withdraws help, never leaves Watching and never touches
  review data.
- An explicit dismissal can be undone for a short window; undo never reverses somebody else's action, and never
  reverses accepting help, submitting a review, or an expiry.

**What "cleared" looks like.** Because Dismiss all leaves decisions alone, a cleared For you can still show its
pinned zone. Three states must read differently: *nothing here*, *nothing new* (cleared — the decision zone may
still be there), and *nothing matching this filter*.

_Avoid:_ a sweep that silently rejects forwards or skips prompts; celebrating "all clear" while decisions are
pending, while loading, offline, or after a partial sweep; clearing that only covers the rows currently loaded on
screen.

## 5. Obligations

Every obligation kind ships with:

1. a **CTA that captures a decision** — a sheet or popup asking for a choice or an input;
2. the **domain transitions** that resolve it;
3. a **decline path**, where the domain allows one, that is truthful to the person waiting.

**There is no bare "Done".** Nothing in the product can be honestly resolved by acknowledgment: responding to a
help offer requires a response, submitting a review requires a package. A proposed obligation that would need a
bare Done button is an optional update wearing the wrong clothes.

Opening a CTA, cancelling the sheet, failing to navigate, or saving an unsent draft resolves nothing.

**Review obligations are not declinable.** Reviews end by sending the package, by the window closing, or by the
author cancelling. This is a standing domain rule, not an oversight.

**Nothing disappears unexplained.** When an obligation ends by expiry or cancellation rather than by the person's
action, it is replaced by an optional update saying so, which the person then clears. A number that falls on its
own with no explanation destroys trust in the number.

_Avoid:_ an obligation with no exit at all — it pins the badge forever and turns the count into wallpaper;
dismissing an obligation privately, which lies to whoever is waiting.

## 6. Order and indicators

**Order.**

- A new obligation promotes its Request to the top of **Needs you**.
- An optional update changes a dot, a preview and an event list — never a position.
- A Request entering a surface establishes its place then; it keeps it.
- Explicit actions may move things between zones (rejecting a forward unpins it; restoring repins it). That is a
  state change, not a bump.

**Indicators.**

```
request.dot   = has at least one uncleared optional event or uncleared outcome
request.count = number of live obligations on it

my desk.dot   = any owned Request has a dot          my desk.count = sum of request.count
for you.dot   = any dismissible attention, pending forward or pending prompt
for you.count = never
```

Dot and number are independent: a Request with both shows both, and a tab shows its dot whether or not it also
shows a number. Indicators do not hide because the tab is currently open.

**One predicate.** The rule deciding what a list shows by default and the rule behind its indicator are the same
rule, implemented once. A tab that lights up and then shows nothing to act on is the failure this prevents:
whatever is counted must be reachable — including archived Requests, whose attention lights the tab only if the
Archive filter actually exposes it.

_Avoid:_ reusing event totals, forward-sender counts or page lengths as a badge; counting Request cards where the
contract counts obligations.

## 7. Forwards, outcomes and prompts

- An **unanswered forward** stays pinned at the top of For you regardless of age, until the person decides.
- Once answered — help offered, forwarded on, watched, rejected — it leaves the pinned zone and remains as a
  dated **outcome row** in the stream.
- **Outcome rows are dismissible** (×). They never bump, never group, carry no sub-cards and no dot. They are a
  trace of the person's own past action, not a second attention object.
- A "You're helping" outcome is the one deliberate exception to §1: the Request's live attention is on My desk
  while a dated trace of the decision stays in For you. Removing that trace entirely is a possible future
  simplification; until then it must always be dismissible, or the surface can never reach zero.
- Rejecting keeps a **Not interested · Restore** row; restoring re-pins the forward.
- Watching is a **collection of stances**, reachable from For you's overflow menu. Clearing a watched Request's
  updates never stops watching, and the collection never depends on unread events to stay reachable.

_Avoid:_ a residue of undismissable rows — a surface that cannot reach zero has no ritual, and the dot stops
meaning anything.

## 8. Child Requests and reviews

- A **child Request is its own attention object**. Creating one leaves a single optional notice on its direct
  parent; everything that happens inside the child belongs to the child.
- Hierarchy notices propagated to ancestors are **timeline-only**: they appear in the Request's log without a
  dot, a count or an effect on order.
- **Review events follow the ordinary rules**: actionable review work is an obligation on the Request;
  informational review updates are optional updates on that same Request. Reviews are never a separate inbox.

_Avoid:_ child activity bumping or lighting up the parent; a review living anywhere other than on its Request.

## 9. History, timeline and what survives clearing

- **Notification history** is the separate, complete, chronological receipt log across both surfaces, with search.
  It is not a primary surface, and its read/unread controls stay inside it.
- The **Request's timeline** shows what happened on that Request, including the viewer's own authorized receipt
  history. Personal receipts are never published into shared room activity.
- **Clearing is not deletion.** Cleared and resolved records are retained; retention never removes a live
  obligation or an uncleared update.
- Every event type must declare **where its content survives** after clearing. A type whose content exists
  nowhere else either cannot have clearing as its only exit, or is exempt from retention deletion.
- Honest limitation: events lost before this model existed — overwritten by collapse or removed by the old
  retention rule — are not reconstructed.

_Avoid:_ promising "it's always in the log" without checking that the type actually has a durable home.

## 10. What every new event type must declare

Before a new event type ships, it declares — per recipient role, not per type:

| | |
|---|---|
| scope | Request-scoped or account-scoped |
| recipient predicate | the exact role/reason condition for this variant |
| class | obligation or optional update |
| placement | primary attention or timeline-only |
| group key | the Request, for every Request-scoped event |
| action | for obligations: the decision-capturing CTA and its target |
| logical task key | for obligations: stable identity plus lifecycle generation |
| resolution | the domain transitions that settle it |
| clear policy | for optional updates: explicit × and/or open; obligations may not declare one |
| ordering effect | new obligations promote; optional updates never do |
| recoverable via | where the content survives clearing |
| tests | executable producer and transition coverage |

This is machine-enforced: [`docs/contracts/updates-event-contract.json`](../contracts/updates-event-contract.json)
plus the architecture tests in `packages/server/test/architecture/` and `packages/client/test/architecture/`.
Enum coverage is exhaustive — a runtime event type with no declaration fails the build, and there is no implicit
"optional by default" fallback.

## 11. Change control

- Product intent lives here. Schedules, unit breakdowns and migration mechanics live in
  [`request-centric-attention-plan.md`](../plans/request-centric-attention-plan.md).
- This document supersedes the allocation and indicator rules in
  [`new-stuff-indicators.md`](new-stuff-indicators.md) (written for the retired client-side marker mechanism) and
  refines decisions D1–D13 of
  [`work-activity-redesign-plan.md`](../plans/work-activity-redesign-plan.md), which remains the record of the
  shipped responsibility split.
- Changing any rule here is a product decision: record it here first, then in the plan, then in code.
