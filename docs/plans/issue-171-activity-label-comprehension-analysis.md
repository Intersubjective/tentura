# Issue #171 — Activity labels are unclear: product / UX analysis

Status: analysis, **rev 4** (2026-09-19). Rationale only — all decisions are closed and the buildable spec is
[`issue-171-card-spec.md`](issue-171-card-spec.md).
Parent: #142 (2026-09-14 product testing). Related: #110 (closed), #151, #179.

**Premise:** this document assumes [`request-centric-attention-plan.md`](request-centric-attention-plan.md)
rev 1 (R1–R10, E1–E32, U01–U11) is **already shipped**. Revision history is in §14.

Feeds: `docs/design/event-cards-product-design.md` (plan §6 deliverable, U01) and
`docs/contracts/updates-event-contract.json` (plan §4).

---

## 1. What the ticket reports — and what it actually found

Reported: «Вы наблюдаете» (watching *what*?) and «Наши требования» ("a million dollars and a helicopter?")
are not self-explanatory.

The tester's joke is the tell. They read a **user-authored request title** as a **system status label** — a list
of demands the app was making of them. That is a genre-recognition failure, not a vocabulary failure.

The rows in question (`activity_forward_row.dart:42-43`), under a day header «СЕГОДНЯ»:

```
[✈ glyph]  Наши требования                          5 мин. назад
           Вы помогаете
```

§4 shows that the deeper cause is not what these two lines say, but what the card around them stopped carrying.

---

## 2. What the plan already fixes — remove from #171's scope

| Original cause | Resolved by | How |
|---|---|---|
| Day headers frame every row as an event, while the row delivers an object | E6, U05 | For You stops being a chronological day-grouped feed; rows are keyed by attention object. A row keyed `beacon:<id>` genuinely **is** an object, so a title headline stops being a grammar inversion. |
| Rows with no news value clutter the surface | E6 | For You shows a Request **only while it has live events**. "No news ⇒ no row" becomes a product invariant. |
| Group time vs. row time disagree | E22 | Group sort key = `max(created_at)` per group. |
| No way to make a row go away | E7, E11, E12 | Explicit ×, coalesced lines, one gesture per Request. |
| Watching reachable only from a row inside the stream | E29 | Permanent entry point independent of events. |
| "I cleared it without reading it" | E10, E30 | Mandatory undo + Timeline entry on every card. |

Consequence: **the redesign's §7.4 rule "headline = event, supporting line = subject" no longer governs For You.**
It still governs Notification History, which stays chronological and (plan §9) becomes *more* load-bearing.
Two surfaces, two grammars — this must be written down in U01, or the next person will "fix" For You back to
event headlines.

---

## 3. Residual causes — what the plan does not touch

Nothing in E1–E32 touches copy, naming, or the typographic treatment of user-authored content.

### C1′ (worse under the plan). Three provenance classes share one headline slot

E4 makes the grouping key `beacon:<id>` | `user:<id>` | `system:<kind>`, and §5.2 item 5 puts all three into the
**same row shape**. One visual slot then carries a title a user wrote, a name a user chose, and a label the system
emits, with nothing distinguishing them. That is #171's failure generalized from one row type to the whole surface.

The hook already exists: `objectKeyKind` is a mandatory contract field. Derive headline treatment from it.

| `objectKeyKind` | Headline | Rationale |
|---|---|---|
| `beacon` | «Title» + `· от <forwarder>` | user-authored ⇒ quoted and attributed |
| `user` | Name + avatar, no quotes | user-authored, but a person; the avatar carries provenance |
| `system` | Plain label + system glyph | system copy ⇒ never quoted |

### C2′ (worse under the plan). Self-echo rows become the permanent sediment of a surface built to reach zero

**E2** keeps the "Вы помогаете / Вы наблюдаете / Не интересно / Закрыт до вашего ответа" rows — the ticket's
literal subject — and reclassifies them as tombstones: *"not an attention object, never bumped, no sub-cards,
no dot, no dismiss affordance, excluded from grouping."*

Stack that against R10 ("a surface the user can bring to zero"), E6 and E31 (zero state as reward):

```
[pinned unanswered forwards]   ← no × by design (E17)
[grouped live-event rows]      ← clearable, leave at zero (E6, E7)
[tombstones]                   ← never grouped, never cleared, never leave   ← #171's rows
```

The user performs the whole clearing ritual and is left staring at the sediment. **Zero is unreachable**, E31's
reward can never fire, R10's promise is never kept. It is the "2000 unread" failure E15 correctly guards against
for obligations, re-entering through the tombstone door — and the sediment is mostly the viewer's own actions
reported back at them (five of seven stream rows in the original screenshot).

Verified: `helping` and `watching` have no trailing action at all (`activity_forward_row.dart:56-67` —
`Restore` for `notInterested`, `Hide` for `closed`/`deleted`, `default: null`). Two of five outcomes are already
unremovable today, and plan §8 test 4 would lock that in. Amendment in §6.

### C3′. «Наблюдать» is un-anchored — and E29 promotes it

On the pinned card the three actions read as three ways to participate:

```
[Предложить помощь]   Переслать   Наблюдать
```

Two are contributions; the third is a **deferral** — "I am not taking this, but keep me in the loop". The label
states neither the result nor the destination, reproducing #110's finding verbatim: *"the request disappeared from
the current view and users thought it was lost."* E17 keeps these buttons unchanged, so this is fully inside #171.

The word appears in four grammatical shapes with no shared family — `beaconHeaderWatch` «Наблюдать»,
`inboxTabWatching` «Наблюдаю», `activityForwardOutcomeWatching` «Вы наблюдаете», `beaconPeopleRoleWatcher`
«Наблюдатель» — so no single exposure teaches it, and in Russian it carries a clinical register that English
"Watch" (GitHub-anchored) does not.

**E29 raises the stakes:** Watching gets a *permanent* entry point, visible whether or not anything happened.
The word moves from an incidental row to standing furniture. Rename, if any, must land **before U09**.

Norman's gulf of evaluation: a control's label must predict the *result* of pressing it, not name the *state*
it produces.

### C4′. The leading glyph contradicts the row

The demoted row leads with a **yellow paper plane** — a *send* affordance — nudging "I sent this", while the
pinned card one section above correctly leads with the forwarder's avatar. Recognition beats recall: the avatar is
what lets a person re-identify a request they saw once. Post-plan this also collides with E4, since `user:` groups
legitimately lead with an avatar.

### C5′. The plan adds copy surfaces and specifies none of them

E31 (cleared-card / surface / tab states, "cleared N today"), E29 (entry-point label), E15 (decline copy that must
read as a social act), E16 ("the review window closed"), E10 (undo affordances). Each can recur #171's failure.
`event-cards-product-design.md` is the right home; today it holds none of these rules.

---

## 4. The regression behind the ticket: what the card stopped carrying

Established from git on 2026-09-18 (read in a detached worktree; the working tree was not touched).

Until 2026-09-14 the For You list rendered **`InboxItemTile`** — a near-full request card
(`inbox_triage_list.dart:134` at `5d024a80f^`):

```
┌──────────────────────────────────────────────┐
│ [cover]  Наши требования                 ⋮   │  BeaconIdentityTile + title + statusLine
│  40×40   ждёт ответа                         │  + BeaconOverflowMenu (→ forwards graph)
│                                              │
│  Bai Yue · Ремонт · обновлено 2 ч назад      │  BeaconCardMetadataLine
│  [нужны: руки] [инструмент] [машина]         │  BeaconRequirementsBar
│  до 20 сент.       Переслали (ава)(ава)+2 ⌄  │  InboxCardForwardsFold
│                                              │
│                             Bai Yue (ава)    │  ← expanded chain
│             «Ты же с этим возился, глянь»  ▏ │     note in italics, right-aligned
│                           [ремонт] [авто]  ▏ │     ForwardCapabilityChips = "why me"
│                                              │
│  [Предложить помощь]  Переслать   ⋯          │  InboxCardActionRow
└──────────────────────────────────────────────┘
```

A three-step decline, each step removing human provenance from the surface where the decision is made:

| When | Component | Personal note |
|---|---|---|
| until 2026-06-25 | `inbox_forward_provenance_panel.dart` (22 KB) — *"Inbox card forward trail + notes (same UI as beacon view Forwards tab)"*, with `_ProvenanceCollapsedQuote` — *"Note preview for the primary (MR-ranked) forwarder; used when provenance is collapsed"* | **visible on the card without expanding** |
| 06-25 → 09-14 | `inbox_card_forwards_fold.dart` — *"Collapsed: 'Forwarded by' + mini avatars + chevron (no note text)"* | behind a chevron, still on the card |
| since 2026-09-14 (`5d024a80f`, `fbf7db1cd`, `b041bc53e`) | `ActivityOfferCard` | **removed from the main surface entirely** |

Verifiable in one grep: in HEAD, `notePreview` is rendered by exactly one widget
(`inbox_card_forwards_fold.dart:283`), which lives only inside `InboxItemTile`, which is used in exactly two
places — `inbox_watching_screen.dart:143` and `inbox_rejected_screen.dart:83`. **The personal note and the forward
chain are now visible only on Watching and Rejected** — the two screens behind ⋮, reached after you have decided
*not* to take the request.

What replaced the whole block is `inbox_forward_attribution_copy.dart` in full:

```dart
return l10n.inboxFromForwarder(name);   // «От Vinland»
```

The first forwarder's name. No note, no chain, no capability chips, no cover, no author, no requirements — and no ⋮,
so the route into the forwards graph is gone from this surface too (`showForwardsGraphFor` survives on
`InboxItemTile:179`, `beacon_tile.dart:59`, `my_work_cards.dart:580,668,888`).

**Why this reframes the ticket.** The tester read «Наши требования» as an app-issued demand because nothing around
the title still marked it as the name of someone else's request. Previously that work was done by context — cover
on the left, «Bai Yue · Ремонт» underneath, the requirements bar, the note «Ты же с этим возился, глянь».
The card was self-evident; there was nothing to explain. What remains is two lines of text, the first of which is
just text. The «Вы помогаете» row is the end state of the same impoverishment: once everything was stripped, only
the state was left to show.

And #110 was closed on the finding that the personal note *"is part of the core relay contract, not optional
decorative metadata; it carries routing judgment and preserves human provenance."* Six weeks later the redesign
removed it from the screen where it is acted on, and the issue stayed closed. **This is a feature regression, not
a copy defect** — which is why §7 is the substantive part of this document.

---

## 5. Principles

Written into `docs/design/event-cards-product-design.md` (U01); the machine-checked half in the contract.

| | Principle | Enforcement |
|---|---|---|
| **P1** | One card, three answers: *What object* / *What's new* / *Where I stand* — three visually distinct registers | design doc + golden |
| **P2** | States are places, events are streams. A state with no change belongs in a list, never as a feed row | E6; extend to tombstones (§6) |
| **P3** | Never report the viewer's own action as news. Self-authored acts produce a transient confirmation naming the object **and the destination**, plus undo | contract field (§9) |
| **P4** | User content is quoted and attributed; system copy is not | derived from `objectKeyKind` (C1′) |
| **P5** | Controls predict outcomes, not state names | U01 checklist |
| **P6** | One concept ⇒ one word family across all four shapes (action / list / chip / role) | copy review |
| **P7** | Register split: labels about *me* are first-person or bare-participle chips («Помогаю», "Helping"); system sentences addressed to me stay second-person | design doc + golden |
| **P8** | **Rank, don't delete.** When a card is overloaded, the fix is deciding what decision it serves and ordering the evidence by weight — not removing content until it fits | §7 |

---

## 6. Tombstone rows — decided: keep them, give them a ×

Considered and rejected: retiring the tombstone class entirely and routing each outcome to an existing home
(My Work for `helping`, the E29 Watching entry for `watching`, Rejected for `notInterested`, ordinary optional
events for `closed`/`deleted`). That reaches zero but discards a real function.

**Owner's decision (2026-09-19):** tombstones stay, and gain the private ×. Their job is to say *"something was
here — the consequence of an action you or someone else took; a memory you may discard."* Everything else in E2
stands: not attention objects, never bump, no dot, no sub-cards, excluded from grouping.

This keeps E2's loss-aversion rationale and fixes C2′ at the same time, because the sediment becomes clearable and
For You can reach zero (R10, E31, criterion A6). It does not re-create E17's "two make-this-go-away gestures"
problem: E17 governs **pinned, unanswered** forwards, where a person is waiting; a tombstone is already answered,
so the quiet × is the only correct gesture on it.

It also yields the copy fix for #171's literal strings: a memory of an act is an **event**, so the second line
becomes a past-tense sentence — «Вы предложили помощь», «Вы начали следить», «Вы отказались» — instead of the
state labels «Вы помогаете» / «Вы наблюдаете». Subject, verb and tense are exactly what the reported rows lacked.

Amendments this requires in the plan (E2 text, §8 test 4) are written up in
[`issue-171-card-spec.md`](issue-171-card-spec.md) §3.

---

## 7. Target card

### 7.1 Why the old card was overloaded — and it was not "too much information"

Count the systems competing inside one rectangle: cover, title, statusLine, ⋮, «author · category · updated»,
requirements chips, room hints, deadline (error-coloured when overdue), «Переслали» + stacked avatars + chevron,
and inside the fold — name + avatar + italic note + a *second* chip system + a vertical rule, then the action row,
then the rejection message. Up to twelve systems, of which **four use chips, three use avatars, two use colour as
signal**. That is not a hierarchy; it is a list of features, each added by its own ticket.

Three specific defects, not merely density:

1. **Priority is inverted.** The highest-weight content — the human judgment, «Ты же с этим возился, глянь» — is
   the one thing behind a chevron, while the lowest-weight content (category, "updated 2h ago") is always visible.
   The fold collapses **by type**, so one important note hides exactly as thoroughly as five empty forwards.
2. **Borrowed grammar applied backwards.** Notes are right-aligned. In chat, right means *mine*; here someone
   else's words about you are set right, and the card zig-zags between alignments.
3. **Two doors to the same actions.** "Offer help" sits both in the action row and in ⋮ — duplication always means
   nobody decided where actions belong.

**Verdict: the old card was not too rich, it was unranked.** The new card "fixed" that by deletion instead of by
ranking. Both are refusals of the same decision — what this card is *for* (P8).

### 7.2 What the card is for

On For You a card serves exactly one decision: **take it / pass it on / later / no**. Everything on it is evidence
for that decision, and evidence weight sets the layout:

1. what a specific person said to me personally — the whole premise of Tentura, maximum weight;
2. what is being asked — the title;
3. why me — capability chips;
4. how urgent — deadline, but only while it is near;
5. who authored it, who is already in — social proof.

Category, "updated", room hints and non-terminal statusLine carry ~zero weight. They move to the detail screen.
That single sort removes half the old card.

### 7.3 Forwards as nested mini-cards — the unification

A forward **is** an event about the Request, from a person, carrying text — the same shape as `_EventSubcard`
(avatar + line + age) in `activity_event_subcard_block.dart`. That component already prefers `body` over the
headline *"so the personal note / event excerpt shows"* for help-offer receipts.

So this is not a new mechanism but the removal of one of two: today the relay chain (`InboxCardForwardsFold`) and
the Request's life (`ActivityEventSubcardBlock`) are separate widgets that look and behave differently. Merging
them gives what neither the old nor the new design had: **the relay chain and the Request's life become one
timeline** — and the note stops being hideable by construction, because it *is* the mini-card's body and therefore
occupies the first visible slot.

**Pinned offer (not yet answered):**

```
┌──────────────────────────────────────────────┐
│ ▢  «Наши требования»                     ⋮   │  header: identity only
│    Bai Yue · до 20 сент.                 ●   │  author + deadline (only when near)
├──────────────────────────────────────────────┤
│ (ава) Bai Yue переслал                2 ч ✕  │  ← forward as a mini-card
│   ▏ Ты же с этим возился, глянь              │     note = body, visible immediately
│   ▏ [ремонт] [авто]                          │     capability chips — here, not in the header
│                                              │
│ (ава) Глеб предложил помощь          40 м ✕  │  ← event, identical shape
│   ▏ Могу дать прицеп на выходных             │
│                                              │
│ ещё 3 · Хронология                           │
├──────────────────────────────────────────────┤
│ [Предложить помощь]   Переслать   Следить    │
└──────────────────────────────────────────────┘
```

**Same card, already answered, back in the stream with news:**

```
┌──────────────────────────────────────────────┐
│ ▢  «Наши требования»      ⟨Помогаю⟩      ⋮   │
├──────────────────────────────────────────────┤
│ (ава) 3 новых сообщения               10 м ✕ │  E11 coalescing
│ (ава) Анна вышла из запроса            2 ч ✕ │
│                                              │
│ ещё 5 · Хронология          Очистить всё     │
└──────────────────────────────────────────────┘
```

### 7.4 Rules

**K1. The header is identity only.** Cover, quoted title, author, and at most one more line — and only if it moves
the decision. It must read in 300 ms and answer "what is this and whose".

**K2. One shape for everything below the header.** Forward, help offer, message, status change: avatar + event
line + optional quoted body + age + ×. Kinds differ by glyph, never by layout. This removes two of the four chip
systems and two of the three avatar systems.

**K3. The note is the mini-card's body, never a fold.** The thing a person is looking at the card *for* cannot sit
behind a chevron. Free to implement: the mechanism exists.

**K4. Everything left-aligned.** The quote rule on the left already reads as a reply; right-alignment only breaks
the scan.

**K5. Collapse by count, not by type.** 1 visible on compact, 3 on wide — `activity_event_subcard_block.dart:77`
already does this correctly.

**K6. Coalesce same-kind events — but never coalesce notes.** Three note-less forwards ⇒ one line
(«ещё 2 переслали» + stacked avatars). Three forwards *with* notes ⇒ three mini-cards. Derived from E28
("dismissible ⇒ derivable"): the note exists nowhere else on the card, so coalescing would destroy it.

**K7. Newest first inside the card.** A relay chain tempts a genealogical order (A → B → me), but that fights the
feed. Genealogy lives in the Timeline and the forwards graph; the card answers "who handed it to me last and why",
which is the decision-relevant slice.

**K8. «ещё N» opens the Timeline; it does not expand in place.** Otherwise one noisy Request grows thirty rows tall
and pushes everything else off screen — the old card's unboundedness (280–420 dp in its goldens). This is also the
Timeline entry point E30 requires, so it removes a mechanism rather than adding one. (Open question in §7.6.)

**K9. × belongs to mini-cards only.** Today `ActivityOfferCard`'s ✕ opens a rejection dialog that messages the
author — a **social act dressed as the private gesture**, exactly what E17 forbids. «Не могу помочь» moves into ⋮
as a named action; the ✕ glyph stays quiet and means only "take this event off my screen".

**K10. One card across four surfaces.** "A Request in a list" is currently rendered four ways —
`ActivityOfferCard`, `ActivityForwardRow`, `InboxItemTile`, `my_work_cards`. The unified card serves For You,
Watching and Rejected, differing only in the action row and the pinned state. This is the insurance against them
drifting apart again.

### 7.5 Concretely: cut, move, promote

- **Cut from the card:** category; "updated N ago" (duplicated by the top mini-card's age); room hints;
  statusLine except terminal states; rejection message (Rejected screen only); ⋮ duplicates of row actions.
- **Move:** capability chips from the fold into the forward mini-card's body — they describe a *forwarder*, not
  the Request, and never belonged in the header. Deadline into the header, rendered only when near or overdue.
- **Keep and promote:** the cover (a cheap, strong marker that this is someone else's object — the direct antidote
  to "a million dollars and a helicopter"); the note, from behind the chevron into the first visible slot.

### 7.6 Open design questions

1. **Ordering inside the collapsed list.** Strictly by time means a fresh system twitch ("status changed") evicts
   the note the whole card exists for. Recommended: pin the first slot to the latest forward carrying a note, sort
   the rest by time. One line of logic; it is the single place where "sort by time" gives the wrong answer.
2. **Expand in place vs. Timeline.** K8 says Timeline everywhere (simpler, bounded, one less mechanism). On wide
   there is room and in-place expansion is cheaper cognitively. "Compact → Timeline, wide → expand" works but gives
   one control two behaviours.
3. **Honest reservation.** A card with three mini-cards is still substantial on a 360 dp screen; ten Requests in
   For You make a heavy list. The guards are a hard height ceiling and `visibleCap = 1` on compact (already the
   case) — but this needs checking against real data, not a mockup.

---

## 8. Confirmations — where object permanence actually belongs

Tombstones say *what was here*; confirmations say *where it went*. #110's confirmation contract was implemented
for forwarding only — extend it to every action that removes a card from For You:

| Action | Confirmation | Actions |
|---|---|---|
| Предложить помощь | «Вы предложили помощь по «X» — запрос теперь в «Моих делах»» | Открыть · Отменить |
| Следить | «Следите за «X» — обновления придут в «Слежу»» | Открыть · Отменить |
| Переслать | existing #110 copy | Открыть · Отменить |
| Не могу помочь | «Убрали «X» из «Для вас»» | Вернуть |

One specific, object-and-destination-naming confirmation teaches the model in a single exposure; a silent move
teaches nothing and reads as loss.

---

## 9. Contract fields to add in U01

Alongside `objectKeyKind` / `attentionClass` / `bumps` / `settlementPath` / `declinePath` / `derivableFrom`:

| field | values | governs |
|---|---|---|
| `selfAuthored` | `suppress` / `obligation` / `n_a` | P3 — an event whose actor is the viewer produces a confirmation, not a row. `obligation` is the only exception. |
| `headlineTreatment` | `quoted_attributed` / `person` / `system`, derived from `objectKeyKind` | P4 — machine-checked instead of per-widget |
| `coalescible` | `true` / `false` | K6 — an event carrying a personal note is never coalescible |

All three join the §4 guard test that **fails when a new event type omits any field**.

---

## 10. Vocabulary

Mutually exclusive; owner's call. Either way it lands **before U09** (E29 makes the word permanent furniture).

**V-A — keep the word.** Never emit a bare state; «Наблюдать» → «Следить за обновлениями» on the button; a one-line
explainer on the Watching entry. Cheap; the four-shape inconsistency and the register survive.

**V-B — rename to one anchored family (recommended).**

| Concept | Now RU | Now EN | Proposed RU | Proposed EN |
|---|---|---|---|---|
| Action on pinned card | Наблюдать | Watch | **Следить** | **Follow** |
| List / permanent entry (E29) | Наблюдаю | Watching | **Слежу** | **Following** |
| My-relation chip | Вы наблюдаете | You're watching | **Слежу** | **Following** |
| My-relation chip (help) | Вы помогаете | You're helping | **Помогаю** | **Helping** |
| Role in People | Наблюдатель | Watcher | **Следит за запросом** | **Follower** |
| Stop | Не наблюдать / Вернуть в «Нужно мне» | Stop watching | **Не следить** | **Unfollow** |
| Digest | …за которыми вы наблюдаете | …requests you watch | …**за которыми вы следите** | …**you follow** |

"Follow / Следить" is the most widely pre-learned affordance for *"keep me posted without committing"*, gives one
family across all four shapes (P6), and drops the clinical register. «Подписаться/Подписки» is even better known
but collides with paid-subscription connotation — not recommended.

Cost: values-only l10n change (keys unchanged), golden churn, and a sweep of sibling #142 issues quoting the old
word. One commit, before the next testing session.

---

## 11. Where each item lands in the plan's work outline

| Item | Unit | Note |
|---|---|---|
| P1–P8 into `event-cards-product-design.md`; `selfAuthored` / `headlineTreatment` / `coalescible` + guard test | **U01** | additive to an existing unit |
| Two-grammar rule (For You = objects, Notification History = events) written down | **U01** | stops §7.4 being re-applied to For You |
| §6 amendment — what the demoted-forward union emits | **decide before U02**, implement in U02 | server read model |
| §7 unified card: header, note restoration, capability chips, cover, K1–K10 | **U05 + U06** | U06 is already "generalized event block + dismiss"; the forward mini-card is that block with one more kind |
| Headline treatment, quoting, attribution, avatar-vs-glyph, `Semantics.label` | **U05** | acceptance criteria on the grouped stream |
| Relation chip + register split (P7) | **U05 / U06** | |
| K10 one-card consolidation across For You / Watching / Rejected | **U09 / U11** | U11 already carries legacy path removal |
| Vocabulary V-A or V-B | **before U09** | E29 |
| Action confirmations with destination + undo (§8) | **standalone, shippable now** | touches `inbox_card_actions.dart` / `forward_case.dart`, independent of grouping; highest-value fix for the #110/#171 "where did it go" failure |
| Zero-state, decline, expiry copy (E31/E15/E16) | **U10 / U07** | reviewed against P1–P8 |

**Sequencing:** do not ship a standalone anatomy fix to `ActivityForwardRow` — U05/U06 retire that widget and the
day-group feed. Only §8's confirmations are worth shipping independently.

---

## 12. Acceptance criteria, operationalized

On 5 participants who have never seen the app:

- **A1 — 5-second test.** Show one card for 5 s, hide it, ask *"what is this about, and what is your relation to
  it?"* ≥4/5 name the request (not a status) **and** the correct relation.
- **A2 — Cloze.** Cover the supporting line; ask what it probably says. ≥4/5 predict a change, not a state.
- **A3 — Action prediction.** Before tapping «Следить», ask what will happen. ≥4/5 predict "the request stays
  available and I will see updates", and ≥4/5 correctly name where it goes.
- **A4 — Recovery.** After tapping, ask them to find the request again. ≥4/5 succeed unaided within 30 s.
- **A5 — Genre.** Nobody reads a request title as an app-issued demand or a status label (the literal #171 failure).
- **A6 — Zero reachable.** After clearing everything clearable, For You is visibly empty and E31's reward fires.
  Fails today and under E2 as written.
- **A7 — Relay comprehension (new in rev 3).** Shown a pinned card, ≥4/5 can say **who** sent it to them and
  **why that person chose them**, without opening anything. This is the criterion §4's regression currently fails.

Add to plan §8: *"For You can be brought to a state with no rows"* and *"a forward's personal note is rendered on
the primary surface"* — the machine-checkable halves of A6 and A7.

---

## 13. Risks and non-goals

- **Emptier For You.** Suppressing self-echo rows and letting tombstones be cleared removes most of today's stream content.
  That is the intent (R10). Measure *rows scanned before the first meaningful tap*, not row count.
- **Denser cards.** §7 adds content back. The counterweights are K1, K5, K8 and a hard height ceiling; validate on
  real data (§7.6.3).
- **Rename churn.** V-B touches goldens, integration tests and sibling-issue wording. One commit, one sweep.
- **Non-goal:** changing what Watching *does*. Only what it promises and where it says the request went.

---

## 14. Revision history

**rev 1 → rev 2** (plan assumed shipped): root cause moved from "inverted grammar" to provenance illegibility, since
E4/E6 make a title headline correct for an object row; "no news ⇒ no row" recognized as E6; client-side suppression
replaced by the server-side E2 amendment; standalone shipping withdrawn except for confirmations; vocabulary tied to
U09; contract fields and A6 added.

**rev 2 → rev 3** (git archaeology): §4 added — the personal note and forward chain were on the primary surface
until 2026-09-14 and now render only on Watching and Rejected, so #171 is downstream of a **feature regression**,
not a copy defect. §7 added — a critique of the old card (unranked, not overloaded) and the unified card that
merges the relay chain into the plan's event sub-cards. P8, K1–K10, `coalescible` and A7 are new; §11 re-routes the
work into U05/U06/U09 accordingly.

**rev 3 → rev 4** (owner decisions): §6 replaced — the tombstone class is kept and made dismissable rather than
retired, with past-tense copy; §15 closed; the implementation spec split out into `issue-171-card-spec.md`.

---

## 15. Decisions — closed 2026-09-19

| id | Decision |
|---|---|
| **D-171-1** | **V-B** — rename to «Следить / Слежу» / "Follow / Following", before U09. |
| **D-171-2** | Tombstones **stay and gain the private ×** (§6). Not the retirement option this document originally recommended. |
| **D-171-3** | Add `selfAuthored`, `headlineTreatment`, `coalescible` to the contract under the failing guard test. |
| **D-171-4** | Build the **full unified card** (§7), not a minimal note restoration. |
| **D-171-5a** | First collapsed slot pinned to the latest note-bearing forward. |
| **D-171-5b** | «ещё N» always opens the Timeline; never expands in place. |

The buildable form of all six lives in [`issue-171-card-spec.md`](issue-171-card-spec.md).

---

## 16. Side findings (separate issues, not #171)

1. **Server writes user-facing English prose into attention receipts.** `attention_intent_case.dart:886-889,
   1002-1005` persists "You and $actorName are now connected."; the client falls back to
   `updatesFallbackBodyMutualConnectionFormed` only when server text is absent — so a Russian UI shows an English
   row (visible in #171's second screenshot). Systemic i18n hole that grows with every event type the plan adds.
2. **`actionStopWatching` renders as «Вернуть в «Нужно мне»»** while the destination tab is labelled «Ждёт меня».
3. **`activity_forward_row.dart:56-67`** gives no trailing action for `helping` / `watching` — already unremovable
   today, before E2 formalizes it.
4. **The forwards graph is unreachable from For You** — `ActivityOfferCard` has no overflow menu, so
   `showForwardsGraphFor` has no entry point on the surface where forwarding decisions are made.
