# Request-centric attention — obligations, optional updates and the clearing ritual

Status: design plan, **revision 2**. Owner decisions are closed (§4); §1 is rebuilt from code at HEAD with
`file:line` evidence after an independent Astra review rejected revision 1's baseline.

Date: 2026-09-18. Baseline: `feb2667a9` on `feature/events_refac` (identical to local `main`).

Scope: the lifecycle of request-scoped events on **My Work** and **For You**, the clearing ritual that brings
those surfaces to zero, and the indicator arithmetic that drives the nav badges. Issues
[#151](https://github.com/Intersubjective/tentura/issues/151) and
[#179](https://github.com/Intersubjective/tentura/issues/179), both under
[#142](https://github.com/Intersubjective/tentura/issues/142).

**What revision 2 changes.** Revision 1 sized its units against a baseline taken from the
`work-activity-redesign` release journal (2026-09-14) instead of from code, and missed two days of shipped work.
Corrected below; the practical effect is that **#151 is substantially already implemented**, the grouping and
pagination units are deleted, and the remaining delta is the event *lifecycle*, not the event *layout*.
Every §1 row is verified first-hand.

---

## 1. Verified baseline

### 1.1 Already shipped — do not rebuild

| Claim | Evidence | Consequence |
|---|---|---|
| For You already coalesces events per Request and orders groups by latest event | `75ce02327` (2026-09-16, ancestor of HEAD); `attention_repository.dart:292-306` (`activity_child_receipts`, `beacon_activity_stats` with `MAX(created_at)`, `event_total`, `event_unseen_count`); synthetic `item_kind = 'requestActivity'` at `:451` | **#151's core is done.** No grouping unit, no pagination rewrite |
| Sub-cards render on ordinary Request rows, not only pinned forwards | `activity_stream_view.dart:889` (`requestActivity` case) and `:915` (`ActivityEventSubcardBlock`); `activity_forward_row.dart:71-85` | Revision 1's "sub-cards only on pinned offers" was false |
| My Work already renders obligation sub-cards with per-kind CTAs | `my_work_obligation_block.dart:136-152` (`_ObligationSubCard`, `onRespondHelpOffer`, `onReview`, `onDone` → `settleObligations`) | **#179 is mostly wiring, possibly already satisfied** — needs gap analysis, not a build |
| Watching has a permanent, event-independent entry point | `inbox_screen.dart:313` overflow → `openInboxWatchingArchive` | Revision 1's E29 solved a non-existent gap; **dropped** |
| Group aggregates already count the whole group, not the preview | `attention_repository.dart:303-304` | Owner's requirement already holds; keep it, test it |
| A dismissal mechanism already exists end to end | `InboxCase.dismissTombstone:125` → `inbox_repository.dart:241` → `tombstone_dismissed_at`; SQL `dismissed_tombstone` CTE at `attention_repository.dart:286-290` excludes dismissed rows | The ritual extends an existing path instead of inventing one |
| Durable occurrence / recipient-snapshot / delivery topology exists | m0121 (`attention_occurrence`, `attention_occurrence_recipient`, delivery tables); written by `attention_dispatch_repository.dart:93` | The "Updates v1 boundary excludes occurrences" framing is obsolete and is **removed** from this plan |
| Explicit mark-seen / mark-unseen affordances exist | `updates_feed_tile.dart:88-150` (overflow, secondary tap, hover toolbar; never long-press alone) | The ritual reuses this interaction vocabulary |
| Batch + optimistic primitives exist | `attentionMarkSeen(ids)`, `markSeenForBeacon:1212`, `markAllSeen`, `attention_ack_store.dart` | No new transport work |

### 1.2 Constraints discovered — these shape the design

| Fact | Evidence | Why it matters |
|---|---|---|
| `seen_at` is **not** purely an explicit user act: reaching the bottom of a room advances it | `room_cubit.markReadToBottom:536` → m0120 `bridge_attention_room_seen` | "Never a viewport side effect" is already false. Either keep this as a declared exception or split dismissal from read state (§4 E9) |
| Collapse **rewrites `created_at = now()`** and **rewrites `requires_action`** on the surviving row | `attention_dispatch_repository.dart:126-147` (`ON CONFLICT (dedup_key) WHERE seen_at IS NULL DO UPDATE SET … requires_action = EXCLUDED.requires_action, created_at = now()`) | (a) a wall-clock "clear everything older than my tap" watermark has no stable axis; (b) **an optional event can become an obligation in place**, so classification cannot be a static per-type constant |
| `requires_action` is **role-dependent**, not type-dependent | `attention_policy.dart:277-283`: `helpOfferSubmitted` requires action only for `authorOfBeacon` | Classification key must be (event type × recipient role × state) |
| `markUnseen` refuses restoration when an unseen sibling shares the dedup key | `attention_repository.dart:1141-1147` | Unconditional undo is not implementable as promised; must become conditional (§4 E10) |
| Seen + emailed receipts are eligible for retention deletion | `notification_outbox_repository.deleteSettledOlderThan:118` | "Always recoverable in the log" is false for the receipt itself; recoverability must be proven per class (§6) |
| `reviewOpened` obligations are deliberately **not** user-settleable, and skipping a review was deliberately removed | `attention_settlement_case.dart:30-40`; `evaluation_case.evaluationSkip:1623` throws "Skip is no longer supported" | "Every obligation has a decline path" would reopen a closed domain decision (§4 E15) |
| Child→parent attention is produced by the **producer**, not by grouping | `beacon_hierarchy_outbox_repository.dart:148`; `beacon_hierarchy_delivery_case.dart:164` emits an intent for the destination (parent) Request | "Different keys make propagation impossible" was wrong; R7 needs a producer-policy decision |
| Trust events are Request-scoped | `attention_intent_case.dart:412,461` both set `beaconId` | They must not be regrouped under a person; object-key extraction is per producer, not per category |
| The event contract covers 15 of 29 runtime event types | `docs/contracts/updates-event-contract.json` vs `attention_models.dart:9-40` | A guard that only validates existing rows cannot enforce "every future event type" |
| There is no client-side Drift cursor for the attention feed | `FeedSessionRegistry` holds pages; cursor encoding lives in `query_attention.dart` | Revision 1's "migrate the Drift cursor" unit is deleted |
| The arrival pill and scroll anchoring serve the offers cubit; the ordinary stream replaces loaded items on head refresh | `activity_stream_view.dart:87`; `attention_case.dart:602-604` | Any reordering/staging rule must name an owner for displayed order — it cannot be assumed inherited |

### 1.3 Net remaining delta

1. **Event lifecycle**: the two classes, their exits (dismiss / CTA / decline / expiry), and what those exits do.
2. **Reachable zero**: tombstones and residue that cannot currently be removed; a surface-level sweep.
3. **Classification contract** as (type × role × state), reconciled with all 29 runtime event types.
4. **Recoverability**: making "it's still in the log" true, per class, against retention.
5. **Indicators**: dot/count arithmetic and the filter-scope rule.
6. **#179 gap analysis** against what `my_work_obligation_block.dart` already renders.
7. **#151 verification**, not construction.

---

## 2. Product model

**R1.** A Request belongs to exactly one primary surface: **My Work** if the viewer authored it, holds an active
help offer, or has a live obligation; **For You** otherwise. Derived server-side at read time (`v.surface`).

**R2.** Live request-scoped events are never split across surfaces.

**R3.** Events for one Request coalesce into that Request's card.

**R4.** Two classes: **obligations** (`requires_action` for *this recipient*, right now) and **optional updates**.

**R5.** Obligations exist only on My Work — holding one is itself a My Work scope criterion. A pinned forward is
an invitation, not an obligation, so For You stays dot-only.

**R6.** Both classes leave the surface when resolved, and remain retrievable through a durable route defined per
class (§6) — not through a blanket "it's in the log" promise.

**R7.** A child Request is its own attention object. Parent-scoped notices about a child are a **producer**
decision (§4 E5) and are non-bumping.

**R8.** Review events obey R4: actionable review work is an obligation; informational review updates are optional.

**R9.** Unanswered forwarded Requests stay pinned at the top of For You.

**R10.** The surfaces must be **reachable to zero** and stay there until something real happens. Any row that
cannot be cleared by any gesture is a defect against this rule.

---

## 3. Decision status against revision 1

| rev 1 | rev 2 |
|---|---|
| E1 one surface, server-derived | **kept** |
| E2 tombstones non-dismissible | **reversed** (owner, 2026-09-18): tombstones get a × |
| E3 per-surface bump rule | **kept, tightened** (bumping vs ordering timestamps separated) |
| E4 object key | **kept, narrowed**: per-producer extraction; trust events stay Request-scoped |
| E5 child rule via key | **replaced**: producer-policy decision, keys alone do not prevent propagation |
| E6 For You ephemeral | **kept** |
| E7–E12 optional lifecycle | **kept**, plus room-read exception and "Dismiss all" |
| E13–E18 obligation lifecycle | **kept except E15**, which is exempted for review obligations |
| E19–E21 indicators | **kept** |
| E22 Drift cursor migration | **dropped** (no such cursor) |
| E23–E27 pagination/races | **re-scoped**: grouping already ships; only clearing-boundary and staging rules remain |
| E28/E30 recoverability | **strengthened into §6**, now a proof obligation, not an assertion |
| E29 Watching entry point | **dropped** (already exists) |
| E31 zero state | **kept** |
| E32 dismiss mechanics | **kept** |

---

## 4. Decisions

### 4.1 Optional updates

**E7. Clearing is an explicit gesture (×), private and silent.** No clearing from scroll, viewport or expansion.

**E8. Opening the Request clears its optional events.** Reading for real is a stronger signal than a checkbox.

**E9. Storage reuses `seen_at`, with one declared exception.** At the domain level it means *dismissed* for
optional receipts. The existing room-read bridge (m0120) stays: reaching the bottom of a discussion dismisses that
discussion's message receipts, because the user demonstrably read them. This exception is written into the product
doc rather than quietly contradicted, and it is the **only** passive path permitted.

**E10. Undo is conditional, and its failure mode is benign.** `markUnseen` refuses restoration when an unseen
sibling shares the dedup key (`attention_repository.dart:1141`). That is acceptable: if undo is refused, a newer
unseen sibling is already lighting the dot, so no information is hidden from the user. Undo therefore promises
*"restore unless the group is already lit again"*, the affordance reports refusal honestly, and clearing returns
an operation token with the affected receipt versions.

**E11. Coalesce same-kind events into one dismissible line**, plus "Clear all on this Request" in the card header
and a surface-level **"Dismiss all"** on For You.

"Dismiss all" clears **optional events and tombstones**. It must never touch:
- **unanswered pinned forwards** — they are social invitations; silently clearing one answers a person by not
  answering them;
- **obligations** — they leave only through their CTA, their decline path, or expiry.

On My Work the equivalent control clears dots and leaves the count untouched.

**E12. Collapsed cards still expose clearable lines** (1–3 coalesced lines with reachable ×; expansion only for
"ещё N"), so the common case is one gesture per Request.

### 4.2 Tombstones (revised by owner)

**E2. Tombstones are not attention objects, but they are dismissible.** Demoted forward rows stay (removing them
would make the action feel like the item was lost), remain non-bumping, non-grouped, sub-card-free and
dot-free — **and carry a ×**.

A tombstone that cannot be removed is permanent sediment on a surface whose whole promise (R10) is reachable zero:
the user performs the entire ritual and is left with a residue composed mostly of their own past actions replayed
as news. That is the "2000 unread" failure that E15 correctly prevents for obligations, re-entering through the
tombstone door, and it would make the E31 reward unreachable.

This is already a live defect: `activity_forward_row.dart:55-69` gives a trailing action only for `notInterested`
(Restore) and `closedBeforeResponse` / `deletedBeforeResponse` (Hide) — `helping` and `watching` fall into
`default: trailingAction = null` and can never be removed. The mechanism exists and is simply not wired for those
outcomes (`dismissTombstone` → `tombstone_dismissed_at`, already honoured by the `dismissed_tombstone` CTE).
Extend it to every outcome behind a uniform ×, keeping `Restore` for `notInterested` as a secondary action.

### 4.3 Obligations

**E13. Obligations have no ×; they carry a per-kind CTA**, which may resolve inline (including via a bottom sheet
raised from the card) or deep-link into the Request.

**E14. Every obligation kind declares a settlement path**: inline CTA / domain event (auto-settle) / expiry. For
the deep-link case the card must show an in-progress state, or the user acts, sees no change in the count, and
stops trusting the number.

**E15. Every obligation kind has an explicit decline path — except review obligations.** `reviewOpened` is
deliberately non-user-settleable (`attention_settlement_case.dart:30-40`) and `evaluationSkip` was deliberately
removed (`evaluation_case.dart:1623`). This plan does **not** reopen that decision. Review obligations end by
sending the package, by window expiry, or by author cancellation; E16 guarantees that each of those still returns
the counter to zero without a decline gesture. Every other obligation kind keeps a truthful, socially visible
decline path, because an obligation with no exit pins the badge permanently.
*Flag if you want review obligations to become declinable — that is a domain change, not UI wiring.*

**E16. Expiry and cancellation never silently decrement the count.** They perform one atomic transition:
settle-and-dismiss the original receipt (existing `settlement_kind = 'expired'`) **and** create a distinct,
idempotent optional explanation ("the review window closed", "the author cancelled") which the user then dismisses.
Idempotency is required because the settlement sweeper may run more than once.

**E17. Private and social gestures must be unmistakable.** The × is quiet and neutral; CTAs and decline paths
carry consequence copy. Pinned unanswered forwards keep their outcome buttons and get **no** ×.

**E18. Settled ⇒ dismissed; dismissed ⇏ settled.**

### 4.4 Classification

**E4. The object key is extracted per producer**, not per category: `beacon:<id>` when the producer sets
`beaconId` (which includes trust events — `attention_intent_case.dart:412,461`), else `user:<id>` or
`system:<kind>`. "Destination person" and "attention owner" are different things and must not be conflated.

**E5. Parent notices about a child are a producer decision.** Hierarchy delivery already emits parent-scoped
intents (`beacon_hierarchy_delivery_case.dart:164`). R7 is enforced by classifying those notices as
**non-bumping optional** events on the parent and by emitting nothing else from child activity — not by relying on
key separation, which does not prevent a producer from addressing the parent. Copy must stay generic when the
source Request is unreadable to the recipient.

**E6. For You is an event surface; My Work is an object surface.** Cleared to zero, a Request leaves For You.
Watching persists through its own permanent entry (`inbox_screen.dart:313`), which must be preserved and tested.

### 4.5 Indicators

**E19. Arithmetic.** Request card: dot iff ≥1 undismissed optional event; count = live obligation receipts.
My Work tab: count = live obligation receipts in scope (unchanged); dot iff ≥1 in-scope Request has a dot.
For You tab: dot only. One badge slot per nav icon — count wins while non-zero, dot reappears at zero. Colors from
design-system tokens only; the optional token must not collide with the obligation token.

**E20. Indicators are computed over the default-visible predicate, whatever that predicate actually is.**
The archived case must be resolved explicitly rather than by slogan: archived Requests *with live obligations* are
deliberately still surfaced today (`derive_my_work_cards.dart` archive handling), while archived Requests' optional
updates are deliberately silent (redesign D7). So the rule is: **the indicator predicate is literally the predicate
of the default-visible list** — freeze it in one named function used by both the list and the badge, and test that
they cannot diverge. Corollary for E16: an expiry explanation for an archived Request must be emitted where the
user can actually see and clear it, or the count drop is again unexplained.

**E21. Settings → "Reset counters"** = client-side invalidation and refetch of every attention projection
(`FeedSessionRegistry` session reset + summary refetch), not a server recount — `surfaceSummary:176` already
computes from current authorized rows, so re-running it repairs nothing. The button's job is to discard stale
client overlays and optimistic acks.

### 4.6 Clearing boundary, staging and state

**E25. Clearing is snapshot/version based, not wall-clock based.** A watermark over `created_at` is unusable:
collapse sets `created_at = now()` on an existing row (`attention_dispatch_repository.dart:146`), so "older than my
tap" both misses and over-consumes. The clear operation takes the server-returned page/version identity of the
group as displayed, clears exactly the eligible set (optional-only, default-visible), and returns what it actually
cleared so the client can reconcile.

**E23/E26. Reordering and live arrivals need a named owner.** The existing pill and scroll anchoring serve the
offers cubit; the ordinary stream replaces its loaded items on head refresh (`attention_case.dart:602`). Before
touching the ritual, assign one owner for displayed order, staged revisions, loaded pages and scroll anchoring —
and state that a group must not be re-ordered or re-populated underneath a user who is mid-clear on it.

**E27. Clearing is one batched, versioned optimistic operation.** The ack store currently applies to top-level
feed items and skips unknown child ids (`attention_case.dart:594,688`); child-level dismissal needs a normalized
receipt/group projection so previews and counts cannot go stale.

**E33 (new). Class transitions are first-class.** Because collapse rewrites `requires_action`, an optional event
can become an obligation in place, and an obligation can be superseded. Each transition must state what happens to
the dot, the count, the card's position, and any in-flight undo token.

**E34 (new). Scope exit ≠ settlement, and authorization loss ≠ either.** When a Request leaves the viewer's scope,
its receipts keep their state and relocate surfaces atomically. When authorization is lost, content is purged from
the surface immediately without being marked settled or dismissed, and restoration on regained access is defined.

### 4.7 Recovery and reward

**E31. Zero state is a reward**: cleared card, cleared surface and cleared tab get a deliberate positive state
(illustration plus light gamification such as "cleared N today"), not a blank region that reads as a failure.

**E32. Dismiss mechanics**: hold layout height until pointer-up, animate removal through a brief placeholder
(a collapsing vertical stack of × puts the next × under the thumb), ≥48dp targets, labelled and announced,
× always visible on touch, hover toolbar on desktop, never long-press alone. Swipe-to-dismiss optional, checked
against existing horizontal gestures.

---

## 5. Classification contract

Extend `docs/contracts/updates-event-contract.json` to **schemaVersion 3**. The key is
**(event type × recipient role × state)**, not the event type alone — `attention_policy.dart:277` already decides
`requires_action` from recipient reasons.

| field | values | governs |
|---|---|---|
| `objectKeyExtractor` | producer field expression | E4 |
| `attentionClass` | per recipient role: `obligation` / `optional` / `tombstone` / `suppressed` | E13 / E7 / E2 |
| `bumps` | `true` / `false` | E3 (child-created and tombstones ⇒ `false`) |
| `settlementPath` | `inline_cta` / `domain_event` / `expiry` / `n_a` | E14 |
| `declinePath` | action id / `exempt_review` / `n_a` | E15 |
| `transitions` | to which class/state this event may mutate on collapse | E33 |
| `recoverableVia` | `request_timeline` / `people` / `room` / `history_only` / `none` | §6 |

Reconciliation is mandatory: the contract lists 15 of 29 runtime types (`attention_models.dart:9-40`). Every enum
value must appear as supported, deliberately silent, or retired, and the guard tests
(`packages/{server,client}/test/architecture/updates_event_contract_test.dart`,
`updates_event_coverage_test.dart`) must fail on **enum coverage**, not merely on fields of listed rows.

Rationale: without this, each queued feature — nested requests, request threads, availability/receptiveness,
subjective help-tag evidence, typed trust — re-litigates placement and affordance. That argument has now been
re-derived three times (IA rev 8 → redesign → this plan).

---

## 6. Recoverability (proof obligation, not an assertion)

Dismissal is only safe if the content survives somewhere the user can reach.

- The Request Timeline reads domain timeline/activity sources, **not** attention receipts
  (`activity_list.dart:42`), so request-scoped events whose content is domain state (messages, participants,
  status, offers) are genuinely recoverable — this must be demonstrated per event type, not assumed.
- Receipts themselves are deletable: `deleteSettledOlderThan` removes rows once `seen_at` and `emailed_at` are
  both set (`notification_outbox_repository.dart:118`). So "always in History" is false.
- Therefore every event type declares `recoverableVia`. If the value is `none` (candidate cases: person- and
  system-scoped notices such as trust changes framed personally, mutual connections, invite-accepted prompts),
  then either dismissal is not the only exit for that type, or those receipts are retention-exempt. Decide per
  type; do not ship a type with `none` and no exemption.
- Every card carries a visible route into its Request's Timeline (this is an entry point, not a new store).

---

## 7. Surface deltas

**My Work.** Add: dismissible coalesced optional lines (E7, E11, E12), obligation in-progress state (E14), decline
paths (E15), dot + count per E19, cleared-card state (E31), Timeline route. Unchanged: sections, filters, card
layout, badge arithmetic.

**For You.** Add: × on every tombstone outcome (E2), surface-level "Dismiss all" (E11), dot semantics per E19,
cleared-surface state (E31). Unchanged: grouping, pinned forwards, ordering, pagination — all already shipped.

---

## 8. Work outline

| # | Unit | Covers |
|---|---|---|
| U01 | Contract + product design doc | §5, §9 — schemaVersion 3, enum coverage, `docs/design/event-cards-product-design.md` |
| U02 | #151 verification pass | drive the shipped grouping against the issue's acceptance criteria; close or list residue |
| U03 | #179 gap analysis | what `my_work_obligation_block.dart` already renders vs what the issue asks; build only the gap |
| U04 | Server: clearing operation | E25 snapshot/version clearing, optional-only + default-visible predicate, returned result set |
| U05 | Server: obligation lifecycle | E14, E15 (review exemption), E16 atomic expiry conversion, E18, E33 transitions |
| U06 | Client: dismiss affordances | E2 tombstone × for every outcome, E7/E11/E12, "Dismiss all", E32 mechanics, E10 conditional undo |
| U07 | Client: feed state ownership | E23/E26/E27 — named owner for order/staging/pages, normalized child projections |
| U08 | Indicators | E19, E20 single shared predicate function |
| U09 | Settings reset + zero states | E21, E31 |
| U10 | Scope/authorization transitions | E34 |
| U11 | e2e + cleanup | full matrix, legacy path removal |

---

## 9. Test plan

1. Contract guard fails when any runtime enum value is unclassified, or any row lacks a §5 field.
2. Classification resolves per recipient role: `helpOfferSubmitted` is an obligation for the author and optional
   for everyone else.
3. Collapse that flips `requires_action` moves the receipt between classes and updates dot/count/position (E33).
4. Tombstones: a `helping` / `watching` row exposes a ×, dismissal persists, the row does not return on refresh;
   **the surface can be driven to zero rows from a realistic mixed state** (E2 + E11 + R10).
5. "Dismiss all" clears optional events and tombstones and leaves pinned unanswered forwards and obligations
   untouched.
6. Clearing is correct across a collapse that rewrote `created_at` during the operation (E25).
7. Undo restores, or refuses honestly when a newer unseen sibling holds the dedup key (E10).
8. Expiry produces exactly one idempotent explanation and never decrements the count silently (E16).
9. Settling marks dismissed; dismissing never settles (E18).
10. The indicator predicate and the default list predicate are the same function and cannot diverge (E20).
11. Scope exit relocates without settling; authorization loss purges without settling (E34).
12. Nav badge and "NEEDS YOU · N" header still cannot disagree (inherited invariant).
13. Room read-to-bottom still dismisses that discussion's receipts, and nothing else does so passively (E9).

---

## 10. Out of scope / open

- No changes to the existing durable topology (m0121) or to push/email delivery.
- No rework of My Work sections, filters or card layout beyond events, indicators and zero state.
- Notification History unchanged in design, but §6 may make some receipt classes retention-exempt.
- Legacy-client compatibility is explicitly **not** a constraint (no users; web-only client; one release plus a
  `kDefaultMinClientVersion` bump).
- Open for owner: whether review obligations should become declinable (E15) — default here is "no, keep the
  existing domain rule".
